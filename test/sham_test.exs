defmodule ShamTest do
  use ExUnit.Case
  import ExUnit.CaptureLog

  doctest Sham

  test "Basic expectation" do
    sham = Sham.start(ssl: false)

    Sham.expect(sham, fn conn ->
      assert conn.method == "GET"
      assert conn.request_path == "/"
      Plug.Conn.resp(conn, 200, "Hello world")
    end)

    {:ok, 200, body} = get("http://localhost:#{sham.port}")
    assert body == "Hello world"
  end

  test "HTTPS expectation" do
    %Sham{} = sham = Sham.start(ssl: true)

    Sham.expect(sham, fn conn ->
      assert conn.method == "GET"
      assert conn.request_path == "/"
      Plug.Conn.resp(conn, 200, "Hello world")
    end)

    {:ok, 200, body} = get("https://localhost:#{sham.port}")
    assert body == "Hello world"
  end

  test "HTTPS with missing key file" do
    assert {:error, <<"keyfile does not exist at ", _::binary>>} =
             Sham.start(ssl: true, keyfile: "/path/to/key.pem")
  end

  test "HTTPS with missing cert file" do
    assert {:error, <<"certfile does not exist at ", _::binary>>} =
             Sham.start(ssl: true, certfile: "/path/to/cert.pem")
  end

  test "Expectation with specific method and path" do
    sham = Sham.start()

    Sham.expect(sham, "POST", "/endpoint", fn conn ->
      assert conn.method == "POST"
      assert conn.request_path == "/endpoint"
      Plug.Conn.resp(conn, 201, "Hello world")
    end)

    {:ok, 201, body} = post("http://localhost:#{sham.port}/endpoint", "")

    response_body = IO.iodata_to_binary(body)
    assert response_body == "Hello world"
  end

  test "Expectation with error" do
    sham = Sham.start()

    Sham.expect(sham, "GET", "/", fn _conn ->
      raise "error"
    end)

    capture_log(fn ->
      {:ok, 500, ""} = get("http://localhost:#{sham.port}/")
    end)

    on_exit({Sham.Instance, sham.pid}, fn ->
      assert {:exception, {%RuntimeError{}, _stacktrace}} = GenServer.call(sham.pid, :on_exit)
    end)
  end

  test "Expectation with no request (no method or path)" do
    sham = Sham.start()

    Sham.expect(sham, fn conn ->
      assert conn.method == "POST"
      assert conn.request_path == "/endpoint"
      Plug.Conn.resp(conn, 201, "Hello world")
    end)

    on_exit({Sham.Instance, sham.pid}, fn ->
      assert {:error, "No HTTP request was received by Sham"} = GenServer.call(sham.pid, :on_exit)
    end)
  end

  test "Expectation with no request" do
    sham = Sham.start()

    Sham.expect(sham, "POST", "/endpoint", fn conn ->
      assert conn.method == "POST"
      assert conn.request_path == "/endpoint"
      Plug.Conn.resp(conn, 201, "Hello world")
    end)

    on_exit({Sham.Instance, sham.pid}, fn ->
      assert {:error, "No HTTP POST request was received by Sham at /endpoint"} =
               GenServer.call(sham.pid, :on_exit)
    end)
  end

  test "HTTPS expectation with no request" do
    sham = Sham.start(ssl: true)

    Sham.expect(sham, "POST", "/endpoint", fn conn ->
      assert conn.method == "POST"
      assert conn.request_path == "/endpoint"
      Plug.Conn.resp(conn, 201, "Hello world")
    end)

    on_exit({Sham.Instance, sham.pid}, fn ->
      assert {:error, "No HTTPS POST request was received by Sham at /endpoint"} =
               GenServer.call(sham.pid, :on_exit)
    end)
  end

  defp request(uri, method, body \\ "")

  defp request(uri, method, body) when is_binary(uri), do: request(URI.parse(uri), method, body)

  defp request(%URI{scheme: scheme, host: host, port: port, path: path}, method, body) do
    scheme = String.to_existing_atom(scheme)
    transport_opts = if(scheme == :https, do: [verify: :verify_none], else: [])

    with {:ok, conn} <-
           Mint.HTTP.connect(scheme, host, port,
             mode: :passive,
             transport_opts: transport_opts
           ),
         {:ok, conn, ref} <- Mint.HTTP.request(conn, method, path || "/", [], body) do
      receive_response(conn, ref, 100, [])
    end
  end

  defp receive_response(conn, ref, status, body) do
    with {:ok, conn, responses} <- Mint.HTTP.recv(conn, 0, 200) do
      receive_response(responses, conn, ref, status, body)
    end
  end

  defp receive_response([], conn, ref, status, body) do
    receive_response(conn, ref, status, body)
  end

  defp receive_response([response | responses], conn, ref, status, body) do
    case response do
      {:status, ^ref, status} ->
        receive_response(responses, conn, ref, status, body)

      {:headers, ^ref, _headers} ->
        receive_response(responses, conn, ref, status, body)

      {:data, ^ref, data} ->
        receive_response(responses, conn, ref, status, [data | body])

      {:done, ^ref} ->
        _ = Mint.HTTP.close(conn)
        {:ok, status, body |> Enum.reverse() |> IO.iodata_to_binary()}

      {:error, ^ref, _reason} = error ->
        error
    end
  end

  defp get(uri) do
    request(uri, "GET")
  end

  defp post(uri, body) do
    request(uri, "POST", body)
  end
end
