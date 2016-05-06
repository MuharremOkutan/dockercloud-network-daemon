#!/bin/bash
set -e

EXTERNAL_DOCKER=no
MOUNTED_DOCKER_FOLDER=no
if [ -S /var/run/docker.sock ]; then
	echo "=> Detected unix socket at /var/run/docker.sock"
	docker version > /dev/null 2>&1 || (echo "   Failed to connect to docker daemon at /var/run/docker.sock" && exit 1)
	EXTERNAL_DOCKER=yes
else
	if [ "$(ls -A /var/lib/docker)" ]; then
		echo "=> Detected pre-existing /var/lib/docker folder"
		MOUNTED_DOCKER_FOLDER=yes
	fi
	echo "=> Starting docker"
	wrapdocker > /dev/null 2>&1 &
	sleep 2
	echo "=> Checking docker daemon"
	docker version > /dev/null 2>&1 || (echo "   Failed to start docker (did you use --privileged when running this container?)" && exit 1)
fi

IP1=10.7.0.1/16
IP2=10.7.0.2/16
IP3=10.7.0.3/16

DOCKER_BINARY=${DOCKER_BINARY:-"/usr/bin/docker"}

echo "=> Launching hello world containers"
docker run -d -e DOCKERCLOUD_IP_ADDRESS=$IP1 dockercloud/hello-world
docker run -d -e DOCKERCLOUD_IP_ADDRESS=$IP2 dockercloud/hello-world

echo "=> Building the image"
docker build -t this .

echo "=> Launching network-daemon"
docker run -d \
      --net host \
      --privileged \
      -v /var/run/docker.sock:/var/run/docker.sock \
      -v ${DOCKER_BINARY}:/usr/local/bin/docker:ro \
      -v /proc:/hostproc \
      -e PROCFS=/hostproc \
      -e WEAVE_LAUNCH="" \
      -e WEAVE_PASSWORD="pass" \
      --name network-daemon \
      this

echo "=> Weave-daemon runtime"
sleep 60

echo "=> Pinging hello world containers"
docker run -d --name=pingC -e DOCKERCLOUD_IP_ADDRESS=$IP3 dockercloud/hello-world
docker exec -t pingC ping 10.7.0.2 -c 15
docker exec -t pingC ping 10.7.0.1 -c 15
