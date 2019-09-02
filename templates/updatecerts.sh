#!/bin/bash
cd {{ acas_install_directory }}/acas_custom 
old=$(docker images --format {% raw %}'{{.ID}}' {% endraw %} mcneilco/onacaslims-certs:latest)
runuser -l  acas -c 'cd {{ acas_install_directory }}/acas_custom ; /usr/local/bin/docker-compose pull certs'
new=$(docker images --format {% raw %}'{{.ID}}' {% endraw %} mcneilco/onacaslims-certs:latest)
if [ "$old" == "$new" ]; then
    echo "Certs already up to date"
else
    echo "Updating certs"
    /usr/local/bin/docker-compose kill nginx
    /usr/local/bin/docker-compose rm -vf nginx certs
    /usr/local/bin/docker-compose up -d nginx certs
    echo "Certs now up to date"

fi

echo "Updating certs for postgres"
cd {{ acas_install_directory }}/acas_custom ;
if [ -f .env ]; then
    . .env;
fi;
folder=$(basename $(pwd));
project=${COMPOSE_PROJECT_NAME:-$folder};
parsed=$(echo "${project//[^A-Za-z0-9_ ]/}" | tr [:upper:] [:lower:]);
container=$parsed'_certs_1';
docker cp $container:/etc/letsencrypt/live/onacaslims.com/fullchain.pem {{ acas_install_directory }}/dbstore/server.crt
docker cp $container:/etc/letsencrypt/live/onacaslims.com/privkey.pem {{ acas_install_directory }}/dbstore/server.key
chown postgres:postgres {{ acas_install_directory }}/dbstore/server.key {{ acas_install_directory }}/dbstore/server.crt
chmod 600 {{ acas_install_directory }}/dbstore/server.key {{ acas_install_directory }}/dbstore/server.crt
