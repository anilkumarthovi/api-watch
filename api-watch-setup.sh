# Version 1.2
#export EXPOSED_PORTS="9901,9902,9903,9904"
#export EXPOSED_HOSTS="http://local9901:1234,http://local9902:2345,http://local9903:3456,http://local9904:4567"

# Create nginx.conf file
#./create_nginx_conf.sh --local-ports=$EXPOSED_PORTS --remote-destinations=$EXPOSED_HOSTS

cat > create_nginx_conf.sh<<CREATE_NGINX_CONF
#!/bin/bash

for ARGUMENT in "\$@"
do

    KEY=\$(echo \$ARGUMENT | cut -f1 -d=)
    VALUE=\$(echo \$ARGUMENT | cut -f2 -d=)

    case "\$KEY" in
            --local-ports)              local_ports=\${VALUE} ;;
            --remote-destinations)    remote_destinations=\${VALUE} ;;
            *)
    esac

done

echo "Local Ports: \$local_ports"
echo "Remote Destinations: \$remote_destinations"

echo "START - creating /etc/nginx/nginx.conf"
cat > /etc/nginx/nginx.conf<<EOF
# /etc/nginx/nginx.conf

user nginx;

# Set number of worker processes automatically based on number of CPU cores.
worker_processes auto;

# Enables the use of JIT for regular expressions to speed-up their processing.
pcre_jit on;

# Configures default error logger.
error_log /var/log/nginx/error.log warn;

