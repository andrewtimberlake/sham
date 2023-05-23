# Sham

An Elixir mock HTTP(S) server useful for testing HTTP(S) clients.

## Usage

```elixir
  sham = Sham.start(ssl: true, certfile: "/path/to/cert.pem", keyfile: "/path/to/key.pem")

  Sham.expect(sham, "GET", "/", fn conn ->
    Plug.Conn.resp(conn, 200, "Hello world")
  end)

  {:ok, {{_, 200, 'OK'}, _, body}} =
    :httpc.request(:get, {"https://localhost:#{sham.port}", []}, [], [])

  response_body = IO.iodata_to_binary(body)
  assert response_body == "Hello world"
```

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `sham` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:sham, "~> 0.1.0"}
  ]
end
```

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at <https://hexdocs.pm/sham>.

## SSL

### Generate Keys

```bash
openssl req -x509 -nodes -days 3650 -newkey rsa:2048 -keyout priv/ssl/key.pem -out priv/ssl/cert.pem
```
