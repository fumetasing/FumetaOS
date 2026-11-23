#!/bin/bash

###########################################################
# FumetaOS
# Services Core
###########################################################

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

# FumetaOS: SSH socket-aware health check v1
unit_is_active() {
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

###########################################################
# Estado servicio
###########################################################

service_state() {
	if unit_is_active "$1"; then
		echo "active"
	else
		echo "inactive"
	fi
}

###########################################################
# Estado timer
###########################################################

timer_state() {
	if unit_is_active "$1"; then
		echo "active"
	else
		echo "inactive"
	fi
}

###########################################################
# Mostrar servicios
###########################################################

services_show() {
	local timer
	local service

	echo
	echo "⚙️ Servicios FumetaOS"
	echo

	echo "⏱️ Timers"
	echo "─────────"

	for timer in $FUMETAOS_TIMERS; do
		if unit_is_active "$timer"; then
			echo "🟢 $timer"
		else
			echo "🔴 $timer"
		fi
	done

	echo

	echo "🛠️ Sistema"
	echo "──────────"

	for service in $SYSTEM_SERVICES; do
		if unit_is_active "$service"; then
			echo "🟢 $service"
		else
			echo "🔴 $service"
		fi
	done

	echo
}
