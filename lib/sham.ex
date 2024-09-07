defmodule Sham do
  @derive {Inspect, only: [:port]}
  defstruct pid: nil, port: nil

  @opaque t :: %__MODULE__{}

  @moduledoc """
  Sham is a mock HTTP(S) server useful for testing HTTP(S) clients.
  """

  @doc """
  Starts a new Sham instance.

  ## Options

  * `:ssl` - Whether to start the server in SSL mode. Defaults to `false`.
  * `:keyfile` - The path to an SSL keyfile. Defaults to an internal self-signed key.
  * `:certfile` - The path to an SSL certfile. Defaults to an internal self-signed certificate.

  ## Examples

      sham = Sham.start()
      Sham.expect(sham, fn conn -> Plug.Conn.send_resp(conn, 200, "Hello") end)

      sham = Sham.start(ssl: true)
      Sham.expect(sham, fn conn -> Plug.Conn.send_resp(conn, 200, "Hello") end)

  """
  @type sham_opts :: [ssl: boolean(), keyfile: String.t(), certfile: String.t()]
  @spec start(sham_opts()) :: Sham.t() | {:error, term()}
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

  @doc """
  Expect at least one call to the Sham instance using any method and at any path.

  ## Examples

      iex> sham = Sham.start()
      iex> Sham.expect(sham, fn conn -> Plug.Conn.send_resp(conn, 200, "Hello") end)
      iex> ShamTest.get("http://localhost:#\{sham.port}/hello")
      {:ok, 200, "Hello"}
      iex> ShamTest.post("http://localhost:#\{sham.port}/other", "foo=bar")
      {:ok, 200, "Hello"}

      sham = Sham.start()
      Sham.expect(sham, fn conn -> Plug.Conn.send_resp(conn, 200, "Hello") end)
      ** (ExUnit.AssertionError) No HTTP request was received by Sham

  If no request is sent to the sham port, an assertion error will be raised.
  """
  @spec expect(Sham.t(), (Plug.Conn.t() -> Plug.Conn.t())) :: Sham.t()
  def expect(%{pid: pid} = sham, callback)
      when is_pid(pid) and is_function(callback, 1) do
    :ok = GenServer.call(pid, {:expect, nil, nil, callback})
    sham
  end

  @doc """
  Expect at least one call to the Sham instance using the given method and path.

  - `method` - The HTTP method to expect. Should be one of `"GET"`, `"POST"`, `"PUT"`, `"PATCH"`, `"DELETE"`, `"HEAD"`, or `"OPTIONS"` or (Anything Plug supports).
  - `path` - The path to expect

  ## Examples

      iex> sham = Sham.start()
      iex> Sham.expect(sham, "GET", "/hello", fn conn -> Plug.Conn.send_resp(conn, 200, "Hello") end)
      iex> ShamTest.get("http://localhost:#\{sham.port}/hello")
      {:ok, 200, "Hello"}

      # Sending a request that does not match an expectation will result in an assertion error
      ShamTest.post("http://localhost:#\{sham.port}/other", "foo=bar")
      {:ok, 500, "Unexpected request to Sham: POST /other"}
      ** (ExUnit.AssertionError) Unexpected request to Sham: POST /other

  If no request is sent to the sham port using the given method and path, an assertion error will be raised.
  """
  @spec expect(
          Sham.t(),
          method :: String.t(),
          path :: String.t(),
          (Plug.Conn.t() -> Plug.Conn.t())
        ) :: Sham.t()
  def expect(%{pid: pid} = sham, method, path, callback)
      when is_pid(pid) and is_function(callback, 1) do
    :ok = GenServer.call(pid, {:expect, method, path, callback})
    sham
  end

  @doc """
  Expect exactly one call to the Sham instance using any method and at any path.

  You can stack multiple calls to `expect_once/4` to expect multiple requests.

  ## Examples

      iex> sham = Sham.start()
      iex> Sham.expect_once(sham, fn conn -> Plug.Conn.send_resp(conn, 200, "Hello") end)
      iex> ShamTest.get("http://localhost:#\{sham.port}/hello")
      {:ok, 200, "Hello"}

      iex> sham = Sham.start()
      iex> Sham.expect_once(sham, fn conn -> Plug.Conn.send_resp(conn, 200, "Hello") end)
      iex> ShamTest.get("http://localhost:#\{sham.port}/hello")
      {:ok, 200, "Hello"}
      iex> Sham.expect_once(sham, fn conn -> Plug.Conn.send_resp(conn, 200, "World") end)
      iex> ShamTest.get("http://localhost:#\{sham.port}/hello")
      {:ok, 200, "World"}

      # Sending a more than one request will result in an assertion error
      ShamTest.post("http://localhost:#\{sham.port}/other", "foo=bar")
      {:ok, 500, "Exceeded expected requests to Sham: POST /other"}
      ** (ExUnit.AssertionError) Exceeded expected requests to Sham: POST /other

  If a request is sent to the sham port using a different method or path, an assertion error will be raised.
  """
  @spec expect_once(Sham.t(), (Plug.Conn.t() -> Plug.Conn.t())) :: Sham.t()
  def expect_once(%{pid: pid} = sham, callback)
      when is_pid(pid) and is_function(callback, 1) do
    :ok = GenServer.call(pid, {:expect_once, nil, nil, callback})
    sham
  end

  @doc """
  Expect exactly one call to the Sham instance using the given method and path.

  You can stack multiple calls to `expect_once/4` to expect multiple requests.

  - `method` - The HTTP method to expect. Should be one of `"GET"`, `"POST"`, `"PUT"`, `"PATCH"`, `"DELETE"`, `"HEAD"`, or `"OPTIONS"` or (Anything Plug supports).
  - `path` - The path to expect

  ## Examples

      iex> sham = Sham.start()
      iex> Sham.expect_once(sham, "GET", "/hello", fn conn -> Plug.Conn.send_resp(conn, 200, "Hello") end)
      iex> ShamTest.get("http://localhost:#\{sham.port}/hello")
      {:ok, 200, "Hello"}

      iex> sham = Sham.start()
      iex> Sham.expect_once(sham, "GET", "/hello", fn conn -> Plug.Conn.send_resp(conn, 200, "Hello") end)
      iex> ShamTest.get("http://localhost:#\{sham.port}/hello")
      {:ok, 200, "Hello"}
      iex> Sham.expect_once(sham, "GET", "/hello", fn conn -> Plug.Conn.send_resp(conn, 200, "World") end)
      iex> ShamTest.get("http://localhost:#\{sham.port}/hello")
      {:ok, 200, "World"}

      # Sending a more than one request with the same method and path will result in an assertion error
      ShamTest.get("http://localhost:#\{sham.port}/hello")
      {:ok, 500, "Exceeded expected requests to Sham: GET /hello"}
      ** (ExUnit.AssertionError) Exceeded expected requests to Sham: GET /hello

  If no request is sent to the sham port using the given method and path, an assertion error will be raised.
  """
  @spec expect_once(
          Sham.t(),
          method :: String.t(),
          path :: String.t(),
          (Plug.Conn.t() -> Plug.Conn.t())
        ) :: Sham.t()
  def expect_once(%{pid: pid} = sham, method, path, callback)
      when is_pid(pid) and is_function(callback, 1) do
    :ok = GenServer.call(pid, {:expect_once, method, path, callback})
    sham
  end

  @doc """
  Expect no requests to the Sham instance using any method or path.

  ## Examples

      sham = Sham.start()
      Sham.expect_none(sham)
      # Sending a request will result in an assertion error
      ShamTest.get("http://localhost:#\{sham.port}/hello")
      {:ok, 500, "A request was received by Sham when none were expected: GET /hello"}
      ** (ExUnit.AssertionError) A request was received by Sham when none were expected: GET /hello
  """
  @spec expect_none(Sham.t()) :: Sham.t()
  def expect_none(%{pid: pid} = sham) do
    :ok = GenServer.call(pid, {:expect_none, nil, nil})
    sham
  end

  @doc """
  Expect no requests to the Sham instance for a given method and path.

  - `method` - The HTTP method to expect. Should be one of `"GET"`, `"POST"`, `"PUT"`, `"PATCH"`, `"DELETE"`, `"HEAD"`, or `"OPTIONS"` or (Anything Plug supports).
  - `path` - The path to expect
  """
  @spec expect_none(Sham.t(), method :: String.t(), path :: String.t()) :: Sham.t()
  def expect_none(%{pid: pid} = sham, method, path) do
    :ok = GenServer.call(pid, {:expect_none, method, path})
    sham
  end

  @doc """
  Provide a callback to handle any requests to the Sham instance without assertions.

  No exceptions will be raised if no requests are sent to the sham port.

  ## Examples

      iex> sham = Sham.start()
      iex> Sham.stub(sham, fn conn -> Plug.Conn.send_resp(conn, 200, "Hello") end)
      iex> ShamTest.get("http://localhost:#\{sham.port}/hello")
      {:ok, 200, "Hello"}
      iex> ShamTest.post("http://localhost:#\{sham.port}/other", "foo=bar")
      {:ok, 200, "Hello"}
  """
  @spec stub(Sham.t(), (Plug.Conn.t() -> Plug.Conn.t())) :: Sham.t()
  def stub(%{pid: pid} = sham, callback)
      when is_pid(pid) and is_function(callback, 1) do
    :ok = GenServer.call(pid, {:stub, nil, nil, callback})
    sham
  end

  @doc """
  Provide a callback to handle any requests to the Sham instance using the given method and path without assertions.

  No exceptions will be raised if no requests are sent to the sham port using the given method and path.

  ## Examples

      iex> sham = Sham.start()
      iex> Sham.stub(sham, "GET", "/hello", fn conn -> Plug.Conn.send_resp(conn, 200, "Hello") end)
      iex> ShamTest.get("http://localhost:#\{sham.port}/hello")
      {:ok, 200, "Hello"}

      # Sending a request with a different method and path will result in an assertion error
      ShamTest.post("http://localhost:#\{sham.port}/other", "foo=bar")
      {:ok, 500, "Unexpected request to Sham: POST /other"}
      ** (ExUnit.AssertionError) Unexpected request to Sham: POST /other
  """
  @spec stub(
          Sham.t(),
          method :: String.t(),
          path :: String.t(),
          (Plug.Conn.t() -> Plug.Conn.t())
        ) :: Sham.t()
  def stub(%{pid: pid} = sham, method, path, callback)
      when is_pid(pid) and is_function(callback, 1) do
    :ok = GenServer.call(pid, {:stub, method, path, callback})
    sham
  end

  @doc """
  Forces the Sham instance to pass regardless of whether a valid request was sent to the sham port or not.

  ## Examples

      iex> sham = Sham.start()
      iex> Sham.expect(sham, "GET", "/hello", fn conn -> Plug.Conn.send_resp(conn, 200, "Hello") end)
      iex> ShamTest.post("http://localhost:#\{sham.port}/other", "foo=bar")
      {:ok, 500, "Unexpected request to Sham: POST /other"}
      iex> Sham.pass(sham)

      iex> sham = Sham.start()
      iex> Sham.expect(sham, "GET", "/hello", fn conn -> Plug.Conn.send_resp(conn, 200, "Hello") end)
      iex> Sham.pass(sham)

  No assertions will be raised.
  """
  @spec pass(Sham.t()) :: Sham.t()
  def pass(%{pid: pid} = sham) do
    :ok = GenServer.call(pid, :pass)
    sham
  end
end
