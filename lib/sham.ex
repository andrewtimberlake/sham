defmodule Sham do
  defstruct pid: nil, port: nil

  def start(opts \\ []) do
    case DynamicSupervisor.start_child(Sham.Supervisor, {Sham.Instance, opts}) do
      {:ok, pid} ->
        {:ok, port} = GenServer.call(pid, :setup)

        ExUnit.Callbacks.on_exit({Sham.Instance, pid}, fn ->
          case GenServer.call(pid, :on_exit) do
            :ok ->
              :ok

            {:error, error} ->
              raise ExUnit.AssertionError, error

            {:exception, {exception, stacktrace}} ->
              reraise exception, stacktrace

            {:error, expected, actual} ->
              raise ExUnit.AssertionError,
                    "TestServer expected #{inspect(expected)} but received #{inspect(actual)}"
          end
        end)

        %Sham{pid: pid, port: port}

      other ->
        other
    end
  end

  def expect(sham, callback) do
    expect(sham, nil, nil, callback)
  end

  def expect(%{pid: pid} = sham, method, path, callback)
      when is_pid(pid) and is_function(callback, 1) do
    GenServer.call(pid, {:expect, method, path, callback})
    sham
  end
end
