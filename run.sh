#!/bin/bash

usage() {
	echo "server-v2ray -u|--uuid <vmess-uuid> [-p|--port <port-num>] [-l|--level <level>] [-a|--alterid <alterid>] [-k|--hook hook-url] [--wp <websocket-path>] [--nginx <domain-name>] [--nginx-port <port-num>] [--no-ssl]"
	echo "    -u|--uuid <vmess-uuid>    Vmess UUID for initial V2ray connection"
	echo "    -p|--port <port-num>      [Optional] Port number for V2ray connection, default 10086"
	echo "    -l|--level <level>        [Optional] Level number for V2ray service access, default 0"
	echo "    -a|--alterid <alterid>    [Optional] AlterID number for V2ray service access, default 16"
	echo "    -k|--hook <hook-url>      [Optional] URL to be hit before server execution, for DDNS update or notification"
	echo "    --wp <websocket-path>     [Optional] Enable websocket with websocket-path setting, e.g. '/wsocket'. default disable"
	echo "    --nginx <domain-name>     [Optional] Enable ngnix proxy-front with specific domain-name, default disable, must be applied with --wp enabled"
	echo "    --nginx-port <port-num>   [Optional] Enable ngnix for domain name hosting, default 8443, must be applied with --nginx enabled"
	echo "    --no-ssl                  [Optional] Disable ngnix SSL support to accelerate CDN connection, must be applied with --nginx enabled."
}

TEMP=`getopt -o u:p:l:a:k: --long uuid:,port:,level:,alterid:hook:wp:nginx:nginx-port:nginx-ssl -n "$0" -- $@`
if [ $? != 0 ] ; then usage; exit 1 ; fi

eval set -- "$TEMP"
while true ; do
	case "$1" in
		-u|--uuid)
			UUID="$2"
			shift 2
			;;
		-p|--port)
			PORT="$2"
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
			WSPATH="$2"
			shift 2
			;;
		--nginx)
			DOMAIN="$2"
			shift 2
			;;
		--nginx-port)
			NGPORT="$2"
			shift 2
			;;
		--nginx-ssl)
			NGSSL="true"
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

if [ -z "${PORT}" ]; then
	PORT=10086
fi

if [ -z "${ALTERID}" ]; then
	ALTERID=16
fi

if [ -z "${LEVEL}" ]; then
	LEVEL=0
fi

if [ -n "${HOOKURL}" ]; then
	curl -sSL "${HOOKURL}"
	echo
fi

cd /tmp
cp /usr/bin/v2ray/vpoint_vmess_freedom.json vvf.json
jq "(.inbounds[] | select( .protocol == \"vmess\") | .port) |= \"${PORT}\"" vvf.json >vvf.json.1
jq "(.inbounds[] | select( .protocol == \"vmess\") | .settings.clients[0].id) |= \"${UUID}\"" vvf.json.1 >vvf.json.2
jq "(.inbounds[] | select( .protocol == \"vmess\") | .settings.clients[0].level) |= ${LEVEL}" vvf.json.2 >vvf.json.3
jq "(.inbounds[] | select( .protocol == \"vmess\") | .settings.clients[0].alterId) |= ${ALTERID}" vvf.json.3 >server.json
exec /usr/bin/v2ray/v2ray -config=/tmp/server.json
