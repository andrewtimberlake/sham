# Sham

An Elixir mock HTTP(S) server useful for testing HTTP(S) clients.

![example workflow](https://github.com/andrewtimberlake/sham/actions/workflows/main.yml/badge.svg)
[![Hex version badge](https://img.shields.io/hexpm/v/sham.svg)](https://hex.pm/packages/sham)
[![Hex Docs](https://img.shields.io/badge/hex-docs-lightgreen.svg)](https://hexdocs.pm/sham/)
[![License badge](https://img.shields.io/hexpm/l/sham.svg)](https://github.com/andrewtimberlake/sham/blob/master/LICENSE)

Documentation is available at <https://hexdocs.pm/sham>.

## Usage

```elixir
  sham = Sham.start(ssl: true, certfile: "/path/to/cert.pem", keyfile: "/path/to/key.pem")

  Sham.expect(sham, "GET", "/", fn conn ->
    Plug.Conn.resp(conn, 200, "Hello world")
  end)

  {:ok, 200, response_body} = HttpClient.get("https://localhost:#{sham.port}")

  assert response_body == "Hello world"
```

### Accessing the body of a request

By default, Plug does not parse the body of a request. If you need to access the body of a request, you will need to manually call

#### JSON body

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

#### URL-encoded body

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

#### Form-data body

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

## SSL

Sham has a test certificate and key in `priv/ssl` to make it easier to get started.

To use your own certificate and key, set the `:certfile` and `:keyfile` options when starting Sham.

```elixir
Sham.start(ssl: true, certfile: "/path/to/cert.pem", keyfile: "/path/to/key.pem")
```

### Generate Keys

```bash
openssl req -x509 -nodes -days 3650 -newkey rsa:2048 -keyout priv/ssl/key.pem -out priv/ssl/cert.pem
```

## About

Thank you for using this library.

If you’d like to support me, I am available for Elixir consulting and online pair programming.
