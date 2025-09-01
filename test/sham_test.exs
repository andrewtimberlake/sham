defmodule ShamTest do
  use ExUnit.Case
  import ExUnit.CaptureLog

  doctest Sham

  [
    :bandit,
    :plug_cowboy
  ]
  |> Enum.each(fn server ->
    describe "expect (with #{server})" do
      setup do
        Application.put_env(:sham, :server, unquote(server))
      end

      test "Basic expectation" do
        sham = Sham.start(ssl: false)

        Sham.expect(sham, fn conn ->
          Plug.Conn.send_resp(conn, 200, "Hello world")
        end)

        assert {:ok, 200, body} = get("http://localhost:#{sham.port}")
        assert body == "Hello world"

        assert {:ok, 200, body} = get("http://localhost:#{sham.port}")
        assert body == "Hello world"
      end

      test "Basic expectation with assertion in callback" do
        sham = Sham.start(ssl: false)

        Sham.expect(sham, fn conn ->
          assert conn.request_path == "/"
          Plug.Conn.send_resp(conn, 200, "Hello world")
        end)

        get("http://localhost:#{sham.port}/wat")

        on_exit({Sham.Instance, sham.pid}, fn ->
          assert {:exception, {%ExUnit.AssertionError{}, _}} = GenServer.call(sham.pid, :on_exit)
        end)
      end

      test "HTTPS expectation" do
        %Sham{} = sham = Sham.start(ssl: true)

        Sham.expect(sham, fn conn ->
          assert conn.method == "GET"
          assert conn.request_path == "/"
          Plug.Conn.send_resp(conn, 200, "Hello world")
        end)

        assert {:ok, 200, body} = get("https://localhost:#{sham.port}")
        assert body == "Hello world"
      end

      test "HTTPS (http/1.1) expectation" do
        %Sham{} = sham = Sham.start(ssl: true)

        Sham.expect(sham, fn conn ->
          assert conn.method == "GET"
          assert conn.request_path == "/"
          Plug.Conn.send_resp(conn, 200, "Hello world")
        end)

        {:ok, %Mint.HTTP1{} = conn} =
          Mint.HTTP.connect(:https, "localhost", sham.port,
            mode: :passive,
            protocols: [:http1],
            transport_opts: [
              verify: :verify_none
            ]
          )

        {:ok, conn, ref} = Mint.HTTP.request(conn, "GET", "/", [], "")
        assert {:ok, 200, body} = receive_response(conn, ref, 100, [])

        assert body == "Hello world"
      end

      test "HTTPS (h2) expectation" do
        %Sham{} = sham = Sham.start(ssl: true)

        Sham.expect(sham, fn conn ->
          assert conn.method == "GET"
          assert conn.request_path == "/"
          Plug.Conn.send_resp(conn, 200, "Hello world")
        end)

        {:ok, %Mint.HTTP2{} = conn} =
          Mint.HTTP.connect(:https, "localhost", sham.port,
            mode: :passive,
            protocols: [:http2],
            transport_opts: [
              verify: :verify_none
            ]
          )

        {:ok, conn, ref} = Mint.HTTP.request(conn, "GET", "/", [], "")
        assert {:ok, 200, body} = receive_response(conn, ref, 100, [])

        assert body == "Hello world"
      end

      test "HTTPS with missing key file" do
        assert {:error, "keyfile and certfile must exist when ssl is true"} =
                 Sham.start(ssl: true, keyfile: "/path/to/key.pem", certfile: nil)
      end

      test "HTTPS with missing cert file" do
        assert {:error, "keyfile and certfile must exist when ssl is true"} =
                 Sham.start(ssl: true, certfile: "/path/to/cert.pem", keyfile: nil)
      end

      test "HTTPS with invalid key file" do
        assert {:error, "keyfile and certfile must exist when ssl is true"} =
                 Sham.start(
                   ssl: true,
                   certfile: "/path/to/cert.pem",
                   keyfile: "/path/to/wrong_key.pem"
                 )
      end

      test "HTTPS with invalid cert file" do
        assert {:error, "keyfile and certfile must exist when ssl is true"} =
                 Sham.start(
                   ssl: true,
                   certfile: "/path/to/wrong_cert.pem",
                   keyfile: "/path/to/key.pem"
                 )
      end

      test "Expectation with specific method and path" do
        sham = Sham.start()

        Sham.expect(sham, "POST", "/endpoint", fn conn ->
          assert conn.method == "POST"
          assert conn.request_path == "/endpoint"
          Plug.Conn.send_resp(conn, 201, "Hello world")
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
          assert {:ok, 500, <<"** (RuntimeError)", _::binary>>} =
                   get("http://localhost:#{sham.port}/")
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
          Plug.Conn.send_resp(conn, 201, "Hello world")
        end)

        on_exit({Sham.Instance, sham.pid}, fn ->
          assert {:error, "No HTTP request was received by Sham"} =
                   GenServer.call(sham.pid, :on_exit)
        end)
      end

      test "Expectation with no request" do
        sham = Sham.start()

        Sham.expect(sham, "POST", "/endpoint", fn conn ->
          assert conn.method == "POST"
          assert conn.request_path == "/endpoint"
          Plug.Conn.send_resp(conn, 201, "Hello world")
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
          Plug.Conn.send_resp(conn, 201, "Hello world")
        end)

        on_exit({Sham.Instance, sham.pid}, fn ->
          assert {:error, "No HTTPS POST request was received by Sham at /endpoint"} =
                   GenServer.call(sham.pid, :on_exit)
        end)
      end

      test "expectation with timeout" do
        sham = Sham.start(ssl: false)

        Sham.expect(sham, fn conn ->
          Process.sleep(2000)
          Plug.Conn.send_resp(conn, 200, "Hello world")
        end)

        assert {:error, _, %Mint.TransportError{reason: :timeout}, _} =
                 get("http://localhost:#{sham.port}", timeout: 100)

        on_exit({Sham.Instance, sham.pid}, fn ->
          assert {:error, "No HTTP request was received by Sham"} =
                   GenServer.call(sham.pid, :on_exit)
        end)
      end
    end

    describe "expect_once (with #{server})" do
      setup do
        Application.put_env(:sham, :server, unquote(server))
      end

      test "Basic expectation" do
        sham = Sham.start(ssl: false)

        Sham.expect_once(sham, fn conn ->
          assert conn.method == "GET"
          assert conn.request_path == "/"
          Plug.Conn.send_resp(conn, 200, "Hello world")
        end)

        assert {:ok, 200, body} = get("http://localhost:#{sham.port}")
        assert body == "Hello world"

        {:ok, 500, "Exceeded expected requests to Sham: GET /"} =
          get("http://localhost:#{sham.port}")

        on_exit({Sham.Instance, sham.pid}, fn ->
          assert {:error, "Exceeded expected requests to Sham: GET /"} =
                   GenServer.call(sham.pid, :on_exit)
        end)
      end

      test "Basic expectation with assertion error in callback" do
        sham = Sham.start(ssl: false)

        Sham.expect_once(sham, fn conn ->
          assert conn.request_path == "/wat"
          Plug.Conn.send_resp(conn, 200, "Hello world")
        end)

        get("http://localhost:#{sham.port}")

        on_exit({Sham.Instance, sham.pid}, fn ->
          assert {:exception, {%ExUnit.AssertionError{}, _}} = GenServer.call(sham.pid, :on_exit)
        end)
      end

      test "Stacked expect_once" do
        sham = Sham.start(ssl: false)

        Sham.expect_once(sham, "GET", "/path", fn conn ->
          assert conn.method == "GET"
          assert conn.request_path == "/path"
          Plug.Conn.send_resp(conn, 200, "Hello world")
        end)

        Sham.expect_once(sham, "GET", "/path", fn conn ->
          assert conn.method == "GET"
          assert conn.request_path == "/path"
          Plug.Conn.send_resp(conn, 200, "Hello world 2")
        end)

        assert {:ok, 200, body} = get("http://localhost:#{sham.port}/path")
        assert body == "Hello world"

        assert {:ok, 200, body} = get("http://localhost:#{sham.port}/path")
        assert body == "Hello world 2"

        assert {:ok, 500, "Exceeded expected requests to Sham: GET /path"} =
                 get("http://localhost:#{sham.port}/path")

        on_exit({Sham.Instance, sham.pid}, fn ->
          assert {:error, "Exceeded expected requests to Sham: GET /path"} =
                   GenServer.call(sham.pid, :on_exit)
        end)
      end

      test "Specified and unspecified paths" do
        sham = Sham.start(ssl: false)

        Sham.expect_once(sham, fn conn ->
          Plug.Conn.send_resp(conn, 200, "Hello world")
        end)

        Sham.expect_once(sham, "GET", "/path", fn conn ->
          Plug.Conn.send_resp(conn, 200, "Hello world 2")
        end)

        assert {:ok, 200, body} = get("http://localhost:#{sham.port}/")
        assert body == "Hello world"

        assert {:ok, 200, body} = get("http://localhost:#{sham.port}/path")
        assert body == "Hello world 2"

        assert {:ok, 500, "Exceeded expected requests to Sham: GET /path"} =
                 get("http://localhost:#{sham.port}/path")

        on_exit({Sham.Instance, sham.pid}, fn ->
          assert {:error, "Exceeded expected requests to Sham: GET /path"} =
                   GenServer.call(sham.pid, :on_exit)
        end)
      end

      test "Expectation with no request (no method or path)" do
        sham = Sham.start()

        Sham.expect_once(sham, fn conn ->
          assert conn.method == "POST"
          assert conn.request_path == "/endpoint"
          Plug.Conn.send_resp(conn, 201, "Hello world")
        end)

        on_exit({Sham.Instance, sham.pid}, fn ->
          assert {:error, "No HTTP request was received by Sham"} =
                   GenServer.call(sham.pid, :on_exit)
        end)
      end

      test "Expectation with no request" do
        sham = Sham.start()

        Sham.expect_once(sham, "POST", "/endpoint", fn conn ->
          assert conn.method == "POST"
          assert conn.request_path == "/endpoint"
          Plug.Conn.send_resp(conn, 201, "Hello world")
        end)

        on_exit({Sham.Instance, sham.pid}, fn ->
          assert {:error, "No HTTP POST request was received by Sham at /endpoint"} =
                   GenServer.call(sham.pid, :on_exit)
        end)
      end

      test "HTTPS expectation with no request" do
        sham = Sham.start(ssl: true)

        Sham.expect_once(sham, "POST", "/endpoint", fn conn ->
          assert conn.method == "POST"
          assert conn.request_path == "/endpoint"
          Plug.Conn.send_resp(conn, 201, "Hello world")
        end)

        on_exit({Sham.Instance, sham.pid}, fn ->
          assert {:error, "No HTTPS POST request was received by Sham at /endpoint"} =
                   GenServer.call(sham.pid, :on_exit)
        end)
      end

      test "expectation with timeout" do
        sham = Sham.start(ssl: false)

        Sham.expect_once(sham, fn conn ->
          Process.sleep(2000)
          Plug.Conn.send_resp(conn, 200, "Hello world")
        end)

        assert {:error, _, %Mint.TransportError{reason: :timeout}, _} =
                 get("http://localhost:#{sham.port}", timeout: 100)

        on_exit({Sham.Instance, sham.pid}, fn ->
          assert {:error, "No HTTP request was received by Sham"} =
                   GenServer.call(sham.pid, :on_exit)
        end)
      end
    end

    describe "expect_none (with #{server})" do
      setup do
        Application.put_env(:sham, :server, unquote(server))
      end

      test "Basic expectation" do
        sham = Sham.start(ssl: false)

        Sham.expect_none(sham)

        assert {:ok, 500, "A request was received by Sham when none were expected: GET /"} =
                 get("http://localhost:#{sham.port}")

        on_exit({Sham.Instance, sham.pid}, fn ->
          assert {:error, "A request was received by Sham when none were expected: GET /"} =
                   GenServer.call(sham.pid, :on_exit)
        end)
      end

      test "Expectation with a request (no method or path)" do
        sham = Sham.start()

        Sham.expect_none(sham)

        assert {:ok, 500, "A request was received by Sham when none were expected: GET /"} =
                 get("http://localhost:#{sham.port}")

        on_exit({Sham.Instance, sham.pid}, fn ->
          assert {:error, "A request was received by Sham when none were expected: GET /"} =
                   GenServer.call(sham.pid, :on_exit)
        end)
      end

      test "Expectation with specific method and path" do
        sham = Sham.start()

        Sham.expect_none(sham, "POST", "/endpoint")

        Sham.stub(sham, "GET", "/endpoint", fn conn ->
          Plug.Conn.send_resp(conn, 200, "Hello world")
        end)

        assert {:ok, 200, _body} = get("http://localhost:#{sham.port}/endpoint")

        on_exit({Sham.Instance, sham.pid}, fn ->
          assert :ok = GenServer.call(sham.pid, :on_exit)
        end)
      end
    end

    describe "stub (with #{server})" do
      setup do
        Application.put_env(:sham, :server, unquote(server))
      end

      test "callback" do
        sham = Sham.start(ssl: false)

        Sham.stub(sham, fn conn ->
          Plug.Conn.send_resp(conn, 200, "Hello world")
        end)

        Sham.stub(sham, "GET", "/path", fn conn ->
          Plug.Conn.send_resp(conn, 200, "Hello world 2")
        end)

        assert {:ok, 200, body} = get("http://localhost:#{sham.port}")
        assert body == "Hello world"
        assert {:ok, 200, body} = get("http://localhost:#{sham.port}/path")
        assert body == "Hello world 2"
        assert {:ok, 200, body} = get("http://localhost:#{sham.port}")
        assert body == "Hello world"
      end

      test "callback with assertion error" do
        sham = Sham.start(ssl: false)

        Sham.stub(sham, fn conn ->
          assert conn.request_path == "/path"
          Plug.Conn.send_resp(conn, 200, "Hello world")
        end)

        Sham.stub(sham, "GET", "/path", fn conn ->
          Plug.Conn.send_resp(conn, 200, "Hello world")
        end)

        # Should raise an assertion error
        get("http://localhost:#{sham.port}/")

        assert {:ok, 200, body} = get("http://localhost:#{sham.port}/path")
        assert body == "Hello world"

        on_exit({Sham.Instance, sham.pid}, fn ->
          assert {:exception, {%ExUnit.AssertionError{}, _}} = GenServer.call(sham.pid, :on_exit)
        end)
      end

      test "expectation with timeout" do
        sham = Sham.start(ssl: false)

        Sham.stub(sham, fn conn ->
          Process.sleep(2000)
          Plug.Conn.send_resp(conn, 200, "Hello world")
        end)

        assert {:error, _, %Mint.TransportError{reason: :timeout}, _} =
                 get("http://localhost:#{sham.port}", timeout: 100)

        on_exit({Sham.Instance, sham.pid}, fn ->
          assert :ok = GenServer.call(sham.pid, :on_exit)
        end)
      end
    end

    describe "pass (with #{server})" do
      setup do
        Application.put_env(:sham, :server, unquote(server))
      end

      test "Basic expectation" do
        sham = Sham.start(ssl: false)

        Sham.expect(sham, fn conn ->
          Plug.Conn.send_resp(conn, 200, "Hello world")
        end)

        Sham.pass(sham)

        on_exit({Sham.Instance, sham.pid}, fn ->
          assert :ok = GenServer.call(sham.pid, :on_exit)
        end)
      end
    end
  end)

  defp request(uri, method, body, opts)

  defp request(uri, method, body, opts) when is_binary(uri),
    do: request(URI.parse(uri), method, body, opts)

  defp request(%URI{scheme: scheme, host: host, port: port, path: path}, method, body, opts) do
    scheme = String.to_existing_atom(scheme)
    transport_opts = if(scheme == :https, do: [verify: :verify_none], else: [])
    transport_opts = Keyword.merge(transport_opts, Keyword.get(opts, :transport_opts, []))

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

  def get(uri, opts \\ []) do
    request(uri, "GET", "", opts)
  end

  def post(uri, body, opts \\ []) do
    request(uri, "POST", body, opts)
  end
end
