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

mostrar_smart_wd_nocturno() {
	local wd=/dev/disk/by-id/usb-WD_Elements_25A3_3444475A3245315A-0:0
	local correcto='WD USB: pruebas SMART cortas terminadas sin errores'
	local fallo="(La prueba corta no terminó correctamente en|El registro no confirma la última prueba corta en|Salud SMART incorrecta en) $wd"
	local resultado

	if [ ! -b "$wd" ]; then
		echo 'ℹ️ USB WD: desconectado'
		return
	fi

	resultado="$(journalctl -q -u fumetaos-smart-short-test.service --grep "$correcto|$fallo" -n 1 -o cat --no-pager)" || resultado=
	case "$resultado" in
		*"$correcto"*) mostrar_correcto 'USB WD' ;;
		'🔴 '*) mostrar_fallo 'USB WD' ;;
		*) mostrar_no_disponible 'USB WD (sin resultado SMART nocturno)' ;;
	esac
}

comprobar_disco "$SSD_DEVICE"
comprobar_disco "$HDD_DEVICE"

if [ "$WATCH" -eq 0 ]; then
	mostrar_smart_wd_nocturno
fi

exit "$ERROR"
