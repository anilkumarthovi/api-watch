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

echo "Local Ports: $local_ports"
echo "Remote Destinations: $remote_destinations"

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
                                          '"remoteAddress": "\$remote_addr",'
                                          '"host": "\$host",'
					  '"proxyHost": "\$proxy_host",'
                                          '"upstreamAddress": "\$upstream_addr",'
					  '"requestUri": "\$request_uri",'
					  '"scheme": "\$scheme",'
                                          '"remoteUser": "\$remote_user",'
                                          '"timeLocal": "\$time_local",'
					  '"requestMethod": "\$request_method",'
					  '"requestUri": "\$uri",'
					  '"requestArgs": "\$args",'
					  '"requestHeaders": "\$request_headers",'
                                          '"request": "\$request",'
                                          '"status": "\$status",'
                                          '"bodyBytesSent": "\$body_bytes_sent",'
                                          '"httpReferer": "\$http_referer",'
                                          '"httpUserAgent": "\$http_user_agent",'
                                          '"requestTime": "\$request_time",'
                                          '"requestBody": "\$request_body",'
                                          '"responseBody": "\$resp_body"'
                                        '}';

        lua_need_request_body on;
EOF


OLD_IFS=$IFS
IFS=','
#exposed_ports=($EXPOSED_PORTS)
#exposed_hosts=($EXPOSED_HOSTS)
exposed_ports=($local_ports)
exposed_hosts=($remote_destinations)

IFS=$OLD_IFS;


for exposed_port_index in "${!exposed_ports[@]}"
do
	echo "
	server {
		set \$resp_body \"\";

		set_by_lua \$request_headers '
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

        	listen ${exposed_ports[exposed_port_index]};

        	location / {
                	echo_read_request_body;
                	proxy_set_header Accept-Encoding '';
                	proxy_pass ${exposed_hosts[exposed_port_index]};            # msp.service.hostname
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
	log_format main '\$remote_addr - \$remote_user [\$time_local] "\$request" '
			'\$status \$body_bytes_sent "\$http_referer" '
			'"\$http_user_agent" "\$http_x_forwarded_for"';

	# Sets the path, format, and configuration for a buffered log write.
	access_log /var/log/nginx/access.log main;


	# Includes virtual hosts configs.
	include /etc/nginx/conf.d/*.conf;
}
EOF
echo "END - /etc/nginx/nginx.conf created"
