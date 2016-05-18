#!/bin/bash

BASE="."

WORK=$BASE/neo
PLUGINS=$WORK/plugins
DATA=$WORK/data

# conf de docker
VOLUME_NAME="panama-data"
NETWORK="common"

docker volume ls -q | grep $VOLUME_NAME > /dev/null || (echo "creando volumen docker..." && docker volume create --name $VOLUME_NAME)
docker network ls -f "name=$NETWORK" | grep $NETWORK > /dev/null || (echo "creando network docker..." && docker network create  $NETWORK)

for d in $WORK $PLUGINS $DATA
do
    ([ -d $d ] && rm -rf $d) || mkdir -p $d
done

curl -q -# -L https://github.com/neo4j-contrib/neo4j-apoc-procedures/releases/download/1.0.0/apoc-1.0.0.jar \
    -o $PLUGINS/apoc-1.0.0.jar

if ! [ -f data-csv.zip ]; then
    echo "Descargando datos..."
    curl -q -# -L -OL https://cloudfront-files-1.publicintegrity.org/offshoreleaks/data-csv.zip
else 
    echo "Ya existe data-csv.zip, no se descarga"
fi

unzip -o -j data-csv.zip -d $DATA

sed -i s"/\\\//g" $DATA/Addresses.csv

cat <<EOF > $DATA/create.cypher
match (n) detach delete n;
create constraint on (n:Node) assert n.node_id is unique;

USING PERIODIC COMMIT 10000
LOAD CSV WITH HEADERS FROM "file:///Addresses.csv" AS row MERGE (n:Node {node_id:row.node_id}) ON CREATE SET n = row, n:Address;
USING PERIODIC COMMIT 10000
LOAD CSV WITH HEADERS FROM "file:///Intermediaries.csv" AS row MERGE (n:Node {node_id:row.node_id})  ON CREATE SET n = row, n:Intermediary;
USING PERIODIC COMMIT 10000
LOAD CSV WITH HEADERS FROM "file:///Entities.csv" AS row MERGE (n:Node {node_id:row.node_id})        ON CREATE SET n = row, n:Entity;
USING PERIODIC COMMIT 10000
LOAD CSV WITH HEADERS FROM "file:///Officers.csv" AS row MERGE (n:Node {node_id:row.node_id})        ON CREATE SET n = row, n:Officer;

USING PERIODIC COMMIT
LOAD CSV WITH HEADERS FROM "file:///all_edges.csv" AS row
WITH row WHERE row.rel_type = "intermediary_of"
MATCH (n1:Node) WHERE n1.node_id = row.node_1
MATCH (n2:Node) WHERE n2.node_id = row.node_2
CREATE (n1)-[:INTERMEDIARY_OF]->(n2);

USING PERIODIC COMMIT
LOAD CSV WITH HEADERS FROM "file:///all_edges.csv" AS row
WITH row WHERE row.rel_type = "officer_of"
MATCH (n1:Node) WHERE n1.node_id = row.node_1
MATCH (n2:Node) WHERE n2.node_id = row.node_2
CREATE (n1)-[:OFFICER_OF]->(n2);

USING PERIODIC COMMIT
LOAD CSV WITH HEADERS FROM "file:///all_edges.csv" AS row
WITH row WHERE row.rel_type = "registered_address"
MATCH (n1:Node) WHERE n1.node_id = row.node_1
MATCH (n2:Node) WHERE n2.node_id = row.node_2
CREATE (n1)-[:REGISTERED_ADDRESS]->(n2);

USING PERIODIC COMMIT
LOAD CSV WITH HEADERS FROM "file:///all_edges.csv" AS row
WITH row WHERE row.rel_type = "similar"
MATCH (n1:Node) WHERE n1.node_id = row.node_1
MATCH (n2:Node) WHERE n2.node_id = row.node_2
CREATE (n1)-[:SIMILAR]->(n2);

USING PERIODIC COMMIT
LOAD CSV WITH HEADERS FROM "file:///all_edges.csv" AS row
WITH row WHERE row.rel_type = "underlying"
MATCH (n1:Node) WHERE n1.node_id = row.node_1
MATCH (n2:Node) WHERE n2.node_id = row.node_2
CREATE (n1)-[:UNDERLYING]->(n2);

DROP CONSTRAINT ON (n:Node) ASSERT n.node_id IS UNIQUE;

MATCH (n) REMOVE n:Node;

CREATE INDEX ON :Officer(name);
CREATE INDEX ON :Entity(name);
CREATE INDEX ON :Entity(address);
CREATE INDEX ON :Intermediary(name);
CREATE INDEX ON :Address(address);

// stats
MATCH (n)-[r]->(m)
RETURN labels(n),type(r),labels(m),count(*)
ORDER BY count(*) DESC;

schema await
EOF

cat <<EOF > $DATA/cleanup.cypher
CREATE INDEX ON :Intermediary(name);
CREATE INDEX ON :Address(address);
CREATE INDEX ON :Officer(name);
CREATE INDEX ON :Entity(name);
CREATE INDEX ON :Entity(address);
CREATE INDEX ON :Entity(jurisdiction);
CREATE INDEX ON :Entity(incorporation_date);
CREATE INDEX ON :Entity(inactivation_date);
CREATE INDEX ON :Entity(struck_off_date);
CREATE INDEX ON :Entity(service_provider);
CREATE INDEX ON :Entity(original_name);
CREATE INDEX ON :Entity(status);

CREATE INDEX ON :Entity(country_codes);
CREATE INDEX ON :Address(country_codes);
CREATE INDEX ON :Intermediary(country_codes);
CREATE INDEX ON :Officer(country_codes);

// everything below is optional for fun
// mark officers as companies

unwind [" LTD","SURVIVORSHIP"," CORP","LIMITED","INC","FOUNDATION"," S.A.","PORTADOR","TRUST","BEARER","INTERNATIONAL","COMPANY","ANSTALT","INVESTMENTS"," B.V."," AG"] as designation
match (o:Officer)
WHERE NOT o:Company AND toUpper(o.name) CONTAINS designation
SET o:Company;

// set sources as label for faster filtering

MATCH (n) WHERE n.sourceID = "Panama Papers" and NOT n:PP
SET n:PP;

MATCH (n) WHERE n.sourceID = "Offshore Leaks" and NOT n:OSL
SET n:OSL;

// extract country nodes

CREATE CONSTRAINT ON (c:Country) ASSERT c.code IS UNIQUE;

CALL apoc.periodic.commit("
MATCH (n) WHERE exists(n.country_codes)
WITH n limit 50000
WITH n, split(n.country_codes,';') as codes,split(n.countries,';') as countries
FOREACH (idx in range(0,size(codes)-1) |
   MERGE (country:Country {code:codes[idx]}) ON CREATE SET country.name = countries[idx]
   MERGE (n)-[:LOCATED_IN]->(country)
)
REMOVE n.country_codes, n.countries
RETURN count(*)
",{});

// create a full-text index 

CALL apoc.index.addAllNodes('offshore',{
  Officer: ["name"],
  Intermediary:  ["name","address"],
  Address: ["address"],
  Entity: ["name", "address", "service_provider", "former_name", "company_type"]});
EOF