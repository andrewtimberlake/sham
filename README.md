# Sham

An Elixir mock HTTP(S) server useful for testing HTTP(S) clients.

![example workflow](https://github.com/andrewtimberlake/sham/actions/workflows/main.yml/badge.svg)
[![Hex version badge](https://img.shields.io/hexpm/v/sham.svg)](https://hex.pm/packages/sham)
[![Hex Docs](https://img.shields.io/badge/hex-docs-lightgreen.svg)](https://hexdocs.pm/sham/)
[![License badge](https://img.shields.io/hexpm/l/sham.svg)](https://github.com/andrewtimberlake/sham/blob/master/LICENSE)

Documentation is available at <https://hexdocs.pm/sham>.

## Installation

The package can be installed by adding `sham` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:sham, "~> 1.0", only: :test}
  ]
end
```

If you’re not using Sham in a web project, you’ll also need to add either `:plug_cowboy` or `:bandit` to your test dependencies.

```elixir
def test_deps do
  [
    {:plug_cowboy, "~> 2.0", only: :test},
    {:bandit, "~> 1.0", only: :test}
  ]
end
```

Sham should pick up on the correct server automatically, but if it doesn't, you can specify it manually.

```elixir
config :sham, server: :plug_cowboy
# or
config :sham, server: :bandit
```

## Usage

### Basic usage

```elixir
  sham = Sham.start()

  Sham.expect(sham, "GET", "/", fn conn ->
    Plug.Conn.resp(conn, 200, "Hello world")
  end)

  {:ok, 200, response_body} = HttpClient.get("http://localhost:#{sham.port}")

  assert response_body == "Hello world"
```

### SSL

```elixir
  sham = Sham.start(ssl: true)
  # or, optionally with your own certificate and key
  # sham = Sham.start(ssl: true, certfile: "/path/to/cert.pem", keyfile: "/path/to/key.pem")

  Sham.expect(sham, "GET", "/", fn conn ->
    Plug.Conn.resp(conn, 200, "Hello world")
  end)

  {:ok, 200, response_body} = HttpClient.get("https://localhost:#{sham.port}")

  assert response_body == "Hello world"
```

## Assertions in the expectation callback

While you can place assertions in the expectation callback, they will only surface in the test run if there are no failed assertions in the rest of the test.
Sham catches any assertion errors, returns a 500 response with the error and then re-raises the assertion in an on_exit callback which is only run after the test has finished.

```elixir
Sham.expect(sham, "GET", "/", fn conn ->
  # This assertion will fail because the request path is not /wrong
  # Sham will return the assertion error in a 500 response and re-raise it in an on_exit callback.
  assert conn.request_path == "/wrong"
  Plug.Conn.resp(conn, 200, "Hello world")
end)

# This assertion will fail because the result from the expection will be a 500 response with the assertion error and the test will fail without the assertion from the expectation callback.
assert {:ok, 200, "Hello world"} = HttpClient.get("https://localhost:#{sham.port}")

# This will work because there is no assertion here so the assertion from the expectation callback will be surfaced at the end of the test.
# The test will fail with the assertion error from the expectation callback.
HttpClient.get("https://localhost:#{sham.port}")
```

## Accessing the body of a request

By default, Plug does not parse the body of a request. If you need to access the body of a request, you will need to manually call

### JSON body

```elixir
Sham.expect(sham, "POST", "/", fn conn ->
  conn =
    Plug.Parsers.call(
      conn,
      Plug.Parsers.init(parsers: [:json], json_decoder: Jason)
    )

  assert conn.body_params == %{"key" => "value"}
end)
```

### URL-encoded body

```elixir
Sham.expect(sham, "POST", "/", fn conn ->
  conn =
    Plug.Parsers.call(
      conn,
      Plug.Parsers.init(parsers: [:urlencoded], pass: ["*/*"])
    )

  assert conn.body_params == %{"key" => "value"}
end)
```

### Form-data body

```elixir
Sham.expect(sham, "POST", "/", fn conn ->
  conn =
    Plug.Parsers.call(
      conn,
      Plug.Parsers.init(parsers: [:multipart], pass: ["*/*"])
    )

  assert conn.body_params == %{"key" => "value"}

  assert %{"file" => %Plug.Upload{path: "/path/to/file", filename: "file.txt"}} = conn.body_params
end)
```

### Raw body

```elixir
Sham.expect(sham, "POST", "/", fn conn ->
  {:ok, body, conn} = Plug.Conn.read_body(conn)

  assert body == "raw body"
end)
```

## Generating SSL key and cert for testing

```bash
openssl req -x509 -nodes -days 3650 -newkey rsa:2048 -keyout test/ssl/key.pem -out test/ssl/cert.pem
```

## About

Thank you for using this library.

If you’d like to support me, [I am available for Elixir consulting and online pair programming](https://andrewtimberlake.com/hire).
