#!/bin/sh
set -e

echo "=> Using weave version: $VERSION"

echo "=> Using docker binary:"
docker version

if [ "${WEAVE_LAUNCH}" = "**None**" ]; then
    # For local dev and testing
    echo "WEAVE_LAUNCH is **None**. Not running 'weave launch'"
else
    ROUTER_PRESENT=`docker ps -a | grep -c "weaveworks/weave:" || true`
    ROUTER_PRESENT_SAME_VERSION=`docker ps -a | grep -c "weaveworks/weave:${VERSION}" || true`
    if [ "${ROUTER_PRESENT_SAME_VERSION}" = "0" ]; then
        echo "=> Weave router:${VERSION} container not found"
        WEAVE_IMAGES=`docker images | grep -c "weaveworks/weave:${VERSION}" || true`
        if [ "${WEAVE_IMAGES}" = "0" ]; then
            echo "=> Pulling weave images"
            /weave --local setup
        fi

        echo "=> Stopping weave on the node"
        /weave --local stop || true
        docker rm -f weave || true
        docker rm -f weaveplugin || true
        docker rm -f weaveproxy || true
    else
        echo "=> Weave router:${VERSION} container found"
    fi

    PRIVATE_SUBNETS=$(ip addr show | grep "eth[0-9]" | grep -oE "(10.[0-9]{1,3}.[0-9]{1,3}.[0-9]{1,3}/[0-9]+|172.(16|17|18|19|2[0-9]|30|31).[0-9]{1,3}.[0-9]{1,3}/[0-9]+|192.168.[0-9]{1,3}.[
0-9]{1,3}/[0-9]+)" | tr '\n' ',' | head -c -1)
    if [ ! -z "${DOCKERCLOUD_PRIVATE_CIDR}" ]; then
        # TODO: check which private subnets detected can be trusted
        # TRUSTED_SUBNETS="${PRIVATE_SUBNETS},${DOCKERCLOUD_PRIVATE_CIDR}"
        TRUSTED_SUBNETS="${DOCKERCLOUD_PRIVATE_CIDR}"
    fi
    echo "=> Marking the following private subnets as trusted (unencrypted): ${TRUSTED_SUBNETS:-none}"

    if [ "${ROUTER_PRESENT}" != "0" ] && [ -z "${WEAVE_LAUNCH}" ]; then
        WEAVE_EXTRA_ARGS="--resume"
    fi

    if [ ! -z "${WEAVE_PASSWORD}" ]; then
        echo "=> Running: weave launch ${WEAVE_EXTRA_ARGS} -password XXXXXX ${WEAVE_LAUNCH}"
        echo "=> Peer count: ${DOCKERCLOUD_PEER_COUNT}"
        WEAVE_EXTRA_ARGS="${WEAVE_EXTRA_ARGS} --password=${WEAVE_PASSWORD}"
    else
        echo "!! WARNING: No \$WEAVE_PASSWORD set!"
        echo "=> Running: weave launch ${WEAVE_EXTRA_ARGS} ${WEAVE_LAUNCH}"
        echo "=> Peer count: ${DOCKERCLOUD_PEER_COUNT}"
    fi
    /weave --local launch-router --conn-limit=0 --ipalloc-range=10.128.0.0/10 --trusted-subnets=${TRUSTED_SUBNETS} --no-dns --no-discovery --ipalloc-init consensus=${DOCKERCLOUD_PEER_COUNT} ${WEAVE_EXTRA_ARGS} ${WEAVE_LAUNCH} || true
    sleep 2
fi

echo "=> Launching weave proxy container"
/weave --local launch-proxy || true
sleep 2

echo "=> Current weave router status"
/weave --local status

echo "=> Running weave expose"
/weave --local expose 10.7.255.254/16

echo "=> Launching weave plugin container"
/weave --local launch-plugin
sleep 2

echo "=> Checking if the weave router, plugin and proxy are running"
docker ps | grep -q "weaveworks/weave:${VERSION}"
docker ps | grep -q "weaveworks/plugin:${VERSION}"
docker ps | grep -q "weaveworks/weaveexec:${VERSION}"

NETWORK_CREATED=`docker network ls | grep -c ${WEAVEMESH_NETWORK} || true`
if [ "${NETWORK_CREATED}" = "0" ]; then
    echo "=> Creating weavemesh network: ${WEAVEMESH_NETWORK}"
    docker network create --driver weavemesh --subnet 10.7.0.0/16 ${WEAVEMESH_NETWORK}
else
    echo "=> Weavemesh network(${WEAVEMESH_NETWORK}) exists"
fi

echo "=> Starting containers with autorestart activated that failed to automatically start"
/restart_failed_containers.sh

if [ -n "${NO_PEER_DISCOVERY}" ]; then
    docker logs -f weave
else
    docker logs -f weave &
    echo "=> Starting peer discovery daemon"
    exec /dockercloud-network-daemon $@
fi
