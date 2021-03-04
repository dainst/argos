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

### Troubleshooting

If Elasticsearch fails to create files on startup, try chown in data/elasticsearch to your host user.

## Deployment

### 1. __Locally__, build an updated docker image

```bash
docker build -t dainst/argos:latest .
```

### 2.  __Locally__, push the new docker image to dockerhub:
```bash
docker push dainst/argos:latest
```

### 3. __Serverside__, pull the newest image

```bash
docker pull dainst/argos:latest
```

### 4. __Serverside__, if you need the newest [ES mapping](https://github.com/dainst/argos/blob/main/priv/elasticsearch-mapping.json), update the repository

```bash
sudo git -C /usr/local/src/argos pull <git remote>
```

The current setup of cloning/pulling the complete repository on the deployment machine, just for the newest ES mapping and the docker-compose.prod.yml, is somewhat overkill. We could switch to just copying those files to a designated place?

### 5. __Serverside__, restart the service
```bash
sudo systemctl restart argos
```

### 6. __Serverside__, run release [functions](lib/release.ex) as required by your recent changes
For example, you can update the ES mapping and reindex all projectes by running:
```
docker exec -it argos-app /app/bin/argos eval "Argos.Release.update_mapping()"
docker exec -it argos-app /app/bin/argos eval "Argos.Release.seed_projects()"
```