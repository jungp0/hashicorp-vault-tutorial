#!/bin/bash
if [[ $# -le 1 ]]
then
    echo -e "The docker image name:"
    read image_name
    docker build -t $image_name .
    echo -e "---------------------------\nThe docker container name:"
    read container_name
    if [[ $# -eq 0 ]]
    then
        docker run --name $container_name -dp 80:8200 $image_name
    else
        docker run --name $container_name -dp $1:8200 $image_name
    fi
    docker exec -it $container_name ./bin/bash
else
    docker build -t $1 .
    if [[ $# -eq 2 ]]
    then
        docker run --name $2 -dp 80:8200 $1
    else
        docker run --name $2 -dp $3:8200 $1
    fi
    docker exec -it $2 ./bin/bash
fi