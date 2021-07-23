#!/bin/bash

for ARGUMENT in "$@"
do

    KEY=$(echo $ARGUMENT | cut -f1 -d=)
    VALUE=$(echo $ARGUMENT | cut -f2 -d=)

    case "$KEY" in
            --local-ports)              local_ports=${VALUE} ;;
            --remote-destinations)    remote_destinations=${VALUE} ;;
            *)
    esac

done

echo "run-nginx:Local Ports: $local_ports"
echo "run-nginx:Remote Destinations: $remote_destinations"

./create_nginx_conf.sh --local-ports=$local_ports --remote-destinations=$remote_destinations

nginx
tail -F /var/log/nginx/server.log | ./printContents.sh
