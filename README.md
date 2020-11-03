# Argos

**TODO: Add description**

## Installation

```
mix run deps.get
```

## Development

Start dockerized Elasticsearch using
```bash
docker-compose up
```

Running the cowboy server using
```bash
mix run --no-halt
```

Running individual exs scripts for data import (example)
```bash
mix run lib/harvesting/projects.exs --script 2020-01-10
```
The `--script` option is required to prevent mix trying to start the application (again).

## Troubleshooting

If Elasticsearch fails to create files on startup, try chmod in data/elasticsearch to your host user.