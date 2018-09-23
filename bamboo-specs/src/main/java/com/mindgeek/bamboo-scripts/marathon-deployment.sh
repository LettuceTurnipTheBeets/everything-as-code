#!/bin/bash

# Define Docker image name
export PRIVATE_REGISTRY_IMAGE=${bamboo_PRIVATE_REGISTRY_HOSTNAME}/${bamboo_PRIVATE_REGISTRY_PROJECT}/${bamboo_DOCKER_IMAGE_NAME}:${bamboo_deploy_release}

# Build from Dockerfile
if [ -z "$bamboo_DOCKER_FILE" ];then
  docker build --pull --rm -t ${PRIVATE_REGISTRY_IMAGE} .
else
  docker build --pull --rm -t ${PRIVATE_REGISTRY_IMAGE} -f ${bamboo_DOCKER_FILE} .
fi
EXIT_CODE=$?
if [ ! $EXIT_CODE -eq 0 ]; then
    echo "Docker Build failed"
    exit $EXIT_CODE
fi

#Push to Docker registry
docker save -o image.tar ${PRIVATE_REGISTRY_IMAGE}
docker run --privileged --userns=host -d --name image-push docker:stable-dind
docker run -w /data/working -v $(pwd):/data/working --rm --link image-push:docker docker:stable docker load --input image.tar
docker run -w /data/working -v $(pwd):/data/working --rm --env bamboo_PRIVATE_REGISTRY_HOSTNAME --env PRIVATE_REGISTRY_IMAGE --env bamboo_PRIVATE_REGISTRY_USERNAME --env bamboo_PRIVATE_REGISTRY_PASSWORD --link image-push:docker docker:stable sh -c 'docker login -u $bamboo_PRIVATE_REGISTRY_USERNAME -p $bamboo_PRIVATE_REGISTRY_PASSWORD $bamboo_PRIVATE_REGISTRY_HOSTNAME && docker push $PRIVATE_REGISTRY_IMAGE'
EXIT_CODE=$?

# Clean-up, we want to clean up the docker artifacts before exiting or if we deploy to Marathon
docker rm -f image-push
rm image.tar
docker rmi -f ${PRIVATE_REGISTRY_IMAGE}
if [ ! $EXIT_CODE -eq 0 ]; then
    echo "Push to Docker Registry failed"
    exit $EXIT_CODE
fi

## Check if a Calico network is being specified
HOST_PORT=", \"hostPort\": 0"
if [ ! -z "$bamboo_CALICO_NETWORK" ];
then
  HOST_PORT=""
  export MESOS_DOCKER_NETWORK="[ {\"name\": \"${bamboo_CALICO_NETWORK}\",\"mode\": \"container\"} ]";
elif [ ! -z "$bamboo_DOCKER_NETWORK" ];
then
  export MESOS_DOCKER_NETWORK="${bamboo_DOCKER_NETWORK}";
else
  export MESOS_DOCKER_NETWORK="[ {\"mode\": \"container/bridge\"} ]";
fi

## Check if a ports have been specified
if [ ! -z "${bamboo_TCP_PORTS}" ];
then
  for P in ${bamboo_TCP_PORTS};
  do
    PORT_STRING="$PORT_STRING { \"containerPort\": ${P}, \"protocol\": \"tcp\" ${HOST_PORT} },";
  done;
  export CONTAINER_PORTS="[ ${PORT_STRING%,*} ]";
elif [ ! -z "${bamboo_CONTAINER_PORTS}" ];
then
  export CONTAINER_PORTS="${bamboo_CONTAINER_PORTS}";
else
  export CONTAINER_PORTS="[ {\"containerPort\": 80,\"protocol\": \"tcp\" ${HOST_PORT} } ]";
fi

if [ -z "$bamboo_MARATHON_URI" ];
then
  HEALTHCHECK=""
