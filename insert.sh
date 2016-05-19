#!/bin/bash

COMPOSE=$(which docker-compose)
DOCKER=$(which docker)

NAME="neo"

if [ -z $COMPOSE ] || ! [ -x $COMPOSE ]; then
	echo "No se encontró docker-compose en el sistema"
	exit 1
fi

if [ -z $DOCKER ] || ! [ -x $DOCKER ]; then
	echo "No se encontró docker en el sistema"
	exit 1
fi

ID=$($COMPOSE ps -q $CONT_NAME 2>/dev/null)
SHORT_ID=$(echo $ID | cut -c1-10)

if [ -z $ID ] || ! $($DOCKER ps | grep $SHORT_ID >/dev/null 2>&1); then
	echo "No se encontró contenedor de neo4j"
	exit 2
fi

echo "Insertando datos..."
$DOCKER exec -it $ID bin/neo4j-shell -file import/create.cypher

echo "Generando índices"
$DOCKER exec -it $ID bin/neo4j-shell -file import/cleanup.cypher