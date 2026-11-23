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

despertar_para_informe() {
	[ "$WATCH" -eq 0 ] && [ "${FUMETAOS_REPORT_WAKE_SMART:-0}" = 1 ]
}

comprobar_disco() {
	local disk="$1"
	local name="$2"
	shift 2
	local -a opciones=("$@")
	local output estado intento intentos=1

	if despertar_para_informe; then
		intentos=4
	else
		opciones+=(-n 'standby,3,5')
	fi

	for ((intento = 1; intento <= intentos; intento++)); do
		estado=0
		output="$(LC_ALL=C smartctl_cmd "${opciones[@]}" -H "$disk" 2>&1)" || estado=$?
		case "$output" in
		*PASSED* | *FAILED*) break ;;
		esac
		if [ "$intento" -lt "$intentos" ]; then
			sleep 3
		fi
	done

	if [ "$estado" -eq 3 ] &&
		[[ "$output" == *"Device is in STANDBY"* || "$output" == *"Device is in SLEEP"* ]]; then
		if [ "$WATCH" -eq 0 ]; then
			mostrar_smart_nocturno "$disk" "$name"
		fi
		return
	fi

	case "$output" in
	*PASSED*) mostrar_correcto "$name" ;;
	*FAILED*) mostrar_fallo "$name" ;;
	*) mostrar_no_disponible "$name" ;;
	esac
}

mostrar_smart_nocturno() {
	local disk="$1" name="$2" resultado tipo='USB WD'
	local filtro='pruebas SMART cortas terminadas|prueba larga completada correctamente|prueba larga terminada y SMART correcto|^🔴 '
	local -a unidades=(-u fumetaos-smart-short-test.service)

	case "$disk" in
	"$HDD_DEVICE") tipo='HDD Datos' ;;
	"$SSD_DEVICE") tipo='SSD Sistema' ;;
	esac

	if [ "$tipo" != 'USB WD' ]; then
		unidades+=(-u fumetaos-smart-test.service)
	fi

	resultado="$(
		journalctl -q "${unidades[@]}" --grep "$filtro" --reverse -o cat --no-pager |
			awk -v disk="$disk" -v name="$tipo" '
				$0 == "🔴 La prueba corta no terminó correctamente en " disk ||
				$0 == "🔴 El registro no confirma la última prueba corta en " disk ||
				$0 == "🔴 Salud SMART incorrecta en " disk ||
				(name == "HDD Datos" && index($0, "🔴 HDD Datos: la prueba larga no terminó correctamente: ") == 1) ||
				(name == "SSD Sistema" && ($0 == "🔴 SSD Sistema: SMART no informa un estado correcto tras la prueba larga" ||
                    $0 == "🔴 SSD Sistema: la prueba larga no terminó correctamente")) {print "fallo"; exit}
				/^✅ HDD, SSD y WD USB: pruebas SMART cortas terminadas sin errores/ ||
				(name == "USB WD" && /^✅ WD USB: pruebas SMART cortas terminadas sin errores/) ||
				(name != "USB WD" && /^✅ HDD y SSD: pruebas SMART cortas terminadas sin errores/) ||
				$0 == "✅ " name ": prueba larga completada correctamente" ||
				$0 == "✅ " name ": prueba larga terminada y SMART correcto" {print "correcto"; exit}
			'
	)"
	case "$resultado" in
	correcto) mostrar_correcto "$name" ;;
	fallo) mostrar_fallo "$name" ;;
	*)
		echo "⚠️ $name (sin resultado SMART nocturno)"
		elevar_error 10
		;;
	esac
}

mostrar_smart_wd() {
	local wd=/dev/disk/by-id/usb-WD_Elements_25A3_3444475A3245315A-0:0

	if [ ! -b "$wd" ]; then
		echo 'ℹ️ USB WD: desconectado'
		return
	fi

	if despertar_para_informe; then
		comprobar_disco "$wd" "USB WD" -d sat
	else
		mostrar_smart_nocturno "$wd" "USB WD"
	fi
}

comprobar_disco "$SSD_DEVICE" "$(disk_name "$SSD_DEVICE")"
comprobar_disco "$HDD_DEVICE" "$(disk_name "$HDD_DEVICE")"

if [ "$WATCH" -eq 0 ]; then
	mostrar_smart_wd
fi

exit "$ERROR"
