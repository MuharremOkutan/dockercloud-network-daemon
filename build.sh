export VERSION=0.10.0


echo "=> Downloading weave version $VERSION"
if [ ! -f "weave" ]; then
  curl -sSLo weave https://github.com/weaveworks/weave/releases/download/v$VERSION/weave
fi
chmod +x weave

echo "=> Building the binary"
docker run \
  -v $(pwd):/src \
  -v /var/run/docker.sock:/var/run/docker.sock \
  centurylink/golang-builder \
  weave-daemon