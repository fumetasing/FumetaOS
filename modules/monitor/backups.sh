#!/bin/bash

###########################################################
# FumetaOS - Monitor de copias (solo consulta)
###########################################################

case "$#:${1:-}" in
0:) ;;
1:--solo-historial) ;;
*)
	printf 'Uso: %s [--solo-historial]\n' "${0##*/}" >&2
	exit 2
	;;
esac

if [ "$#" -eq 0 ]; then
	source "$(dirname "${BASH_SOURCE[0]}")/../../core/mac-mirror-common.sh"
fi

ERROR=0
NOW=$(date +%s)
DAILY_LIMIT=$((30 * 3600))
WEEKLY_LIMIT=$((8 * 24 * 3600))

LOCAL="fumetaos-backup.service"
TC="fumetaos-timecapsule-mac-backup.service"
RECOVERY="fumetaos-recovery-backup.service"
GENERAL="fumetaos-mac-backup.service"
VERIFY="fumetaos-recovery-verify.service"
NIGHTLY_TIMER="fumetaos-nightly.timer"

elevar_error() {
	if [ "$1" -gt "$ERROR" ]; then
		ERROR="$1"
	fi
}

ultimo_evento() {
	local unit="$1"
	local output

	shift

	if ! output=$(
		timeout 5 journalctl \
			--quiet \
			--no-pager \
			--since="30 days ago" \
			-n 1 \
			-o short-unix \
			_PID=1 \
			"UNIT=$unit" \
			"$@" 2>/dev/null
	); then
		return 1
	fi

	printf '%s\n' "$output" |
		awk '
            $1 ~ /^[0-9]+\.[0-9]+$/ {
                split($1, parts, ".")
                printf "%s%06d\n", parts[1], parts[2]
                exit
            }
        '
}

UNITS=(
	"$LOCAL"
	"$TC"
	"$RECOVERY"
	"$GENERAL"
	"$VERIFY"
)

TIMERS=(
	"$NIGHTLY_TIMER"
)

declare -a STATE RESULT LOADED OK BAD HISTORY
declare -A TIMER_STATE TIMER_NEXT

leer_servicio() {
	local idx="$1"
	local unit="${UNITS[$1]}"
	local output
	local key
	local value

	LOADED[$idx]=""
	STATE[$idx]=""
	RESULT[$idx]=""

	if output=$(
		timeout 5 systemctl show \
			"$unit" \
			-p LoadState \
			-p ActiveState \
			-p Result \
			2>/dev/null
	); then
		while IFS='=' read -r key value; do
			case "$key" in
			LoadState)
				LOADED[$idx]="$value"
				;;
			ActiveState)
				STATE[$idx]="$value"
				;;
			Result)
				RESULT[$idx]="$value"
				;;
			esac
		done <<<"$output"
	fi

	HISTORY[$idx]=1

	OK[$idx]=$(
		ultimo_evento \
			"$unit" \
			MESSAGE_ID=39f53479d3a045ac8e11786248231fbf
	) || HISTORY[$idx]=0

	BAD[$idx]=$(
		ultimo_evento \
			"$unit" \
			MESSAGE_ID=be02cf6855d2428ba40df7e9d022f03d \
			MESSAGE_ID=d9b373ed55a64feb8242e02dbe79a49c
	) || HISTORY[$idx]=0
}

leer_timer() {
	local timer="$1"
	local output
	local key
	local value

	TIMER_STATE["$timer"]=""
	TIMER_NEXT["$timer"]=""

	if output=$(
		timeout 5 systemctl show \
			"$timer" \
			-p ActiveState \
			-p NextElapseUSecRealtime \
			2>/dev/null
	); then
		while IFS='=' read -r key value; do
			case "$key" in
			ActiveState)
				TIMER_STATE["$timer"]="$value"
				;;
			NextElapseUSecRealtime)
				TIMER_NEXT["$timer"]="$value"
				;;
			esac
		done <<<"$output"
	fi
}

en_curso() {
	case "${STATE[$1]}" in
	activating | active | reloading | deactivating)
		return 0
		;;
	*)
		return 1
		;;
	esac
}

ha_fallado() {
	local idx="$1"

	[ "${STATE[$idx]}" = "failed" ] && return 0

	case "${RESULT[$idx]}" in
	"" | success) ;;
	*)
		return 0
		;;
	esac

	[ "${BAD[$idx]:-0}" -gt "${OK[$idx]:-0}" ]
}

