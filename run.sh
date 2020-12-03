#!/bin/bash

usage() {
	echo "server-v2ray -u|--uuid <vmess-uuid> [-p|--port <port-num>] [-l|--level <level>] [-a|--alterid <alterid>] [-k|--hook hook-url] [--wp <websocket-path>] [--nginx <domain-name>] [--nginx-port <port-num>] [--no-ssl]"
	echo "    -u|--uuid <vmess-uuid>    Vmess UUID for initial V2ray connection"
	echo "    -p|--port <port-num>      [Optional] V2ray listening port, default 10086"
	echo "    -l|--level <level>        [Optional] Level number for V2ray service access, default 0"
	echo "    -a|--alterid <alterid>    [Optional] AlterID number for V2ray service access, default 16"
	echo "    -k|--hook <hook-url>      [Optional] URL to be hit before server execution, for DDNS update or notification"
	echo "    --wp <websocket-path>     [Optional] Enable websocket with websocket-path setting, e.g. '/wsocket'. default disable"
	echo "    --nginx <domain-name>     [Optional] Enable Ngnix frontend with given domain-name, must be applied with --wp enabled"
	echo "    --nginx-port <port-num>   [Optional] Ngnix listening port, default 443, must be applied with --nginx enabled"
	echo "    --share-cert <cert-path>  [Optional] Waiting for cert populating in given path instead of requesting. default disable"
	echo "    --no-ssl                  [Optional] Disable Ngnix SSL support for CDN optimisation, must be applied with --nginx enabled"
}

TEMP=`getopt -o u:p:l:a:k: --long uuid:,port:,level:,alterid:,hook:,wp:,nginx:,nginx-port:,share-cert:,nginx-ssl -n "$0" -- $@`
if [ $? != 0 ] ; then usage; exit 1 ; fi

eval set -- "$TEMP"
while true ; do
	case "$1" in
		-u|--uuid)
			UUID="$2"
			shift 2
			;;
		-p|--port)
			VPORT="$2"
			shift 2
			;;
		-l|--level)
			LEVEL="$2"
			shift 2
			;;
		-a|--alterid)
			ALTERID="$2"
			shift 2
			;;
		-k|--hook)
			HOOKURL="$2"
			shift 2
			;;
		--wp)
			if [[ $2 =~ ^\/[A-Za-z0-9_-]{1,16}$ ]]; then
				WSPATH="$2"
				shift 2
			else
				echo "Websocket path must be 1-16 aplhabets, numbers, '-' or '_' started with '/'"
				exit
			fi
			;;
		--nginx)
			NGDOMAIN="$2"
			shift 2
			;;
		--nginx-port)
			NGPORT="$2"
			shift 2
			;;
		--share-cert)
			SHARECERT="$2"
			shift 2
			;;
		--no-ssl)
			NOSSL="true"
			shift 1
			;;
		--)
			shift
			break
			;;
		*)
			usage;
			exit 1
			;;
	esac
done

if [ -z "${UUID}" ]; then
	usage
	exit 1
fi

if [ -z "${VPORT}" ]; then
	VPORT=10086
fi

if [ -z "${ALTERID}" ]; then
	ALTERID=16
fi

if [ -z "${LEVEL}" ]; then
	LEVEL=0
fi

if [ -z "${NGPORT}" ]; then
	NGPORT=443
fi

if [ -n "${HOOKURL}" ]; then
	curl -sSL "${HOOKURL}"
	echo
fi

if [ -z "${SHARECERT}" ]; then
	CERTPATH="/root/.acme.sh/${NGDOMAIN}"
else
	CERTPATH="${SHARECERT}"
fi

if [ -n "${NGDOMAIN}" ]; then
	if [ -z "${WSPATH}" ]; then
		echo "'--wp' option is missing, which is necessary for '--nginx' option. Abrot."
		exit 1
	fi

	if [ -z "${NOSSL}" ]; then
		TRY=0
		while [ ! -f "${CERTPATH}/fullchain.cer" ]
		do
			if [ -n "${SHARECERT}" ]; then
				echo "Cert populating not found, Waitting..."
			else
				echo "Cert requesting..."
				/root/.acme.sh/acme.sh --issue --standalone -d ${NGDOMAIN}
				((TRY++))
				if [ ${TRY} >= 3 ]; then
					echo "Requesting cert for ${NGDOMAIN} failed. Check log please."
					exit 3
				fi
			fi
			echo "Wait 10 seconds before cert checking again..."
			sleep 10
		done
	fi

	# Running as root to enable low port listening. Necessary for Fargate or k8s.
	sed -i 's/^user nginx;$/user root;/g' /etc/nginx/nginx.conf
	mkdir -p /run/nginx/

	cd /etc/nginx/conf.d/

	if [ -f /etc/nginx/conf.d/default.conf ]; then
		mv default.conf default.conf.disable
	fi

	if [ -z "${NOSSL}" ]; then
		TPL="site-ssl.conf.tpl"
	else
		TPL="site-non-ssl.conf.tpl"
	fi

	cat ${TPL} \
		| sed "s/CERTPATH/${CERTPATH}/g" \
		| sed "s/NGDOMAIN/${NGDOMAIN}/g" \
		| sed "s/NGPORT/${NGPORT}/g" \
		| sed "s/VPORT/${VPORT}/g" \
		| sed "s/WSPATH/\\${WSPATH}/g" \
		>v2site.conf

fi

cd /tmp
cat /usr/bin/v2ray/vpoint_vmess_freedom.json \
	| jq "(.inbounds[] | select( .protocol == \"vmess\") | .port) |= \"${VPORT}\"" - \
	| jq "(.inbounds[] | select( .protocol == \"vmess\") | .settings.clients[0].id) |= \"${UUID}\"" - \
	| jq "(.inbounds[] | select( .protocol == \"vmess\") | .settings.clients[0].level) |= ${LEVEL}" - \
	| jq "(.inbounds[] | select( .protocol == \"vmess\") | .settings.clients[0].alterId) |= ${ALTERID}" - \
	>server.json

if [ -n "${WSPATH}" ]; then
	cat server.json \
		| jq "(.inbounds[] | select( .protocol == \"vmess\")) +=  {\"streamSettings\":{\"network\":\"ws\",\"wsSettings\":{\"path\":\"${WSPATH}\"}}}" - \
		>server-ws.json
	mv server-ws.json server.json
fi

nginx
exec /usr/bin/v2ray/v2ray -config=/tmp/server.json
