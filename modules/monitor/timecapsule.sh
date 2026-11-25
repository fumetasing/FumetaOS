#!/bin/bash

###########################################################
# FumetaOS
# Monitor Time Capsule
###########################################################

source /opt/fumetaos/core/common.sh

TIMECAPSULE_MOUNT="/mnt/timecapsule"
CASAOS_MOUNT="/DATA/TimeCapsule"
SMB_CLIENT="/usr/sbin/mount.cifs"

ERROR=0

mostrar_detalles() {
	echo "   SMB: $TIMECAPSULE_MOUNT"
	echo "   CasaOS: $CASAOS_MOUNT"
	echo "   Protocolo configurado: SMB 3.1.1"
	echo "   Acceso: $1"
}

if [ ! -x "$SMB_CLIENT" ]; then

	echo "🔴 Cliente SMB no disponible"
	echo "   Esperado: $SMB_CLIENT"
	ERROR=20

elif ! systemctl is-active --quiet fumetaos-timecapsule.service; then

	echo "🔴 Servicio SMB de Time Capsule no activo"
	ERROR=20

elif [ "$(findmnt -rn -M "$TIMECAPSULE_MOUNT" -o FSTYPE 2>/dev/null)" != "cifs" ]; then

	echo "🔴 Time Capsule SMB no montada"
	echo "   Punto interno: $TIMECAPSULE_MOUNT"
	ERROR=20

elif ! systemctl is-active --quiet fumetaos-timecapsule-casaos.service; then

	echo "🔴 Servicio de Time Capsule para CasaOS no activo"
	ERROR=20

elif ! findmnt -rn -M "$CASAOS_MOUNT" >/dev/null 2>&1; then

	echo "🔴 Time Capsule no disponible en CasaOS"
	echo "   Punto esperado: $CASAOS_MOUNT"
	ERROR=20

elif ! timeout --kill-after=5 15 ls "$CASAOS_MOUNT" >/dev/null 2>&1; then

	echo "🔴 Time Capsule montada pero sin acceso desde CasaOS"
	echo "   Punto: $CASAOS_MOUNT"
	ERROR=20

else
	acceso_disponible=1
	ESPACIO="$(
		timeout --kill-after=5 15 df -hP "$TIMECAPSULE_MOUNT" |
			awk 'NR == 2 { gsub("%", "", $5); print $4 "|" $5 }'
	)"

	LIBRE="${ESPACIO%|*}"
	USO="${ESPACIO#*|}"

	if [[ ! "$USO" =~ ^[0-9]+$ ]]; then
		echo "🔴 No se pudo determinar el uso de Time Capsule"
		ERROR=20
	elif [ "$USO" -gt "$DISK_CRITICAL" ]; then
		echo "🔴 Time Capsule SMB — espacio crítico"
		ERROR=20
	elif [ "$USO" -ge "$DISK_CRITICAL" ]; then
		echo "🟠 Time Capsule SMB — vigilar espacio"
		ERROR=10
	elif [ "$USO" -ge "$DISK_WARNING" ]; then
		echo "🟡 Time Capsule SMB — vigilar espacio"
		ERROR=10
	else
		echo "🟢 Time Capsule SMB"
	fi

	if [ "$ERROR" -ne 0 ] || [ "${1:-}" = "--detalles" ]; then
		mostrar_detalles disponible
	fi
	echo "   Libre: $LIBRE"
	echo "   Uso:   ${USO}%"

	case "$USO" in
	'' | *[!0-9]*) ;;
	*)
		if [ "$USO" -gt "$DISK_CRITICAL" ]; then
			echo "   Umbral: crítico por encima del ${DISK_CRITICAL}%"
		elif [ "$USO" -ge "$DISK_WARNING" ]; then
			echo "   Umbral: aviso desde ${DISK_WARNING}%"
		fi
		;;
	esac
fi

if [ "${acceso_disponible:-0}" -eq 0 ]; then
	mostrar_detalles "no disponible"
fi

exit "$ERROR"
