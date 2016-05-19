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
# Donde <nombre contenedor neo> es el nombre o id del container
# ejecutando la base neo4j

# inserta en neo
$ docker exec -it <nombre contenedor neo> bin/neo4j-shell -file import/create.cypher

# depura, indexa, etc
$ docker exec -it <nombre contenedor neo> bin/neo4j-shell -file import/cleanum.cypher
```

O bien utilizando el script que automatiza lo anterior

```sh
$ ./insert.sh
```
