#!/bin/bash

docker rmi -f blackducksoftware/hub-nginx:3.6.0
docker rmi -f blackducksoftware/hub-jobrunner:3.6.0-SNAPSHOT
docker rmi -f blackducksoftware/hub-webapp:3.6.0-SNAPSHOT
docker rmi -f blackducksoftware/hub-solr:3.6.0
docker rmi -f blackducksoftware/hub-postgres:3.6.0
docker rmi -f blackducksoftware/hub-registration:3.6.0-SNAPSHOT
docker rmi -f blackducksoftware/hub-zookeeper:3.6.0
docker rmi -f blackducksoftware/hub-logstash:3.6.0
docker rmi -f blackducksoftware/hub-cfssl:3.6.0