else
  HEALTHCHECK=$(cat <<-HEALTH
"healthChecks": [
    {
        "gracePeriodSeconds": 300,
        "ignoreHttp1xx": false,
        "intervalSeconds": 60,
        "maxConsecutiveFailures": 3,
        "path": "$bamboo_MARATHON_URI",
        "portIndex": 0,
        "protocol": "HTTP",
        "timeoutSeconds": 20,
        "delaySeconds": 15
    }
],
HEALTH
)
fi

#Deploy to Marathon
# Check to see if the service exists in Marathon
CURL_RESPONSE=$(curl --write-out %{http_code} --silent --output /dev/null ${bamboo_MARATHON_URL}/${bamboo_MARATHON_SERVICE}/versions)
# If it does then take the current configuration from Marathon and put in the new Docker image name
if [ $CURL_RESPONSE -eq 200 ];then
  echo "Updating Current Marathon Service ${bamboo_MARATHON_SERVICE}"
  UPDATED_JSON=$(curl -sL ${bamboo_MARATHON_URL}/${bamboo_MARATHON_SERVICE}/versions | docker run --rm -i asvinours/php-nodejs-tools bash -c 'cat - | jq -r ".versions[]" | sort -r | head -n1' | xargs -I {} curl -s "${bamboo_MARATHON_URL}/${bamboo_MARATHON_SERVICE}/versions/{}" | docker run --rm -i asvinours/php-nodejs-tools bash -c "cat - | jq '(.|=with_entries(select(.key|test(\"version|fetch|uris\")|not)) | (.container.docker.image |= \"${PRIVATE_REGISTRY_IMAGE}\") | (.container.docker.forcePullImage |= true))'")
  echo $UPDATED_JSON | curl \
      -H "Content-Type: application/json; charset=utf-8" \
      -H "X-TOKEN-AUTH: ${bamboo_MARATHON_HEADER_PASSWORD}" \
      -X PUT \
      -d@- \
      ${bamboo_MARATHON_URL}/${bamboo_MARATHON_SERVICE}
  EXIT_CODE=$?
  if [ ! $EXIT_CODE -eq 0 ]; then
      echo "Request to Marathon has failed."
      exit $EXIT_CODE
  fi
else
# If it does not exist, create a new JSON template and push to Marathon
  echo "Creating new Marathon Service ${bamboo_MARATHON_SERVICE} JSON template"
  MARATHON_JSON="{
      \"id\": \"/$bamboo_MARATHON_SERVICE\",
      \"cpus\": $bamboo_MARATHON_CPUS,
      \"mem\": $bamboo_MARATHON_MEM,
      \"disk\": 0,
      \"instances\": $bamboo_MARATHON_INSTANCES,
      \"container\": {
          \"type\": \"DOCKER\",
          \"volumes\": [],
          \"docker\": {
              \"image\": \"$PRIVATE_REGISTRY_IMAGE\",
              \"portMappings\": $CONTAINER_PORTS,
              \"forcePullImage\": false,
              \"parameters\": [],
              \"privileged\": false
          }
      },
      \"env\": {
          \"ENV_FILE\": \"$bamboo_ENV_FILE\"
      },
      $HEALTHCHECK
      \"labels\": {
          \"HAPROXY_0_VHOST\": \"$bamboo_MARATHON_PROXY_HOST\",
          \"HAPROXY_GROUP\": \"$bamboo_MARATHON_PROXY_GROUP\"
      },
      \"networks\": $MESOS_DOCKER_NETWORK
  }"
  echo "JSON for marathon has been generated...Sending to Marathon"
  echo $MARATHON_JSON
  echo "___________"
  echo "___________"
  echo $MARATHON_JSON | curl \
      -H "Content-Type: application/json" \
      -H "X-TOKEN-AUTH: ${bamboo_MARATHON_HEADER_PASSWORD}" \
      -X POST \
      -d@- \
      ${bamboo_MARATHON_URL}
  EXIT_CODE=$?
  if [ ! $EXIT_CODE -eq 0 ]; then
      echo "Request to Marathon has failed."
      exit $EXIT_CODE
  fi
fi
echo "The request has been sent to Marathon, please verify that the service has started properly."
exit 0
