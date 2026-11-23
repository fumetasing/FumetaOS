#!/bin/bash

###########################################################
# FumetaOS
# Monitor de servicios
###########################################################

source "$(dirname "${BASH_SOURCE[0]}")/../../core/services.sh"

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

for service in $SYSTEM_SERVICES; do
	if unit_is_active "$service"; then
		if [ "$WATCH" -eq 0 ]; then
			echo "✅ $service"
		fi

	else
		if [ "$WATCH" -eq 0 ]; then
			echo "🚨 $service"
		else
			echo "Servicio detenido: $service"
		fi

		elevar_error 20
	fi
done

exit "$ERROR"
