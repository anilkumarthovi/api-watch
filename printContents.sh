#!/bin/sh

while read -r line; do
        request=$(echo "$line" | jq .request);
        requestBody=$(echo "$line" | jq .requestBody);
	requestBodyRaw=$(echo "$line" | jq -r .requestBody);
        responseBody=$(echo "$line" | jq .responseBody);
        httpStatus=$(echo "$line" | jq -r .status);
	requestHeaders=$(echo "$line" | jq -r .requestHeaders);
	upstreamAddress=$(echo "$line" | jq -r .upstreamAddress);
	scheme=$(echo "$line" | jq -r .scheme);
	requestUri=$(echo "$line" | jq -r .requestUri);
	requestArgs=$(echo "$line" | jq -r .requestArgs);
	requestMethod=$(echo "$line" | jq -r .requestMethod);

	if [ -z "$requestArgs" ]
	then
		requestUrl=$(echo "$scheme://$upstreamAddress$requestUri");
	else
	  	requestUrl=$(echo "$scheme://$upstreamAddress$requestUri?$requestArgs");
	fi

	echo "###################################################################################################################################";
        echo "###################################################      REQUEST START      #######################################################";
	echo "###################################################################################################################################";
	echo "_______________________________________________________";
	echo "++++++       CURL CODE SNIPPET START             ++++++";
	echo "-------------------------------------------------------";
	echo "curl --request $requestMethod '$requestUrl' \\"
	OIFS=$IFS
	IFS=";";
	for headerKeyValue in $requestHeaders;
	do
		case $headerKeyValue in
			"transfer-encoding:"*)  ;;
			*)			echo "--header '$headerKeyValue' \\" ;;
		esac
	done
	IFS=$OIFS

	if [ ! -z "$requestBodyRaw" ]
	then
		echo "--data-raw '$requestBodyRaw'"
	fi
	echo "_______________________________________________________";
	echo "++++++       CURL CODE SNIPPET END               ++++++";
	echo "-------------------------------------------------------";

        #echo "REQUEST: $request";
	#echo "HOST: $upstreamAddress";
	echo "REQUEST URL: $requestUrl";
	echo "REQUEST METHOD: $requestMethod";
        echo "STATUS CODE: $httpStatus";
	echo "REQUEST HEADERS: ";
        echo "$requestHeaders" | tr ";" "\n";

        formatRequestBody=$(echo $requestBody | jq '.| fromjson' 2>&1);

        if [ $? -eq 0 ]
        then
                echo "REQUEST BODY:"
                echo "$formatRequestBody"
        else
                REQ_BODY=$(echo $requestBody | jq -r . 2>&1);
                if [ $? -eq 0 ] && [ -z "$REQ_BODY" ]
                then
                        echo "(No Request Body)"
                else
                        echo "REQUEST BODY: (Parse Error Caught while logging)"
                        echo $REQ_BODY
                fi
        fi

        formatResponseBody=$(echo $responseBody | jq '.| fromjson' 2>&1);
        if [ $? -eq 0 ]
        then
                echo "RESPONSE BODY:"
                echo "$formatResponseBody"
        else
                RESP_BODY=$(echo $responseBody | jq -r . 2>&1);
                if [ $? -eq 0 ] && [ -z "$RESP_BODY" ]
                then
                        echo "(No Response Body)"
                else
                        echo "RESPONSE BODY: (Parse Error Caught while logging)"
                        echo $RESP_BODY
                fi
        fi
        echo "###################################################################################################################################";
        echo "###################################################      REQUEST END      #########################################################";
        echo "###################################################################################################################################";
done
