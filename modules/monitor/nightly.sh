#!/bin/bash

# Estado de la última cadena nocturna, dentro del informe diario existente.
STATUS_FILE="${FUMETAOS_NIGHTLY_STATUS_FILE:-/var/lib/fumetaos-nightly-status}"

format_time() {
	date -d "@$1" '+%d/%m/%Y %H:%M' 2>/dev/null ||
		date -r "$1" '+%d/%m/%Y %H:%M'
}

if [ ! -e "$STATUS_FILE" ]; then
	echo 'ℹ️ Cadena nocturna: pendiente de registrar la primera ejecución'
	exit 0
fi

if [ ! -r "$STATUS_FILE" ]; then
	echo '🔴 Cadena nocturna: no se puede leer el resultado'
	exit 20
fi

version='' start='' end='' result='' step='' failed=''
while IFS= read -r line || [ -n "$line" ]; do
	key=${line%%=*}
	value=${line#*=}
	case "$key" in
	version) version=$value ;;
	start) start=$value ;;
	end) end=$value ;;
	result) result=$value ;;
	step) step=$value ;;
	failed) failed=$value ;;
	esac
done <"$STATUS_FILE"

if [ "$version" != 1 ] ||
	! [[ "$start" =~ ^[1-9][0-9]*$ ]] ||
	! [[ "$end" =~ ^(0|[1-9][0-9]*)$ ]] ||
	[[ "$step" == *$'\n'* ]] ||
	[[ "$failed" == *$'\n'* ]]; then
	echo '🔴 Cadena nocturna: resultado no válido'
	exit 20
fi

now=$(date +%s)
if [ "$start" -gt $((now + 300)) ]; then
	echo '🔴 Cadena nocturna: hora de inicio no válida'
	exit 20
fi

started_at=$(format_time "$start")

case "$result" in
success | failed)
	if [ "$end" -lt "$start" ] || [ "$end" -gt $((now + 300)) ]; then
		echo '🔴 Cadena nocturna: hora de fin no válida'
		exit 20
	fi
	ended_at=$(format_time "$end")
	;;
running)
	if [ "$end" -ne 0 ]; then
		echo '🔴 Cadena nocturna: resultado no válido'
		exit 20
	fi
	;;
*)
	echo '🔴 Cadena nocturna: resultado no válido'
	exit 20
	;;
esac

case "$result" in
success)
	if [ $((now - start)) -gt $((36 * 3600)) ]; then
		echo "🔴 Cadena nocturna: sin ejecución reciente (última: $started_at)"
		exit 20
	fi
	echo '✅ Cadena nocturna completada'
	echo "   Inicio: $started_at"
	echo "   Fin: $ended_at"
	;;
failed)
	echo '🔴 Cadena nocturna terminada con errores'
	echo "   Inicio: $started_at"
	echo "   Fin: $ended_at"
	echo "   Falló: ${failed:-${step:-paso desconocido}}"
	exit 20
	;;
running)
	if [ $((now - start)) -gt $((12 * 3600)) ]; then
		echo "🔴 Cadena nocturna interrumpida (desde $started_at)"
		echo "   Último paso: ${step:-desconocido}"
		exit 20
	fi
	echo "🟡 Cadena nocturna en curso desde $started_at"
	echo "   Paso: ${step:-preparación}"
	exit 10
	;;
esac
