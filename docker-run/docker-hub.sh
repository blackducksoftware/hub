_VERSION=
_MIGRATE=
_UP=
_DOWN=
_STOP=
_VOLUMES=
_EXTERNALDB=

usage () {
  echo 'This should be started with the following options:
        -r | --release : The Hub version that should be deployed.  This field is mandatory. 
        -m | --migrate : Migrates Hub data from the PostgreSQL dump file. Typically this is run only once and very first if data needs to be migrated. It does not work with the --down, --stop, or --externaldb options. 
        -u | --up : Starts the containers.  Creates volumes if they do not already exist. 
        -d | --down : Stops and removes the containers.  If --volumes is provided, it will remove volumes as well. 
        -s | --stop : Stops the containers, but leaves them on the system.  Does not affect volumes. 
        -v | --volumes : If provided with --down, this script will remove the volumes and all data stored within them. 
		-e | --externaldb : Use an external PostgreSQL instance rather than the default docker container; cannot be used with --migrate.
       '
}

while [ "$1" != "" ]; do
  case $1 in 
      -r | --release )       shift
                             _VERSION=$1
                             export HUB_VERSION="$1"
                             ;;
      -m | --migrate )       shift
                             _MIGRATE=1
                             dump_file=$1
                             ;;
      -u | --up )            _UP=1
                             ;;
      -d | --down )          _DOWN=1
                             ;;
      -s | --stop )          
                             _STOP=1
                             ;;
      -v | --volumes )       
                             _VOLUMES=1
                             ;;
      -e | --externaldb )
                             _EXTERNALDB=1
							 ;;

      * )                    echo "$1"
                             usage
                             exit 1
  esac
  shift
done

if [ "$_UP" != "" ] && [ "$_VERSION" == "" ]; then usage; exit 1; fi
if [ "$_MIGRATE" != "" ] && ([ "$_VERSION" == "" ] || [ "$dump_file" == "" ]); then usage; exit 1; fi
if [ "$_MIGRATE" != "" ] && ([ "$_STOP" != "" ] || [ "$_DOWN" != "" ]); then usage; exit 1; fi
if [ "$_UP" != "" ] && [ "$_STOP" != "" ]; then echo 'You can only provide --up or --stop, not both.'; usage; exit 1; fi
if [ "$_UP" != "" ] && [ "$_DOWN" != "" ]; then echo 'You can only provide --up or --down, not both.'; usage; exit 1; fi
if [ "$_STOP" != "" ] && [ "$_DOWN" != "" ]; then echo 'You can only provide --down or --stop, not both.'; usage; exit 1; fi
if [ "$_VOLUMES" != "" ]; then if [ "$_UP" != "" ] || [ "$_STOP" != "" ] || [ "$_MIGRATE" != "" ]; then echo 'You cannot provide the --volumes flag for --up, --stop or --migrate.'; usage; exit 1; fi; fi
if [ "$_MIGRATE" != "" ] && [ "$_EXTERNALDB" != "" ]; then echo 'You can only provide --migrate or --externaldb, not both.'; usage; exit 1; fi

if [ "$_EXTERNALDB" == "" ] ; then
	bdsHubContainers=("webserver" "jobrunner" "webapp" "solr" "zookeeper" "registration" "postgres" "logstash" "cfssl" "documentation")
	bdsHubVolumes=("config-volume" "cert-volume" "log-volume" "postgres96-data-volume" "webserver-volume" "webapp-volume" "solr6-volume")
	pg_linkage=("--link postgres")
else
	bdsHubContainers=("webserver" "jobrunner" "webapp" "solr" "zookeeper" "registration" "logstash" "cfssl" "documentation")
	bdsHubVolumes=("config-volume" "cert-volume" "log-volume" "webserver-volume" "webapp-volume" "solr6-volume")
	pg_linkage=("--env-file hub-postgres.env" "-v ${PWD}:/run/secrets:ro")
fi

function createVolume() {
  for volume in $*; do
    if [ "$(docker volume ls | grep $volume)" == "" ]; then
       (docker volume create -d local --name $volume | sed -e 's/^/Creating volume / ; s/$/.../')|| exit 1 
    fi
  done
}

function startCfssl() {
  if [ "$(docker ps -a | grep cfssl)" == "" ]; then
    docker run -it -d --name cfssl -v cert-volume:/etc/cfssl \
    --health-cmd='/usr/local/bin/docker-healthcheck.sh http://localhost:8888/api/v1/cfssl/scaninfo' \
    --health-interval=30s \
    --health-retries=5 \
    --health-timeout=10s \
    --user=cfssl:root \
    --memory=512m \
    --security-opt=no-new-privileges \
    blackducksoftware/hub-cfssl:$_VERSION | sed -e 's/^/Starting cfssl / ; s/$/.../' || exit 1
  elif [ "$(docker ps | grep cfssl)" == "" ]; then
    docker start cfssl | sed -e 's/^/Starting cfssl / ; s/$/.../' || exit 1
  fi
}

