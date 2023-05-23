defmodule Sham.Plug do
  def init([pid]), do: pid

  def call(%{method: method, request_path: request_path} = conn, pid) do
    case GenServer.call(pid, {:get_callback, method, request_path}) do
      {_method, _request_path, callback, ref} ->
        conn = Plug.Conn.fetch_query_params(conn)

        try do
          callback.(conn)
        else
          conn ->
            GenServer.call(pid, {:put_result, ref, :called})
            conn
        rescue
          exception ->
            stacktrace = __STACKTRACE__
            GenServer.call(pid, {:put_result, ref, {:exception, {exception, stacktrace}}})
            Plug.Conn.resp(conn, 500, "")
        end

      _ ->
        error = "Unexpected request #{method} #{request_path}"
        GenServer.call(pid, {:put_error, error})
        Plug.Conn.resp(conn, 500, error)
    end
  end
end
