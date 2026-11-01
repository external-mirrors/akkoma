echo "Building $1 using image tag $2"
docker buildx build --platform amd64,arm64 -t docker.io/akkoma/ci-base:$1 --build-arg=version=$1 --push --build-arg=TAG=$2 . 
#docker push docker.io/akkoma/ci-base:$1
