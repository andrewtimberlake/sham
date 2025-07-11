defmodule Sham.Instance do
  @moduledoc false
  use GenServer, restart: :transient

  defmodule State do
    @moduledoc false
    defstruct port: nil, server_ref: nil, opts: nil, expectations: nil, errors: nil
  end

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts)
  end

  @impl true
  def init(opts) do
    {:ok, socket} = open_socket()
    {:ok, port} = get_port(socket)
    :inet.close(socket)

    with {:ok, opts} <- configure_opts(Keyword.merge(opts, port: port)),
         {:ok, server_ref} <- start_server(opts) do
      {:ok, %State{port: port, server_ref: server_ref, opts: opts, expectations: [], errors: []}}
    else
      {:error, error} -> {:stop, error}
    end
  end

  defp configure_opts(opts, acc \\ [])
  defp configure_opts([], acc), do: validate_opts(Map.new(acc))

  defp configure_opts([{:port, port} | opts], acc) do
    configure_opts(opts, [{:port, port} | acc])
  end

  defp configure_opts([{:ssl, ssl} | opts], acc) do
    configure_opts(opts, [{:ssl, ssl} | acc])
  end

  defp configure_opts([{:keyfile, keyfile} | opts], acc) do
    configure_opts(opts, [{:keyfile, keyfile} | acc])
  end

  defp configure_opts([{:certfile, certfile} | opts], acc) do
    configure_opts(opts, [{:certfile, certfile} | acc])
  end

  defp configure_opts([_other | opts], acc), do: configure_opts(opts, acc)

  defp validate_opts(opts) do
    opts = set_default_opts(opts)

    if Map.get(opts, :ssl) do
      with true <- is_binary(opts.keyfile) and File.exists?(opts.keyfile),
           true <- is_binary(opts.certfile) and File.exists?(opts.certfile) do
        {:ok, opts}
      else
        nil -> {:error, "keyfile and certfile are required when ssl is true"}
        false -> {:error, "keyfile and certfile must exist when ssl is true"}
      end
    else
      {:ok, opts}
    end
  end

  # I’m really not sure if this is the best way to have auto-supplied test key/cert files
  @key """
  -----BEGIN PRIVATE KEY-----
  MIIEvAIBADANBgkqhkiG9w0BAQEFAASCBKYwggSiAgEAAoIBAQCuMIAq0OLRzm9S
  mY70JuAqDz6tnXCp050HfPGXmTSFWmYk9GKs+ie5yWrNX64vBqpfP0zdVbCivrn2
  ul2fNXQA8TdVFp+L+mqvNq2tFPc4Os0BRZyOg+EVEl+sNFqDElaojJuSW+YeNyAx
  KMSG+2Yg5HCTAFApWzAfJGkwXUrUegNEddKxPzs6AP9SGYbONyaynwc+B+GRQCij
  RvU5ouxhbqg93wdeo8ZljWZdOetf1/9RlMZAMazU5FhtZ0Jkgx8+ghovCqaqxcmL
  1hZsrXUC1CRIwuelzv5jplmIJXO5RmdTDhzTmKZxI/4j0yi2yXU8vmkeh1J/m3jQ
  H39nctLxAgMBAAECggEAAM+seMzMLKCemR5VK1/SnSwythegv0VlErDgHPe73UQZ
  CGRRZIW2wJRem64tv5v/rYeWuYET5wlaHtIzOFnW1G5gfc7oBLc14LEsSGffRy4o
  UE0AWmVdoNsndazbjHjDQqcYQ6KZlXWCgCfjG+wEbsehWsfLy1T0/aw/2yJMpijS
  FdtwKzS2T0F+YtVFMNEu3+ZMWPsqqk8nM91DzhtqF8pyB+pIkdkJcu6t8JN1JrkY
  4tou+ekC3dEwG37XLNabxqbOJiwidPXu7wOWisHkv43UXmUp4OEFsF+xGc3jkJvr
  SW3DD+QLRKTRHm7gghiSCDh4cbL1vu9YFr33g0UhQQKBgQDmlj0l7kvHpyFvkvg4
  4M6Y+LNka4Z2hFz1is/54phix0CtGC4I15Lqoxp+ngHFbdq7pktXQqf57IjPbXZd
  lD3kdkX4JBUkMXaGPK+OF4te+0au3UnUdrlR/qRaSsleOn1B6QKFNNRHhk2UM3Ir
  fl41+gxyOrz852xJVmw328M0sQKBgQDBYxG6EQmPgDCNDiZ/XpyiXpEm9B0Tfapk
  s4b613W64yvaZsBX4OpFhUOAL4MGozk+GLJ/RfXyBydPdhjn7OTMr/6PBI2ANDFo
  LUkApfyrYg4Y4ZZsUWxAplIgAD0JntW4uDZRbVfYoRuEyO6N9Pqi3mRnnjavOC01
  Wx7l144SQQKBgDNKpBt14GFu6d8ZwCFW0F3ypGToDib61nq///dD0kXWsKpQQJ0y
  5rlOwqv7lcVG5GrtWMD2UMslNGF/pd63BPV24aWK0TEV15mQkjR3REdCebyX+L5M
  EnkMvZ5gGF7ff9FTdX4P/FBUrZkTwIewOmCjWHVoX3WaPNorYTMjrU5hAoGAWPtH
  rdCnEINQU6b+Kb8T3VYb/ct3EX/SBlHgusym3B4pEG4U9JqF0QU3gOTbqhMyhJMC
  lrNPLlUCTnqtjRGgWVpli9LxdNsPHLsxiv3VG9qbV/F8sExqvfiJczYI38NY3YzN
  WXwxXnkK23dE5MajCIvBsTfIO6lii9lohyM+uMECgYBZ6cYoPnaimZyBBqRYXi5i
  HSaZK5/1SppcSLTqh4kx/geaonuQX+m5BbHnCNaBInJzEEgYLjQ9jPJVTwiueaws
  NDIsuVBYBmgdpHhTemeI+9EbqAfL71q3YkGpAC9lk+dNtsoLsu29EBRrZm0v9+CX
  Zy2pa/rmNE+05zAqIBQ2EQ==
  -----END PRIVATE KEY-----
  """
  @cert """
    -----BEGIN CERTIFICATE-----
  MIIEGzCCAwOgAwIBAgIUWBSAoSsaXQizu1PST/7pdUN4GI0wDQYJKoZIhvcNAQEL
  BQAwgZwxCzAJBgNVBAYTAlpBMRAwDgYDVQQIDAdHYXV0ZW5nMRUwEwYDVQQHDAxK
  b2hhbm5lc2J1cmcxDTALBgNVBAoMBFNoYW0xDTALBgNVBAsMBHRlc3QxGjAYBgNV
  BAMMEUFuZHJldyBUaW1iZXJsYWtlMSowKAYJKoZIhvcNAQkBFhthbmRyZXdAYW5k
  cmV3dGltYmVybGFrZS5jb20wHhcNMjUwNzExMTMyOTAwWhcNMzUwNzA5MTMyOTAw
  WjCBnDELMAkGA1UEBhMCWkExEDAOBgNVBAgMB0dhdXRlbmcxFTATBgNVBAcMDEpv
  aGFubmVzYnVyZzENMAsGA1UECgwEU2hhbTENMAsGA1UECwwEdGVzdDEaMBgGA1UE
  AwwRQW5kcmV3IFRpbWJlcmxha2UxKjAoBgkqhkiG9w0BCQEWG2FuZHJld0BhbmRy
  ZXd0aW1iZXJsYWtlLmNvbTCCASIwDQYJKoZIhvcNAQEBBQADggEPADCCAQoCggEB
  AK4wgCrQ4tHOb1KZjvQm4CoPPq2dcKnTnQd88ZeZNIVaZiT0Yqz6J7nJas1fri8G
  ql8/TN1VsKK+ufa6XZ81dADxN1UWn4v6aq82ra0U9zg6zQFFnI6D4RUSX6w0WoMS
  VqiMm5Jb5h43IDEoxIb7ZiDkcJMAUClbMB8kaTBdStR6A0R10rE/OzoA/1IZhs43
  JrKfBz4H4ZFAKKNG9Tmi7GFuqD3fB16jxmWNZl0561/X/1GUxkAxrNTkWG1nQmSD
  Hz6CGi8KpqrFyYvWFmytdQLUJEjC56XO/mOmWYglc7lGZ1MOHNOYpnEj/iPTKLbJ
  dTy+aR6HUn+beNAff2dy0vECAwEAAaNTMFEwHQYDVR0OBBYEFLfRpaF+erim0ZPc
  MukfAZMcBWUWMB8GA1UdIwQYMBaAFLfRpaF+erim0ZPcMukfAZMcBWUWMA8GA1Ud
  EwEB/wQFMAMBAf8wDQYJKoZIhvcNAQELBQADggEBAI9rS7Tpu4YlVDID7q+WtasT
  HrrlY/NITTWSmICtknly8yn34ZB6MyHKdQliShkN7kPyKfUoYekeEw66leaVKrhX
  oM1QjCmyMgtDkMRo6yQduCsonIpg4PVjEjNmpYLYypG+r/KHo4AdJll0XaSqdEdu
  uGW/B6t55fdXwZ0VF0fmhae/lLNur5VYuyUBKk9kAo9pMuis7AcQwJmFZXn87HcD
  CE3vBca7XuFxN9+DQ13YXfFz17dsed/T/MDm5V/evyClDO/u3n8Kicd01ssxssLP
  yerSi/kSvrCBRnnb61o5wRMFBzQyBrxOCWor57PmZa8Wnq0xZh+ZtzIZdgKzhVk=
  -----END CERTIFICATE-----
  """

  defp set_default_opts(opts) do
    opts
    |> Map.put_new(:ssl, false)
    |> Map.put_new_lazy(:keyfile, fn ->
      keyfile = Path.join(System.tmp_dir!(), "sham-#{System.unique_integer([:positive])}-key.pem")
      File.write!(keyfile, String.trim(@key))
      keyfile
    end)
    |> Map.put_new_lazy(:certfile, fn ->
      certfile =
        Path.join(System.tmp_dir!(), "sham-#{System.unique_integer([:positive])}-cert.pem")

      File.write!(certfile, String.trim(@cert))
      certfile
    end)
    |> Map.put_new_lazy(:server, fn ->
      server = Application.get_env(:sham, :server)

      if server do
        server
      else
        cond do
          match?({:module, _}, Code.ensure_compiled(Bandit)) ->
            :bandit

          match?({:module, _}, Code.ensure_compiled(Plug.Cowboy)) ->
            :plug_cowboy

          true ->
            raise "No supported server found. Please add one of the following to your deps: bandit, plug_cowboy"
        end
      end
    end)
  end

  if match?({:module, _}, Code.ensure_compiled(Bandit)) do
    defp start_server(%{server: :bandit} = opts) do
      server_opts = [port: opts.port, startup_log: false, plug: {Sham.Plug, pid: self()}]

      server_opts =
        if opts.ssl do
          Keyword.merge(server_opts,
            scheme: :https,
            keyfile: opts.keyfile,
            certfile: opts.certfile
          )
        else
          server_opts
        end

      {:ok, pid} = Bandit.start_link(server_opts)
      {:ok, {:bandit, pid}}
    end
  end

  if match?({:module, _}, Code.ensure_compiled(Plug.Cowboy)) do
    defp start_server(%{server: :plug_cowboy} = opts) do
      server_ref = make_ref()

      {:ok, _pid} =
        if opts.ssl do
          Plug.Cowboy.https(Sham.Plug, [pid: self()],
            ref: server_ref,
            port: opts.port,
            keyfile: opts.keyfile,
            certfile: opts.certfile
          )
        else
          Plug.Cowboy.http(Sham.Plug, [pid: self()], ref: server_ref, port: opts.port)
        end

      {:ok, {:plug_cowboy, server_ref}}
    end
  end

  defp start_server(%{server: server}) do
    raise "Unsupported server: #{inspect(server)}"
  end

  @impl true
  def handle_call(:setup, _from, %{port: port} = state) do
    {:reply, {:ok, port}, state}
  end

  def handle_call(
        {:expect_none, method, path},
        _from,
        %{expectations: expectations} = state
      ) do
    expectations = [
      {:expect_none, method, path, nil, make_ref(), :waiting}
      | expectations
    ]

    {:reply, :ok, %{state | expectations: expectations}}
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
      {:expect_none, _method, _path, _callback, _ref, _state} ->
        {:reply, :expect_none, state}

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
          server_ref: server_ref,
          errors: errors,
          expectations: expectations
        } = state
      ) do
    shutdown_server(server_ref)

    if state.opts[:keyfile] && Regex.match?(~r/sham-\d+-key\.pem$/, state.opts[:keyfile]) do
      File.rm(state.opts.keyfile)
    end

    if state.opts[:certfile] && Regex.match?(~r/sham-\d+-cert\.pem$/, state.opts[:certfile]) do
      File.rm(state.opts.certfile)
    end

    case errors do
      [error | _] ->
        {:stop, :normal, {:error, error}, nil}

      [] ->
        {:stop, :normal, parse_expectation_results(expectations, state), nil}
    end
  end

  defp shutdown_server({:bandit, pid}) do
    GenServer.stop(pid)
  end

  defp shutdown_server({:plug_cowboy, server_ref}) do
    Plug.Cowboy.shutdown(server_ref)
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
           {_expectation, method, path, _callback, _ref, {:error, error}} | _tail
         ],
         _state
       ) do
    {:error, "Received error on #{method} to #{path}: #{inspect(error)}"}
  end

  defp parse_expectation_results(
         [
           {_expectation, _method, _path, _callback, _ref, {:exception, exception}} | _tail
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
    if opts.ssl, do: "HTTPS", else: "HTTP"
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
