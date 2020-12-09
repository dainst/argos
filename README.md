# Argos

**TODO: Add description**

## Installation

```
mix deps.get
```

## Development

Start dockerized Elasticsearch on http://localhost:9200 using
```bash
docker-compose up
```

Run the cowboy server (harvesting scripts and search endpoint on http://localhost:4001 ) using
```bash
mix run --no-halt
```

Running individual exs scripts for data import (example)
```bash
mix run lib/harvesting/projects.exs --script 2020-01-10
```
The `--script` option is required to prevent mix trying to start the application (again).

## Troubleshooting

If Elasticsearch fails to create files on startup, try chown in data/elasticsearch to your host user.
