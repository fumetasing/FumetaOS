#!/bin/bash

###########################################################
# FumetaOS
# Monitor de temporizadores
###########################################################

source "$(dirname "${BASH_SOURCE[0]}")/../../core/services.sh"

ERROR=0

echo

declare -A descripciones=(
	[fumetaos-watch.timer]="Vigilancia del sistema"
	[fumetaos-report.timer]="Informes de estado"
	[fumetaos-history.timer]="Registro del historial"
	[fumetaos-history-clean.timer]="Limpieza del historial"
	[fumetaos-nightly.timer]="Cadena nocturna de copias y mantenimiento"
	[fumetaos-timecapsule-watch.timer]="Vigilancia de Time Capsule"
)

for timer in $FUMETAOS_TIMERS; do
	descripcion="${descripciones[$timer]:-$timer}"
	if unit_is_active "$timer"; then
		echo "✅ $descripcion"
	else
		echo "🚨 $descripcion ($timer)"
		ERROR=20
	fi
done

exit "$ERROR"
