#!/bin/bash

DOCKER_HUB_REPO=suculent/$(basename $(pwd))
docker buildx build --platform=linux/amd64 . -t $DOCKER_HUB_REPO 


