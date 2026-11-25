#!/bin/bash

###########################################################
# FumetaOS
# Monitor de memoria
###########################################################

source "$(dirname "${BASH_SOURCE[0]}")/../../core/system.sh"

WATCH=0

if [ "${1:-}" = "--watch" ]; then
	WATCH=1
fi

if ! read -r USO USED_MB TOTAL_MB < <(ram_metrics); then
	[ "$WATCH" -eq 0 ] && echo "❓ No se pudo leer la memoria"
	exit 20
fi

MEMORIA="${USED_MB} MB / $(ram_total_label "$TOTAL_MB")"

if [ "$USO" -lt "$RAM_WARNING" ]; then
	if [ "$WATCH" -eq 0 ]; then
		echo "🟢 Uso: ${USO}%"
		echo "   $MEMORIA"
	fi

	exit 0
elif [ "$USO" -lt "$RAM_CRITICAL" ]; then
	if [ "$WATCH" -eq 0 ]; then
		echo "🟡 Uso: ${USO}%"
		echo "   $MEMORIA"
	else
		echo "RAM al ${USO}%"
	fi

	exit 10
else
	if [ "$WATCH" -eq 0 ]; then
		echo "🔴 Uso: ${USO}%"
		echo "   $MEMORIA"
	else
		echo "RAM al ${USO}%"
	fi

	exit 20
fi
