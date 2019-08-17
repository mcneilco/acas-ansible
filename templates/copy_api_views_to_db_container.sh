#!/bin/bash
if [ -f .env ]; then
		. .env;
fi;
folder=$(basename $(pwd));
project=${COMPOSE_PROJECT_NAME:-$folder};
parsed=$(echo "${project//[^A-Za-z0-9 ]/}" | tr [:upper:] [:lower:]);
container=$parsed'_db_1';
while [ "`docker inspect -f {% raw %}'{{.State.Running}}' {% endraw %} $container`" != "true" ]; do 
   echo "waiting on the db to start";
   sleep 2;
done;
docker cp api_views.sql $container:/tmp/api_views.sql
/usr/local/bin/docker-compose exec db psql -U postgres acas -f "/tmp/api_views.sql"
