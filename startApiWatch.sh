#!/bin/bash
#LOCAL_PORTS="9901,9902"
#REMOTE_HOSTS="http://10.1.1.1:9087,http://11.1.1.1:9999"
LOCAL_PORTS=`cat $1 | grep "LOCAL_PORTS" | cut -d'=' -f2`
REMOTE_HOSTS=`cat $1 | grep "REMOTE_HOSTS" | cut -d'=' -f2`


OLD_IFS=$IFS
IFS=','
exposed_ports=($LOCAL_PORTS)
exposed_hosts=($REMOTE_HOSTS)

IFS=$OLD_IFS;

IFS=
for exposed_port_index in "${!exposed_ports[@]}";
do
        DOCKER_PORTS="${DOCKER_PORTS}-p ${exposed_ports[exposed_port_index]}:${exposed_ports[exposed_port_index]} "
done

echo "Docker ports: $DOCKER_PORTS"
DOCKER_COMMAND="docker run -it --rm $DOCKER_PORTS api_watch:d0.2 --local-ports=$LOCAL_PORTS --remote-destinations=$REMOTE_HOSTS"
eval $DOCKER_COMMAND
IFS=$OLD_IFS;