# Includes files with directives to load dynamic modules.
include /etc/nginx/modules/*.conf;


events {
	# The maximum number of simultaneous connections that can be opened by
	# a worker process.
	worker_connections 1024;
}

http {
        log_format bodylog escape=json '{'
                                          '"remoteAddress": "\\\$remote_addr",'
                                          '"host": "\\\$host",'
					  '"proxyHost": "\\\$proxy_host",'
                                          '"upstreamAddress": "\\\$upstream_addr",'
					  '"requestUri": "\\\$request_uri",'
					  '"scheme": "\\\$scheme",'
                                          '"remoteUser": "\\\$remote_user",'
                                          '"timeLocal": "\\\$time_local",'
					  '"requestMethod": "\\\$request_method",'
					  '"requestUri": "\\\$uri",'
					  '"requestArgs": "\\\$args",'
					  '"requestHeaders": "\\\$request_headers",'
                                          '"request": "\\\$request",'
                                          '"status": "\\\$status",'
                                          '"bodyBytesSent": "\\\$body_bytes_sent",'
                                          '"httpReferer": "\\\$http_referer",'
                                          '"httpUserAgent": "\\\$http_user_agent",'
                                          '"requestTime": "\\\$request_time",'
                                          '"requestBody": "\\\$request_body",'
                                          '"responseBody": "\\\$resp_body"'
                                        '}';

        lua_need_request_body on;
EOF


OLD_IFS=\$IFS
IFS=','
#exposed_ports=(\$EXPOSED_PORTS)
#exposed_hosts=(\$EXPOSED_HOSTS)
exposed_ports=(\$local_ports)
exposed_hosts=(\$remote_destinations)

IFS=\$OLD_IFS;


for exposed_port_index in "\${!exposed_ports[@]}"
do
	echo "
	server {
		set \\\$resp_body \"\";

		set_by_lua \\\$request_headers '
                        local h = ngx.req.get_headers()
                        local request_headers_all = \"\"
                        for k, v in pairs(h) do
                                request_headers_all = request_headers_all .. \"\"..k..\": \"..v..\";\"
                        end
                        return request_headers_all
                ';

		body_filter_by_lua_block {
                	local resp_body = ngx.arg[1]
                	ngx.ctx.buffered = (ngx.ctx.buffered or \"\") .. resp_body

                	if ngx.arg[2] then
                        	ngx.var.resp_body = ngx.ctx.buffered
                	end
        	}

        	listen \${exposed_ports[exposed_port_index]};

        	location / {
                	echo_read_request_body;
                	proxy_set_header Accept-Encoding '';
                	proxy_pass \${exposed_hosts[exposed_port_index]};            # msp.service.hostname
                	access_log /var/log/nginx/server.log bodylog;
        	}
	}
	" >> /etc/nginx/nginx.conf;
done;

cat >> /etc/nginx/nginx.conf<<EOF

	# Includes mapping of file name extensions to MIME types of responses
	# and defines the default type.
	include /etc/nginx/mime.types;
	default_type application/octet-stream;

	# Name servers used to resolve names of upstream servers into addresses.
	# It's also needed when using tcpsocket and udpsocket in Lua modules.
	#resolver 208.67.222.222 208.67.220.220;

	# Don't tell nginx version to clients.
	server_tokens off;

	# Specifies the maximum accepted body size of a client request, as
	# indicated by the request header Content-Length. If the stated content
	# length is greater than this size, then the client receives the HTTP
	# error code 413. Set to 0 to disable.
	client_max_body_size 20m;

        client_body_buffer_size 32k;

	# Timeout for keep-alive connections. Server will close connections after
	# this time.
	keepalive_timeout 65;

	# Sendfile copies data between one FD and other from within the kernel,
	# which is more efficient than read() + write().
	sendfile on;

	# Don't buffer data-sends (disable Nagle algorithm).
	# Good for sending frequent small bursts of data in real time.
	tcp_nodelay on;

	# Causes nginx to attempt to send its HTTP response head in one packet,
	# instead of using partial frames.
	#tcp_nopush on;


	# Path of the file with Diffie-Hellman parameters for EDH ciphers.
	#ssl_dhparam /etc/ssl/nginx/dh2048.pem;

	# Specifies that our cipher suits should be preferred over client ciphers.
	ssl_prefer_server_ciphers on;

	# Enables a shared SSL cache with size that can hold around 8000 sessions.
	ssl_session_cache shared:SSL:2m;


	# Enable gzipping of responses.
	#gzip on;

	# Set the Vary HTTP header as defined in the RFC 2616.
	gzip_vary on;

	# Enable checking the existence of precompressed files.
	#gzip_static on;


	# Specifies the main log format.
	log_format main '\\\$remote_addr - \\\$remote_user [\\\$time_local] "\\\$request" '
			'\\\$status \\\$body_bytes_sent "\\\$http_referer" '
			'"\\\$http_user_agent" "\\\$http_x_forwarded_for"';

	# Sets the path, format, and configuration for a buffered log write.
	access_log /var/log/nginx/access.log main;


	# Includes virtual hosts configs.
	include /etc/nginx/conf.d/*.conf;
}
EOF
echo "END - /etc/nginx/nginx.conf created"
CREATE_NGINX_CONF

echo "END - create_nginx_conf.sh created"



echo "====================================="
echo ""

echo "START - Creating printContents.sh"
cat > printContents.sh<<EOF
#!/bin/sh

while read -r line; do
        request=\$(echo "\$line" | jq .request);
        requestBody=\$(echo "\$line" | jq .requestBody);
	requestBodyRaw=\$(echo "\$line" | jq -r .requestBody);
        responseBody=\$(echo "\$line" | jq .responseBody);
        httpStatus=\$(echo "\$line" | jq -r .status);
	requestHeaders=\$(echo "\$line" | jq -r .requestHeaders);
	upstreamAddress=\$(echo "\$line" | jq -r .upstreamAddress);
	scheme=\$(echo "\$line" | jq -r .scheme);
	requestUri=\$(echo "\$line" | jq -r .requestUri);
	requestArgs=\$(echo "\$line" | jq -r .requestArgs);
	requestMethod=\$(echo "\$line" | jq -r .requestMethod);

	if [ -z "\$requestArgs" ]
	then
		requestUrl=\$(echo "\$scheme://\$upstreamAddress\$requestUri");
	else
	  	requestUrl=\$(echo "\$scheme://\$upstreamAddress\$requestUri?\$requestArgs");
	fi

	echo "###################################################################################################################################";
        echo "###################################################      REQUEST START      #######################################################";
	echo "###################################################################################################################################";
	echo "_______________________________________________________";
	echo "++++++       CURL CODE SNIPPET START             ++++++";
	echo "-------------------------------------------------------";
	echo "curl --request \$requestMethod '\$requestUrl' \\\\"
	OIFS=\$IFS
	IFS=";";
	for headerKeyValue in \$requestHeaders;
	do
		case \$headerKeyValue in
			"transfer-encoding:"*)  ;;
			*)			echo "--header '\$headerKeyValue' \\\\" ;;
		esac
	done
	IFS=\$OIFS

	if [ ! -z "\$requestBodyRaw" ]
	then
		echo "--data-raw '\$requestBodyRaw'"
	fi
	echo "_______________________________________________________";
	echo "++++++       CURL CODE SNIPPET END               ++++++";
	echo "-------------------------------------------------------";

        #echo "REQUEST: \$request";
	#echo "HOST: \$upstreamAddress";
	echo "REQUEST URL: \$requestUrl";
	echo "REQUEST METHOD: \$requestMethod";
        echo "STATUS CODE: \$httpStatus";
	echo "REQUEST HEADERS: ";
        echo "\$requestHeaders" | tr ";" "\n";

        formatRequestBody=\$(echo \$requestBody | jq '.| fromjson' 2>&1);

        if [ \$? -eq 0 ]
        then
                echo "REQUEST BODY:"
                echo "\$formatRequestBody"
        else
                REQ_BODY=\$(echo \$requestBody | jq -r . 2>&1);
                if [ \$? -eq 0 ] && [ -z "\$REQ_BODY" ]
                then
                        echo "(No Request Body)"
                else
                        echo "REQUEST BODY: (Parse Error Caught while logging)"
                        echo \$REQ_BODY
                fi
        fi

        formatResponseBody=\$(echo \$responseBody | jq '.| fromjson' 2>&1);
        if [ \$? -eq 0 ]
        then
                echo "RESPONSE BODY:"
                echo "\$formatResponseBody"
        else
                RESP_BODY=\$(echo \$responseBody | jq -r . 2>&1);
                if [ \$? -eq 0 ] && [ -z "\$RESP_BODY" ]
                then
                        echo "(No Response Body)"
                else
                        echo "RESPONSE BODY: (Parse Error Caught while logging)"
                        echo \$RESP_BODY
                fi
        fi
        echo "###################################################################################################################################";
        echo "###################################################      REQUEST END      #########################################################";
        echo "###################################################################################################################################";
done
EOF
echo "END - printContents.sh file created"

echo "START - Create run-nginx.sh"
cat > run-nginx.sh<<EOF
#!/bin/bash

for ARGUMENT in "\$@"
do

    KEY=\$(echo \$ARGUMENT | cut -f1 -d=)
    VALUE=\$(echo \$ARGUMENT | cut -f2 -d=)

    case "\$KEY" in
            --local-ports)              local_ports=\${VALUE} ;;
            --remote-destinations)    remote_destinations=\${VALUE} ;;
            *)
    esac

done

echo "run-nginx:Local Ports: \$local_ports"
echo "run-nginx:Remote Destinations: \$remote_destinations"

./create_nginx_conf.sh --local-ports=\$local_ports --remote-destinations=\$remote_destinations

nginx
tail -F /var/log/nginx/server.log | ./printContents.sh
EOF
echo "END - run-nginx.sh"

echo "Creating Dockerfile for api_watch installation"
cat > Dockerfile_api_watch<<EOF
FROM alpine:3.6

RUN apk add --no-cache nginx-mod-http-lua nginx-mod-http-echo jq
RUN apk update
RUN apk upgrade
RUN apk add bash

# Delete default config
RUN rm -r /etc/nginx/conf.d
#RUN rm /etc/nginx/nginx.conf

# Create folder for PID file
RUN mkdir -p /run/nginx

# Add our nginx conf
#COPY ./nginx.conf /etc/nginx/nginx.conf
COPY ./printContents.sh /printContents.sh
COPY ./create_nginx_conf.sh /create_nginx_conf.sh
COPY ./run-nginx.sh /run-nginx.sh
RUN chmod +x /printContents.sh
RUN chmod +x /run-nginx.sh
RUN chmod +x /create_nginx_conf.sh

#CMD ["nginx"]
#CMD ["./run-nginx.sh"]
ENTRYPOINT ["sh","/run-nginx.sh"]
EOF
echo "END - Creating Dockerfile_api_watch"

echo "Creating Docker image"
docker build -f Dockerfile_api_watch -t api_watch:d0.2 .

if [ $? -eq 0 ]
then
	echo "Cleaning up files"
	#rm printContents.sh run-nginx.sh Dockerfile_api_watch create_nginx_conf.sh
fi

echo "START - Create startApiWatch.sh"
cat > startApiWatch.sh<<EOF
#!/bin/bash
#LOCAL_PORTS="9901,9902"
#REMOTE_HOSTS="http://10.1.1.1:9087,http://11.1.1.1:9999"
LOCAL_PORTS=\`cat \$1 | grep "LOCAL_PORTS" | cut -d'=' -f2\`
REMOTE_HOSTS=\`cat \$1 | grep "REMOTE_HOSTS" | cut -d'=' -f2\`


OLD_IFS=\$IFS
IFS=','
exposed_ports=(\$LOCAL_PORTS)
exposed_hosts=(\$REMOTE_HOSTS)

IFS=\$OLD_IFS;

IFS=
for exposed_port_index in "\${!exposed_ports[@]}";
do
        DOCKER_PORTS="\${DOCKER_PORTS}-p \${exposed_ports[exposed_port_index]}:\${exposed_ports[exposed_port_index]} "
done

echo "Docker ports: \$DOCKER_PORTS"
DOCKER_COMMAND="docker run -it --rm \$DOCKER_PORTS api_watch:d0.2 --local-ports=\$LOCAL_PORTS --remote-destinations=\$REMOTE_HOSTS"
eval \$DOCKER_COMMAND
IFS=\$OLD_IFS;
EOF
echo "END - created startApiWatch.sh"

chmod +x startApiWatch.sh

echo "Done creating Docker image"
echo "\n"
echo "============================================================"
echo "Use the below command to run the docker"
#echo "docker run -it --name=api_watch_0_2 --rm -p 9901:9901 -p 9902:9902 -p 9903:9903 -p 9904:9904 -v `pwd`/nginx.conf:/etc/nginx/nginx.conf api_watch:d0.2 >> `pwd`/logs.log"
echo "./startApiWatch.sh"
echo "\n"
#echo "After making any changes to nginx.conf from your local volume, use the below command to reload configuration"
#echo "docker exec -it api_watch_0_2 nginx -s reload"
echo "============================================================"
echo "\n"

