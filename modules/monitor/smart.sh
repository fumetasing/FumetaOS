#!/bin/bash

###########################################################
# FumetaOS
# Módulo SMART
###########################################################

source /opt/fumetaos/core/common.sh

WATCH=0
ERROR=0

if [ "${1:-}" = "--watch" ]; then
	WATCH=1
fi

elevar_error() {
	if [ "$1" -gt "$ERROR" ]; then
		ERROR="$1"
	fi
}

mostrar_correcto() {
	local name="$1"

	if [ "$WATCH" -eq 0 ]; then
		echo "✅ $name"
	fi
}

mostrar_no_disponible() {
	local name="$1"

	if [ "$WATCH" -eq 0 ]; then
		echo "⚠️ $name (no se ha podido comprobar)"
	else
		echo "No se ha podido comprobar SMART de $name"
	fi

	elevar_error 10
}

mostrar_fallo() {
	local name="$1"

	if [ "$WATCH" -eq 0 ]; then
		echo "🚨 $name"
	else
		echo "Problema SMART en $name"
	fi

	elevar_error 20
}

comprobar_disco() {
	local disk="$1"
	local name
	local output

	name="$(disk_name "$disk")"
	output="$(smartctl_cmd -H "$disk" 2>&1)"

	case "$output" in
	*PASSED*)
		mostrar_correcto "$name"
		;;
	*FAILED*)
		mostrar_fallo "$name"
		;;
	*)
		mostrar_no_disponible "$name"
		;;
	esac
}

comprobar_disco "$SSD_DEVICE"
comprobar_disco "$HDD_DEVICE"

if [ "$WATCH" -eq 0 ]; then
	wd=/dev/disk/by-id/usb-WD_Elements_25A3_3444475A3245315A-0:0
	if [ ! -b "$wd" ]; then
		echo 'ℹ️ USB WD: desconectado'
	else
		opciones=(-d sat)
		if [ "${FUMETAOS_SMART_WAKE_WD:-0}" != 1 ]; then
			opciones+=(-n standby,3,5)
		fi
		resultado=0
		salud="$(smartctl_cmd "${opciones[@]}" -H "$wd" 2>&1)" || resultado=$?
		case "$salud" in
			*PASSED*) mostrar_correcto 'USB WD' ;;
			*FAILED*) mostrar_fallo 'USB WD' ;;
			*)
				if [ "$resultado" -eq 3 ] && [[ "$salud" == *'Device is in'* ]]; then
					echo 'ℹ️ USB WD: en reposo'
				else
					mostrar_no_disponible 'USB WD'
				fi
				;;
		esac
	fi
fi

exit "$ERROR"
