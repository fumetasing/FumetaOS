#!/bin/bash

###########################################################
# FumetaOS
# Watch Core
###########################################################

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/system.sh"
source "$(dirname "${BASH_SOURCE[0]}")/apps.sh"
source "$(dirname "${BASH_SOURCE[0]}")/events.sh"

WATCH_STATE="$FUMETAOS_HOME/data/watch-state"

mkdir -p "$WATCH_STATE"

###########################################################
# Estado
###########################################################

state_get() {

	FILE="$WATCH_STATE/$1"

	if [ -f "$FILE" ]; then
		cat "$FILE"
	fi

}

state_set() {

	echo "$2" >"$WATCH_STATE/$1"

}

###########################################################
# Servicios
###########################################################

# FumetaOS: SSH socket-aware health check v1
_fumetaos_watch_unit_is_active() {
	case "$1" in
	ssh | ssh.service | sshd | sshd.service)
		local estado
		estado="$(systemctl show ssh.service -p ActiveState --value 2>/dev/null)" || return 1
		case "$estado" in
		active) return 0 ;;
		inactive) systemctl is-active --quiet ssh.socket ;;
		*) return 1 ;;
		esac
		;;
	*) systemctl is-active --quiet "$1" ;;
	esac
}

check_services() {

	for SERVICE in $SYSTEM_SERVICES; do

		if _fumetaos_watch_unit_is_active "$SERVICE"; then
			CURRENT="ok"
		else
			CURRENT="failed"
		fi

		OLD=$(state_get "service-$SERVICE")

		#######################################################
		# Servicio caído
		#######################################################

		if [ "$CURRENT" = "failed" ]; then

			if [ "$OLD" = "warning" ]; then

				event_error \
					"Servicio detenido" \
					"$SERVICE no está activo"

				state_set "service-$SERVICE" "failed"

			elif [ "$OLD" = "ok" ] || [ -z "$OLD" ]; then

				state_set "service-$SERVICE" "warning"

			fi

		#######################################################
		# Servicio recuperado
		#######################################################

		elif [ "$CURRENT" = "ok" ]; then

			if [ "$OLD" = "failed" ]; then

				event_recovery \
					"Servicio recuperado" \
					"$SERVICE vuelve a estar activo"

			fi

			state_set "service-$SERVICE" "ok"

		fi

	done

}

###########################################################
# Ejecutar Watch
###########################################################

watch_run() {

	check_services

}
