#!/bin/bash

DOCKER_HUB_REPO=suculent/$(basename $(pwd))
docker build . -t $DOCKER_HUB_REPO


