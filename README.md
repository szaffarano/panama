## Prerequisitos

- docker-compose 1.5+
- docker 1.11+

## Ejecución

```sh
# descarga datos y configura el ambiente para correr neo4j
$ ./prepare-data.sh
$ docker-compose up -d
```

## Carga de datos

```sh
# inserta en neo
$ docker exec -it docker_neo_1 bin/neo4j-shell -file import/create.cypher

# depura, indexa, etc
$ docker exec -it docker_neo_1 bin/neo4j-shell -file import/cleanup.cypher
```
