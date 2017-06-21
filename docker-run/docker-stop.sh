
for container in 'webserver' 'jobrunner' 'webapp' 'solr' 'zookeeper' 'registration' 'postgres' 'logstash' 'cfssl'; do
  docker stop $container | awk '{print "Stopping "$1"..."}'
done