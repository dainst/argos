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
mix run lib/harvesting/projects.exs
```

## Troubleshooting

If Elasticsearch fails to create files on startup, try chmod in data/elasticsearch to your host user.