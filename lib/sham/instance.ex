defmodule Sham.Instance do
  use GenServer, restart: :transient

  defmodule State do
    defstruct port: nil, cowboy_ref: nil, opts: nil, expectations: nil, errors: nil
  end

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts)
  end

  @impl true
  def init(opts) do
    {:ok, socket} = open_socket()
    {:ok, port} = get_port(socket)
    :inet.close(socket)
    cowboy_ref = make_ref()

    result =
      if Keyword.get(opts, :ssl, false) do
        with keyfile <-
               Keyword.get(opts, :keyfile, Application.app_dir(:sham, "priv/ssl/key.pem")),
             {:keyfile, true} <- {:keyfile, File.exists?(keyfile)},
             certfile <-
               Keyword.get(opts, :certfile, Application.app_dir(:sham, "priv/ssl/cert.pem")),
             {:certfile, true} <- {:certfile, File.exists?(certfile)} do
          Plug.Cowboy.https(Sham.Plug, [pid: self()],
            ref: cowboy_ref,
            port: port,
            keyfile: keyfile,
            certfile: certfile
          )
        else
          {:keyfile, false} ->
            {:error, "keyfile does not exist at #{Keyword.get(opts, :keyfile)}"}

          {:certfile, false} ->
            {:error, "certfile does not exist at #{Keyword.get(opts, :certfile)}"}
        end
      else
        Plug.Cowboy.http(Sham.Plug, [pid: self()], ref: cowboy_ref, port: port)
      end

    case result do
      {:ok, _pid} ->
        {:ok,
         %State{port: port, cowboy_ref: cowboy_ref, opts: opts, expectations: [], errors: []}}

      {:error, error} ->
        {:stop, error}
    end
  end

  @impl true
  def handle_call(:setup, _from, %{port: port} = state) do
    {:reply, {:ok, port}, state}
  end

  def handle_call(
        {expectation, method, path, callback},
        _from,
        %{expectations: expectations} = state
      ) do
    expectations = [{expectation, method, path, callback, make_ref(), :waiting} | expectations]

    {:reply, :ok, %{state | expectations: expectations}}
  end

  def handle_call({:get_callback, method, path}, _from, %{expectations: expectations} = state) do
    expectations
    |> Enum.reverse()
    |> Enum.sort(&sort_expectations/2)
    |> Enum.find(fn
      {:expect_once, _, _, _callback, _ref, state} when state != :waiting -> false
      {_, ^method, ^path, _callback, _ref, _state} -> true
      {_, nil, ^path, _callback, _ref, _state} -> true
      {_, nil, nil, _callback, _ref, _state} -> true
      {_, _, _, _, _, _} -> false
    end)
    |> case do
      {_expectation, method, path, callback, ref, _state} ->
        {:reply, {method, path, callback, ref}, state}

      _ ->
        {:reply, did_exceed?(expectations, method, path), state}
    end
  end

  def handle_call({:put_result, ref, result}, _from, %{expectations: expectations} = state) do
    expectations =
      expectations
      |> Enum.map(fn
        {expectation, method, path, callback, ^ref, :waiting} ->
          {expectation, method, path, callback, ref, result}

        other ->
          other
      end)
      |> Enum.filter(& &1)

    {:reply, :ok, %{state | expectations: expectations}}
  end

  def handle_call({:put_error, error}, _from, %{errors: errors} = state) do
    {:reply, :ok, %{state | errors: [error | errors]}}
  end

  def handle_call(:pass, _from, %{expectations: expectations} = state) do
    expectations = Enum.map(expectations, &put_elem(&1, 5, :called))

    {:reply, :ok, %{state | errors: [], expectations: expectations}}
  end

  def handle_call(
        :on_exit,
        _from,
        %{
          cowboy_ref: cowboy_ref,
          errors: errors,
          expectations: expectations
        } = state
      ) do
    Plug.Cowboy.shutdown(cowboy_ref)

    case errors do
      [error | _] ->
        {:stop, :normal, {:error, error}, nil}

      [] ->
        {:stop, :normal, parse_expectation_results(expectations, state), nil}
    end
  end

  defp did_exceed?(expectations, method, path) do
    expectations
    |> Enum.filter(fn
      {:expect_once, ^method, ^path, _callback, _ref, _state} -> true
      {:expect_once, nil, nil, _callback, _ref, _state} -> true
      _ -> false
    end)
    |> case do
      [] -> nil
      [_ | _] -> :exceeded
    end
  end

  # Sort expectations so that specified method and path always takes precedence over unspecified
  defp sort_expectations({_, nil, nil, _, _, _}, {_, nil, nil, _, _, _}),
    do: true

  defp sort_expectations({_, method, path, _, _, _}, {_, nil, nil, _, _, _})
       when not is_nil(method) and not is_nil(path),
       do: true

  defp sort_expectations({_, nil, nil, _, _, _}, {_, method, path, _, _, _})
       when not is_nil(method) and not is_nil(path),
       do: false

  defp sort_expectations(_, _),
    do: true

  defp parse_expectation_results([], _state) do
    :ok
  end

  defp parse_expectation_results(
         [{expectation, method, path, _callback, _ref, :waiting} | _tail],
         state
       )
       when expectation in [:expect, :expect_once] do
    {:error,
     "No #{scheme(state)}#{method_error(method)} request was received by Sham#{path_error(path)}"}
  end

  defp parse_expectation_results(
         [
           {:expect, method, path, _callback, _ref, {:error, error}} | _tail
         ],
         _state
       ) do
    {:error, "Received error on #{method} to #{path}: #{inspect(error)}"}
  end

  defp parse_expectation_results(
         [
           {:expect, _method, _path, _callback, _ref, {:exception, exception}} | _tail
         ],
         _state
       ) do
    {:exception, exception}
  end

  defp parse_expectation_results(
         [{_expectation, _method, _path, _callback, _ref, _state} | tail],
         state
       ) do
    parse_expectation_results(tail, state)
  end

  defp scheme(%State{opts: opts}) do
    if(Keyword.get(opts, :ssl, false), do: "HTTPS", else: "HTTP")
  end

  defp method_error(nil), do: ""
  defp method_error(method), do: " #{method}"

  defp path_error(nil), do: ""
  defp path_error(path), do: " at #{path}"

  defp open_socket(),
    do: :gen_tcp.listen(0, [:binary, packet: :line, active: false, reuseaddr: true])

  defp get_port(socket),
    do: :inet.port(socket)
end