function startLogstash() {
  if [ "$(docker ps -a | grep logstash)" == "" ]; then
    docker run -it -d --name logstash -v log-volume:/var/lib/logstash/data \
    --health-cmd='/usr/local/bin/docker-healthcheck.sh http://localhost:9600/' \
    --health-interval=30s \
    --health-retries=5 \
    --health-timeout=10s \
    --user=logstash:root \
    --memory=640m \
    --security-opt=no-new-privileges \
    blackducksoftware/hub-logstash:$_VERSION | sed -e 's/^/Starting logstash / ; s/$/.../' || exit 1
  elif [ "$(docker ps | grep logstash)" == "" ]; then
    docker start logstash | sed -e 's/^/Starting logstash / ; s/$/.../' || exit 1
  fi
}

function startPostgres() {
  [ "$_EXTERNALDB" != "" ] && return 0
  if [ "$(docker ps -a | grep postgres)" == "" ]; then
    docker run -it -d --name postgres --link cfssl --link logstash \
    -v postgres96-data-volume:/var/lib/postgresql/data \
    --health-cmd='/usr/local/bin/docker-healthcheck.sh' \
    --health-interval=30s \
    --health-retries=5 \
    --health-timeout=10s \
    --user=postgres:root \
    --memory=3072m \
    --security-opt=no-new-privileges \
    blackducksoftware/hub-postgres:$_VERSION | sed -e 's/^/Starting postgres / ; s/$/.../' || exit 1
  elif [ "$(docker ps | grep postgres)" == "" ]; then
    docker start postgres | sed -e 's/^/Starting postgres / ; s/$/.../' || exit 1
  fi
}

function startRegistration() {
  if [ "$(docker ps -a | grep registration)" == "" ]; then
    docker run -it -d --name registration --link logstash \
    -v config-volume:/opt/blackduck/hub/registration/config \
    --env-file=hub-proxy.env \
    --health-cmd='/usr/local/bin/docker-healthcheck.sh http://localhost:8080/registration/health-checks/liveness' \
    --health-interval=30s \
    --health-retries=5 \
    --health-timeout=10s \
    --user=8080:root \
    --memory=640m \
    --security-opt=no-new-privileges \
    blackducksoftware/hub-registration:$_VERSION | sed -e 's/^/Starting registration / ; s/$/.../' || exit 1
  elif [ "$(docker ps | grep registration)" == "" ]; then
    docker start registration | sed -e 's/^/Starting registration / ; s/$/.../' || exit 1
  fi
}

function startZookeeper() {
  if [ "$(docker ps -a | grep zookeeper)" == "" ]; then
    docker run -it -d --name zookeeper --link logstash \
    --health-cmd='zkServer.sh status' \
    --health-interval=30s \
    --health-retries=5 \
    --health-timeout=10s \
    --user=zookeeper:root \
    --memory=384m \
    --security-opt=no-new-privileges \
    blackducksoftware/hub-zookeeper:$_VERSION | sed -e 's/^/Starting zookeeper / ; s/$/.../' || exit 1
  elif [ "$(docker ps | grep zookeeper)" == "" ]; then
    docker start zookeeper | sed -e 's/^/Starting zookeeper / ; s/$/.../' || exit 1
  fi
}

function startSolr() {
  if [ "$(docker ps -a | grep solr)" == "" ]; then
    docker run -it -d --name solr --link logstash --link zookeeper \
    -v solr6-volume:/opt/blackduck/hub/solr/cores.data \
    --health-cmd='/usr/local/bin/docker-healthcheck.sh http://localhost:8080/solr/project/admin/ping?wt=json' \
    --health-interval=30s \
    --health-retries=5 \
    --health-timeout=10s \
    --user=solr:root \
    --memory=640m \
    --security-opt=no-new-privileges \
    blackducksoftware/hub-solr:$_VERSION | sed -e 's/^/Starting solr / ; s/$/.../' || exit 1
  elif [ "$(docker ps | grep solr)" == "" ]; then
    docker start solr | sed -e 's/^/Starting solr / ; s/$/.../' || exit 1
  fi
}

function startWebapp() {
  if [ "$(docker ps -a | grep webapp)" == "" ]; then
    docker run -it -d --name webapp --link cfssl --link logstash ${pg_linkage[@]} --link registration --link zookeeper --link solr \
    -v webapp-volume:/opt/blackduck/hub/hub-webapp/security \
    -v log-volume:/opt/blackduck/hub/logs \
    --env-file hub-proxy.env \
    --health-cmd='/usr/local/bin/docker-healthcheck.sh http://127.0.0.1:8080/api/health-checks/liveness' \
    --health-interval=30s \
    --health-retries=5 \
    --health-timeout=10s \
    --user=8080:root \
    --memory=4608m \
    --security-opt=no-new-privileges \
    blackducksoftware/hub-webapp:$_VERSION | sed -e 's/^/Starting webapp / ; s/$/.../' || exit 1
  elif [ "$(docker ps | grep webapp)" == "" ]; then
    docker start webapp | sed -e 's/^/Starting webapp / ; s/$/.../' || exit 1
  fi
}

