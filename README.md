# Argos

**TODO: Add description**

## Development

Install dependencies
```
mix deps.get
```

Start dockerized Elasticsearch on http://localhost:9200 using
```bash
docker-compose up
```

Run the cowboy server (harvesting scripts and search endpoint on http://localhost:4001 ) using
```bash
mix run --no-halt
```

Add ES mapping project data
```bash
mix update-mapping
```

Seed project data
```bash
mix seed.projects
```

### Troubleshooting

If Elasticsearch fails to create files on startup, try chown in data/elasticsearch to your host user.

## Deployment

1. __Locally__, build an updated docker image

```bash
docker build -f DockerfileAPI -t dainst/argos_api:latest .
docker build -f DockerfileAggregation -t dainst/argos_aggregation:latest .
```

2.  __Locally__, push the new docker image to dockerhub:
```bash
docker push dainst/argos_api:latest
docker push dainst/argos_aggregation:latest
```

3. __Serverside__, pull the newest image

```bash
docker pull dainst/argos_api:latest
docker pull dainst/argos_aggregation:latest
```

4. __Serverside__, if you need the newest [ES mapping](https://github.com/dainst/argos/blob/main/priv/elasticsearch-mapping.json), update the repository

```bash
sudo git -C /usr/local/src/argos pull
```

The current setup of cloning/pulling the complete repository on the deployment machine, just for the newest ES mapping and the docker-compose.prod.yml, is somewhat overkill. We could switch to just copying those files to a designated place?

5. __Serverside__, restart the service

TODO: Update for umbrella project.
```bash
sudo systemctl restart argos
```

6. __Serverside__, run release [functions](lib/release.ex) as required by your recent changes
For example, you can update the ES mapping and reindex all projects by running:
```
docker exec -it argos-api /app/bin/api eval "ArgosAPI.Release.update_mapping()"
docker exec -it argos-aggregation /app/bin/aggregation eval "ArgosAggregation.Release.seed_projects()"
```
