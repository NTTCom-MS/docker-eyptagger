#!/bin/bash

docker run -d -v /root/.ssh:/root/.ssh -t eyp/eyptagger

docker ps --all | grep eyptagger | grep Exited | awk '{ print $1 }' xargs docker rm

