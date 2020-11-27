#!/usr/bin/env bash

set -euo pipefail

DOCKER_BUILDKIT=1 docker build $DOCKER_BUILD_ARGS .
docker push "$IMAGE"

echo -n $(docker inspect --format='{{index .RepoDigests 0}}' "$IMAGE" | awk -F@ '{print $2}') > ../image-digest
echo -n "$IMAGE_TAG" > ../image-tags
echo -n "$IMAGE" > ../image
