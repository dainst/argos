# Argos

https://api.idai.world/

## Prerequisites
* Docker
* docker-compose
* Elixir >= 1.11

## Development

Install dependencies
```
mix deps.get
```

Start dockerized Elasticsearch on http://localhost:9200 using
```bash
docker-compose up
```

Run application stack (harvesting scripts and search endpoint on http://localhost:4001 ) using
```bash
mix run --no-halt
```

Seed some initial data
```bash
mix seed
```

### Testing
```bash
mix test
```

### Troubleshooting

If Elasticsearch fails to create files on startup, try chown in data/elasticsearch to your host user.

## Deployment

1. __Locally__, build an updated docker image

```bash
docker build -f DockerfileAPI -t dainst/argos_api:latest .
docker build -f DockerfileHarvesting -t dainst/argos_harvesting:latest .
```

2.  __Locally__, push the new docker image(s) to dockerhub:
```bash
docker push dainst/argos_api:latest
docker push dainst/argos_harvesting:latest
```

Optionally tag and push also with explicit version number. Ensure version match those specified in the mix.exs files. See also https://semver.org/lang/de/.
```
docker tag dainst/argos_api:latest dainst/argos_api:MAJOR.MINOR.PATCH
docker tag dainst/argos_harvesting:latest dainst/argos_harvesting:MAJOR.MINOR.PATCH

docker push dainst/argos_api:MAJOR.MINOR.PATCH
docker push dainst/argos_harvesting:MAJOR.MINOR.PATCH
```

3. __Locally__ (optional), if change occurred, copy config files to server:
- docker-compose.{prod|test}.yml
- traefik.toml 
- priv/elasticsearch-mapping.json

See VM documentation for the appropriate locations.

4. __Serverside__, pull the latest image(s)
```bash
docker pull dainst/argos_api:latest
docker pull dainst/argos_harvesting:latest
```

Alternatively pull specific versions. To use the specific version you have to adjust the variables defined in the .env file.

5. __Serverside__, restart the services
```bash
cd /opt/argos && docker-compose -f docker-compose.deploy.yml up -d
```

6. __Serverside__, run release functions for [harvesting](apps/argos_harvesting/lib/release_cli.ex) or [core](apps/argos_core/lib/release_cli.ex) as required by your recent changes. For example, you can update the ES mapping and reindex all [collections](https://collections.dainst.org) by running:

```
docker exec -it argos-harvesting /app/bin/harvesting eval "ArgosCore.ReleaseCLI.update_mapping()"
docker exec -it argos-harvesting /app/bin/harvesting eval "ArgosHarvesting.ReleaseCLI.seed_collections()"
```
