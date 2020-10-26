# Argos

**TODO: Add description**

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `argos` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:argos, "~> 0.1.0"}
  ]
end
```

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at [https://hexdocs.pm/argos](https://hexdocs.pm/argos).

## Development

Start dockerized Elasticsearch using
```bash
docker-compose up
```

Running the cowboy server using
```bash
mix run --no-halt
```

## Troubleshooting

If Elasticsearch fails to create files on startup, try chmod in data/elasticsearch to your host user.