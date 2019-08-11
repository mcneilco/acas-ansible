#!/bin/bash
cd {{ acas_install_directory }}/acas_custom 
old=$(docker images --format {% raw %}'{{.ID}}' {% endraw %} mcneilco/onacaslims-certs:latest)
/usr/local/bin/docker-compose pull certs
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