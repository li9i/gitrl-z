#!/bin/sh
docker run --rm --user "$(id -u):$(id -g)" -e HOME=/tmp -v "$PWD:/src" -w /src gitrlz-build ./docker/build-deb.sh;
