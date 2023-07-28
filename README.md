# Sham

An Elixir mock HTTP(S) server useful for testing HTTP(S) clients.

![example workflow](https://github.com/andrewtimberlake/sham/actions/workflows/main.yml/badge.svg)
[![Hex version badge](https://img.shields.io/hexpm/v/sham.svg)](https://hex.pm/packages/sham)
[![Hex Docs](https://img.shields.io/badge/hex-docs-lightgreen.svg)](https://hexdocs.pm/sham/)
[![License badge](https://img.shields.io/hexpm/l/sham.svg)](https://github.com/andrewtimberlake/sham/blob/master/LICENSE)

## Usage

```elixir
  sham = Sham.start(ssl: true, certfile: "/path/to/cert.pem", keyfile: "/path/to/key.pem")

  Sham.expect(sham, "GET", "/", fn conn ->
    Plug.Conn.resp(conn, 200, "Hello world")
  end)

  {:ok, 200, response_body} = HttpClient.get("https://localhost:#{sham.port}")

  assert response_body == "Hello world"
```

## Installation

The package can be installed by adding `sham` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:sham, "~> 1.0"}
  ]
end
```

Documentation is available at <https://hexdocs.pm/sham>.

## SSL

### Generate Keys

```bash
openssl req -x509 -nodes -days 3650 -newkey rsa:2048 -keyout priv/ssl/key.pem -out priv/ssl/cert.pem
```

## About

Thank you for using this library.

If you’d like to support me, I am available for Elixir consulting and online pair programming.

I am also the founder of [Sitesure](https://sitesure.net) which provides uptime and background monitoring, notifying you immediately when your services go down.