mostrar_usb() {
    local wd=/mnt/data-wd
    if [ "$(findmnt -n -o UUID -M "$wd")" = 87d65071-48b3-439c-8e8d-4216f3c60d5d ]; then
        echo "🟢 Data WD en Ubuntu"
        df -h --output=avail,pcent -- "$wd" | awk 'NR==2 {print "   Libre: " $1; print "   Uso: " $2}'
    else
        echo "🔴 Data WD no está montado en Ubuntu"
        elevar_error 20
    fi
}

mostrar_copia() {
	local idx="$1"
	local unit="${UNITS[$1]}"
	local timer="$2"
	local label="$3"
	local limit="$4"
	local level=0
	local icon="✅"
	local detail=""
	local next
	local last
	local age=0

	next="${TIMER_NEXT[$timer]}"

	case "$next" in
	"" | n/a)
		next="No programada"
		;;
	esac

	last="No consta en el registro accesible de los últimos 30 días"

	if [ "${OK[$idx]:-0}" -gt 0 ]; then
		last=$(
			date \
				-d "@$((OK[$idx] / 1000000))" \
				'+%d/%m/%Y %H:%M:%S %Z'
		)

		age=$((NOW - OK[$idx] / 1000000))
	fi

	if [ "${LOADED[$idx]}" != "loaded" ]; then
		level=20
		detail="Servicio no disponible"

	elif en_curso "$idx"; then
		level=10
		detail="En curso; todavía no ha terminado"

	elif ha_fallado "$idx"; then
		level=20
		detail="Última ejecución fallida (ver registro del servicio)"

	elif [ "${HISTORY[$idx]}" != 1 ]; then
		level=10
		detail="No se pudo consultar todo el historial; estado no confirmado"

	elif [ "${OK[$idx]:-0}" -eq 0 ]; then
		level=10
		detail="No se puede confirmar una ejecución correcta"
	fi

	if [ "${OK[$idx]:-0}" -gt 0 ]; then
		if [ "$age" -lt 0 ]; then
			[ "$level" -lt 10 ] && level=10
			detail="${detail:+$detail. }Fecha futura: revisar el reloj"

		elif [ "$age" -gt "$limit" ]; then
			level=20
			detail="${detail:+$detail. }Atrasada: $((age / 3600)) h sin completar; límite $((limit / 3600)) h"
		fi
	fi

	if [ "${TIMER_STATE[$timer]}" != "active" ]; then
		level=20
		detail="${detail:+$detail. }Temporizador inactivo o no disponible"

	elif [ "$next" = "No programada" ]; then
		[ "$level" -lt 10 ] && level=10
		detail="${detail:+$detail. }Sin próxima fecha disponible"
	fi

	case "$unit" in
	"$LOCAL")
		next="Inicio de cadena: $next"
		;;
	"$TC")
		next="Tras la copia local (cadena inicia: $next)"
		;;
	"$RECOVERY")
		next="Tras Time Capsule → Data WD (cadena inicia: $next)"
		;;
	"$GENERAL")
		next="Tras la recuperación (cadena inicia: $next)"
		;;
	"$VERIFY")
		next="Los lunes, tras actualizar Ubuntu (cadena inicia a las 00:30)"
		;;
	esac

	case "$level" in
	10)
		icon="🟡"
		;;
	20)
		icon="🔴"
		;;
	esac

	echo "$icon $label"
	echo "   Última correcta: $last"
	[ -z "$detail" ] || echo "   Estado: $detail"
	echo "   Próxima: $next"

	elevar_error "$level"
}

for idx in "${!UNITS[@]}"; do
	leer_servicio "$idx"
done

for timer in "${TIMERS[@]}"; do
	leer_timer "$timer"
done

if [ "$#" -eq 0 ]; then
	echo
	mostrar_usb
fi

echo
mostrar_copia \
	0 \
	"$NIGHTLY_TIMER" \
	"Copia local" \
	"$DAILY_LIMIT"

echo
mostrar_copia \
	1 \
	"$NIGHTLY_TIMER" \
	"Time Capsule → Data WD" \
	"$DAILY_LIMIT"

echo
mostrar_copia \
	2 \
	"$NIGHTLY_TIMER" \
	"Recuperación cifrada y máquinas virtuales" \
	"$DAILY_LIMIT"

echo
mostrar_copia \
	3 \
	"$NIGHTLY_TIMER" \
	"Espejo general a Data WD" \
	"$DAILY_LIMIT"

echo
mostrar_copia \
	4 \
	"$NIGHTLY_TIMER" \
	"Verificación cifrada" \
	"$WEEKLY_LIMIT"

exit "$ERROR"
