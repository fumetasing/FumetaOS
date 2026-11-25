#!/bin/bash

###########################################################
# FumetaOS
# Monitor de temperatura
###########################################################

source "$(dirname "${BASH_SOURCE[0]}")/../../core/system.sh"

WATCH=0

if [ "${1:-}" = "--watch" ]; then
	WATCH=1
fi

TEMP="$(cpu_temp)"

if [ -z "$TEMP" ]; then
	[ "$WATCH" -eq 0 ] && echo "❓ No se pudo leer la temperatura"
	exit 20
fi

if [ "$TEMP" -lt "$CPU_WARNING" ]; then
	[ "$WATCH" -eq 0 ] && echo "🌡️ CPU: ${TEMP}°C 🟢"
	exit 0
elif [ "$TEMP" -lt "$CPU_CRITICAL" ]; then
	if [ "$WATCH" -eq 0 ]; then
		echo "🌡️ CPU: ${TEMP}°C 🟡"
	else
		echo "CPU a ${TEMP}°C"
	fi

	exit 10
else
	if [ "$WATCH" -eq 0 ]; then
		echo "🌡️ CPU: ${TEMP}°C 🔴"
	else
		echo "CPU a ${TEMP}°C"
	fi

	exit 20
fi