function startJobrunner() {
  if [ "$(docker ps -a | grep jobrunner)" == "" ]; then
    docker run -it -d --name jobrunner --link cfssl --link logstash ${pg_linkage[@]} --link registration --link zookeeper --link solr \
    --env-file hub-proxy.env \
    --health-cmd='/usr/local/bin/docker-healthcheck.sh' \
    --user=jobrunner:root \
    --memory=4608m \
    --security-opt=no-new-privileges \
    blackducksoftware/hub-jobrunner:$_VERSION | sed -e 's/^/Starting jobrunner / ; s/$/.../' || exit 1
  elif [ "$(docker ps | grep jobrunner)" == "" ]; then
    docker start jobrunner | sed -e 's/^/Starting jobrunner / ; s/$/.../' || exit 1
  fi
}

function startDocumentation() {
  if [ "$(docker ps -a | grep documentation)" == "" ]; then
    docker run -it -d --name documentation --link logstash \
    --user=8080:root \
    --health-cmd='/usr/local/bin/docker-healthcheck.sh http://127.0.0.1:8080/hubdoc/health-checks/liveness' \
    --health-interval=30s \
    --health-retries=5 \
    --health-timeout=10s \
    blackducksoftware/hub-documentation:$_VERSION | sed -e 's/^/Starting documentation / ; s/$/.../' || exit 1
  elif [ "$(docker ps | grep documentation)" == "" ]; then
    docker start documentation | sed -e 's/^/Starting documentation / ; s/$/.../' || exit 1
  fi
}

function startWebserver() {
  if [ "$(docker ps -a | grep webserver)" == "" ]; then
    docker run -it -d --name webserver --link webapp --link cfssl --link documentation -p 443:8443 \
    -v webserver-volume:/opt/blackduck/hub/webserver/security \
    --env-file=hub-webserver.env \
    --health-cmd='/usr/local/bin/docker-healthcheck.sh https://localhost:443/health-checks/liveness /opt/blackduck/hub/webserver/security/root.crt' \
    --health-interval=30s \
    --health-retries=5 \
    --health-timeout=10s \
    --user=nginx:root \
    --memory=640m \
    --security-opt=no-new-privileges \
    blackducksoftware/hub-nginx:$_VERSION | sed -e 's/^/Starting webserver / ; s/$/.../' || exit 1
  elif [ "$(docker ps | grep webserver)" == "" ]; then
    docker start webserver | sed -e 's/^/Starting webserver / ; s/$/.../' || exit 1
  fi    
}

# Migrate postgres data. If migration script runs successfully and --up option is provided, continue to start remaining containers.
if [ "$_MIGRATE" != "" ]; then
  createVolume "cert-volume" "log-volume" "postgres96-data-volume"
  startCfssl
  startLogstash
  startPostgres
  sleep 10
  ./bin/hub_db_migrate.sh $dump_file
  migrationResult=$?
  if [ $migrationResult != 0 ]; then
    echo "Error running PostgreSQL migration from the file: $dump_file"
    exit 1
  else 
    echo "Migration successful."
    if [ "$_UP" == "" ]; then
      exit 1;
    fi
  fi
fi

# Start the containers.  Check if volumes exist, if not, create them.  If the containers already exist, start them.
if [ "$_UP" != "" ]; then
    createVolume ${bdsHubVolumes[@]}
    startCfssl
    startLogstash
    startPostgres
    startRegistration
    startZookeeper
    startSolr
    startWebapp
    startJobrunner
    startDocumentation
    startWebserver
fi

# Stop the containers.
if [ "$_STOP" != "" ]; then
  for container in ${bdsHubContainers[@]}; do
    docker stop $container | sed -e 's/^/Stopping / ; s/$/.../'
  done
fi

# Stop and remove the containers.  If --volumes was provided, remove the volumes as well.
if [ "$_DOWN" != "" ]; then
  for container in ${bdsHubContainers[@]}; do
      docker stop $container | sed -e 's/^/Stopping / ; s/$/.../'
      docker rm $container | sed -e 's/^/Removing / ; s/$/.../'
  done
  if [ "$_VOLUMES" != "" ]; then
      for volume in ${bdsHubVolumes[@]}; do
          docker volume rm $volume | sed -e 's/^/Removing volume / ; s/$/.../'
      done
  fi
fi
