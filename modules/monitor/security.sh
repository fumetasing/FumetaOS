#!/bin/bash

ERROR=0
UFW_BIN="/usr/sbin/ufw"
DOCKER_STATUS="/opt/fumetaos/bin/fumetaos-docker-firewall-status"

elevar_error() {
	if [ "$1" -gt "$ERROR" ]; then
		ERROR="$1"
	fi
}

comprobar_proteccion_docker() {
	echo

	if [ ! -x "$DOCKER_STATUS" ]; then
		echo "🔴 Protección Docker: verificador no disponible"
		elevar_error 20
		return
	fi

	if ! sudo -n "$DOCKER_STATUS" >/dev/null 2>&1; then
		echo "🔴 Protección Docker: no está activa o no se puede verificar"
		elevar_error 20
		return
	fi

	echo "🟢 Protección Docker activa"
	echo "🔒 LAN y Tailscale permitidos; Internet limitado a Transmission"
}

echo

if [ ! -x "$UFW_BIN" ]; then
	echo "🔴 Firewall UFW no instalado"
	exit 20
fi

if ! UFW_STATUS="$(LC_ALL=C sudo -n "$UFW_BIN" status verbose 2>/dev/null)"; then
	echo "🔴 No se puede consultar el Firewall UFW"
	exit 20
fi

STATUS="$(sed -n '1p' <<<"$UFW_STATUS")"

if [ "$STATUS" = "Status: active" ]; then
	echo "🟢 Firewall UFW activo"
else
	echo "🔴 Firewall UFW inactivo o estado desconocido"
	elevar_error 20
fi

POLICY="$(sed -n '/^Default:/ {p; q;}' <<<"$UFW_STATUS")"

if [ -n "$POLICY" ]; then
	echo "🔒 $POLICY"
fi

comprobar_proteccion_docker

exit "$ERROR"
