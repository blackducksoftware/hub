_VERSION=$1
if [ "$_VERSION" == "" ]; then 
	echo "You must provide the version of the Hub to install."; 
	exit 1; 
fi

docker volume create -d local --name config-volume || exit 1
docker volume create -d local --name log-volume || exit 1
docker volume create -d local --name data-volume  || exit 1
docker volume create -d local --name webserver-volume || exit 1

docker run -it -d --name cfssl -v config-volume:/etc/cfssl \
	--health-cmd='/usr/local/bin/docker-healthcheck.sh http://localhost:8888/api/v1/cfssl/scaninfo' \
	--health-interval=30s \
	--health-retries=5 \
	--health-timeout=10s \
	blackducksoftware/hub-cfssl:$_VERSION || exit 1
docker run -it -d --name logstash -v log-volume:/var/lib/logstash/data \
	--health-cmd='/usr/local/bin/docker-healthcheck.sh http://localhost:9600/' \
	--health-interval=30s \
	--health-retries=5 \
	--health-timeout=10s \
	blackducksoftware/hub-logstash:$_VERSION || exit 1
docker run -it -d --name postgres --link cfssl --link logstash -v data-volume:/var/lib/postgresql/data \
	--health-cmd='/usr/local/bin/docker-healthcheck.sh' \
	--health-interval=30s \
	--health-retries=5 \
	--health-timeout=10s \
	blackducksoftware/hub-postgres:$_VERSION || exit 1
docker run -it -d --name registration --link logstash -v config-volume:/opt/blackduck/hub/registration/config \
	--health-cmd='/usr/local/bin/docker-healthcheck.sh http://localhost:8080/registration/health-checks/liveness' \
	--health-interval=30s \
	--health-retries=5 \
	--health-timeout=10s \
	blackducksoftware/hub-registration:$_VERSION || exit 1
docker run -it -d --name zookeeper --link logstash \
	--health-cmd='zkServer.sh status' \
	--health-interval=30s \
	--health-retries=5 \
	--health-timeout=10s \
	blackducksoftware/hub-zookeeper:$_VERSION || exit 1
docker run -it -d --name solr --link logstash --link zookeeper \
	--health-cmd='/usr/local/bin/docker-healthcheck.sh http://localhost:8080/solr/project/admin/ping?wt=json' \
	--health-interval=30s \
	--health-retries=5 \
	--health-timeout=10s \
	blackducksoftware/hub-solr:$_VERSION || exit 1
docker run -it -d --name webapp \
	--link cfssl --link logstash --link postgres --link registration --link zookeeper --link solr \
	-v log-volume:/opt/blackduck/hub/logs \
	--env-file=hub-proxy.env \
	--health-cmd='/usr/local/bin/docker-healthcheck.sh http://127.0.0.1:8080/api/health-checks/liveness' \
	--health-interval=30s \
	--health-retries=5 \
	--health-timeout=10s \
	blackducksoftware/hub-webapp:$_VERSION || exit 1
docker run -it -d --name jobrunner \
	--link cfssl --link logstash --link postgres --link registration --link zookeeper --link solr \
	--env-file=hub-proxy.env \
	--health-cmd='/usr/local/bin/docker-healthcheck.sh' \
	--health-interval=30s \
	--health-retries=5 \
	--health-timeout=10s \
	blackducksoftware/hub-jobrunner:$_VERSION || exit 1
docker run -it -d --name webserver --link webapp --link cfssl -p 443:443 \
	-v webserver-volume:/opt/blackduck/hub/webserver/security \
	--health-cmd='/usr/local/bin/docker-healthcheck.sh https://localhost:443/health-checks/liveness /opt/blackduck/hub/webserver/security/root.crt' \
	--health-interval=30s --health-retries=5 --health-timeout=10s blackducksoftware/hub-nginx:$_VERSION || exit 1