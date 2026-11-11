#!/bin/bash

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

###########################################################
# FumetaOS
# Installer
###########################################################

BASE="/opt/fumetaos"
PACKAGE="$BASE/install/package"
BACKUP_DIR="/mnt/datos/backups/fumetaos"

FUMETAOS_TIMERS="
fumetaos-watch.timer
fumetaos-history.timer
fumetaos-history-clean.timer
fumetaos-report.timer
fumetaos-nightly.timer
fumetaos-timecapsule-watch.timer
"

source "$SCRIPT_DIR/../core/package-validation.sh"
source "$SCRIPT_DIR/../core/installation-backup.sh"

check_system() {
	echo "🔎 Comprobando sistema..."
	echo

	if [ -f /etc/os-release ]; then
		. /etc/os-release
		echo "✅ Sistema: $PRETTY_NAME"
	else
		echo "❌ Sistema no detectado"
		exit 20
	fi

	echo "🏗️ Arquitectura: $(uname -m)"

	if command -v systemctl >/dev/null; then
		echo "✅ Systemd disponible"
	else
		echo "❌ Systemd no disponible"
		exit 20
	fi

	echo
}

crear_backup_previo() {
	[[ -f "$BASE/VERSION" ]] || return 0
	echo "⚠️ Instalación existente detectada"

	local extras=()
	if [[ -d "$BASE/apps" ]]; then
		extras+=(apps)
	fi
	crear_respaldo_instalacion "$BASE" "$BACKUP_DIR" fumetaos-preinstall "" "" "${extras[@]}"
}

validar_configuracion_instalacion() {
	local activa="$BASE/config/fumetaos.conf"
	local incluida="$PACKAGE/config/fumetaos.conf"

	if [[ -e "$activa" || -L "$activa" ]]; then
		if [[ -f "$activa" && -s "$activa" && -r "$activa" ]]; then
			return 0
		fi
		printf '❌ Revisa %s. La configuración existente debe ser un archivo legible y no vacío.\n' "$activa" >&2
		return 20
	fi
	if [[ -f "$incluida" && -s "$incluida" && -r "$incluida" ]]; then
		return 0
	fi
	printf '❌ Prepara %s o %s a partir de fumetaos.conf.example antes de instalar.\n' "$activa" "$incluida" >&2
	return 20
}

simular() {
	echo
	echo "🧪 Modo simulación"
	echo

	echo "📁 Crearía:"
	echo "$BASE/data"

	echo

	echo "📦 Copiaría:"
	echo "✅ bin"
	echo "✅ core"
	echo "✅ modules"
	echo "✅ apps"

	echo

	echo "⚙️ Instalaría servicios:"

	for SERVICE in "$PACKAGE/services/"*; do
		echo "✅ $(basename "$SERVICE")"
	done

	echo

	echo "⏱️ Activaría timers:"

	for TIMER in $FUMETAOS_TIMERS; do
		echo "✅ $TIMER"
	done

	echo

	echo "🏷️ Versión final:"
	echo "$FUMETAOS_VERSION"

	echo

	echo "✅ Simulación completada"
}

configurar_journald() {
	local JOURNALD_SOURCE="$PACKAGE/config/systemd/journald.conf.d/90-fumetaos.conf"
	local JOURNALD_DEST="/etc/systemd/journald.conf.d/90-fumetaos.conf"

	echo "🧾 Configurando retención del journal"

	[ -f "$JOURNALD_SOURCE" ] || {
		echo "❌ No existe la configuración de journald"
		exit 20
	}

	install -D -m 644 \
		"$JOURNALD_SOURCE" \
		"$JOURNALD_DEST" || exit 20

	systemctl restart systemd-journald.service || exit 20
	systemctl is-active --quiet systemd-journald.service || exit 20

	journalctl --rotate || exit 20
	journalctl --vacuum-size=1G || exit 20

	echo "✅ Journal limitado a 1 GB"
}
instalar() {
	echo
	echo "🚀 Instalando FumetaOS $FUMETAOS_VERSION"
	echo

	local ruta
	if [[ "$EUID" -ne 0 ]]; then
		echo "❌ Ejecuta el instalador con sudo." >&2
		exit 20
	fi
	for ruta in bin core modules apps config VERSION; do
		if [[ -L "$BASE/$ruta" ]]; then
			echo "❌ La ruta $ruta está enlazada. Usa el procedimiento de actualización." >&2
			exit 20
		fi
	done

	crear_backup_previo
	configurar_journald

	mkdir -p "$BASE/data"

	echo "📦 Copiando binarios"
	cp -r "$PACKAGE/bin" "$BASE/"

	echo "📦 Copiando core"
	cp -r "$PACKAGE/core" "$BASE/"

	echo "📦 Copiando módulos"
	cp -r "$PACKAGE/modules" "$BASE/"

	echo "📦 Copiando apps"
	cp -r "$PACKAGE/apps" "$BASE/"

	if [ ! -f "$BASE/config/fumetaos.conf" ]; then
		echo "📦 Copiando configuración"
		cp -r "$PACKAGE/config" "$BASE/"
	else
		echo "⏭️ Conservando configuración existente"
	fi

	if [ -d "$PACKAGE/sudoers" ]; then
		echo "🔐 Instalando permisos limitados"
		find "$PACKAGE/sudoers" -maxdepth 1 -type f -print0 |
			while IFS= read -r -d "" REGLA_SUDOERS; do
				install -m 440 "$REGLA_SUDOERS" "/etc/sudoers.d/$(basename "$REGLA_SUDOERS")"
			done
	fi

	echo "⚙️ Instalando servicios"
	find "$PACKAGE/services" -type f -print0 |
		while IFS= read -r -d "" SERVICE; do
			DESTINO="/etc/systemd/system/${SERVICE#"$PACKAGE/services/"}"
			install -D -m 644 "$SERVICE" "$DESTINO"
		done

	echo "🔄 Recargando systemd"
	systemctl daemon-reload

	# Recuperación exclusiva de Jellyfin tras montajes tardíos al arrancar.
	if [ -f "$BASE/bin/fumetaos-jellyfin-mount-guard" ] &&
		systemctl cat fumetaos-jellyfin-mount-guard.service >/dev/null 2>&1; then
		echo "🛠️ Activando recuperación de montajes de Jellyfin"
		systemctl enable fumetaos-jellyfin-mount-guard.service || exit 20
		systemctl start --no-block fumetaos-jellyfin-mount-guard.service || exit 20
	fi

	if systemctl cat fumetaos-docker-firewall.service >/dev/null 2>&1; then
		echo "🔒 Activando protección Docker"
		systemctl enable --now fumetaos-docker-firewall.service
	fi

	echo
	echo "⛓️ Desactivando horarios antiguos de copias y actualización"
	for TIMER in \
		fumetaos-backup.timer \
		fumetaos-timecapsule-mac-backup.timer \
		fumetaos-mac-backup.timer \
		fumetaos-recovery-backup.timer \
		fumetaos-recovery-verify.timer \
		fumetaos-system-upgrade.timer \
		fumetaos-smart-test.timer \
		apt-daily.timer \
		apt-daily-upgrade.timer; do
		systemctl disable --now "$TIMER" || true
	done

	# Evitar que Persistent=true lance una copia al activar el timer por primera vez.
	if [ ! -e /var/lib/systemd/timers/stamp-fumetaos-nightly.timer ]; then
		install -d -m 755 /var/lib/systemd/timers || exit 20
		touch /var/lib/systemd/timers/stamp-fumetaos-nightly.timer || exit 20
	fi

	echo
	echo "⏱️ Activando timers"

	for TIMER in $FUMETAOS_TIMERS; do
		systemctl enable "$TIMER"
		systemctl start "$TIMER"
	done

	echo
	echo "🏷️ Actualizando versión"
	echo "$FUMETAOS_VERSION" >"$BASE/VERSION"

	echo
	echo "🩺 Doctor"
	if "$BASE/bin/fumetaos-doctor"; then
		:
	else
		ESTADO_DOCTOR=$?
		echo "❌ Doctor ha detectado problemas; revisa las comprobaciones anteriores." >&2
		echo "Los cambios aplicados no se han revertido." >&2
		exit "$ESTADO_DOCTOR"
	fi

	echo
	echo "✅ FumetaOS instalado correctamente"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
	case "${1:-}" in
	--check|--dry-run|--install)
		if [[ "$1" == --install ]]; then
			exec 9<"$BASE/install"
			flock -n 9 || {
				echo "❌ Ya hay una operación sobre el paquete en curso." >&2
				exit 20
			}
		fi
		check_system
		validar_contenido_paquete "$PACKAGE" $FUMETAOS_TIMERS
		validar_configuracion_instalacion
		echo "✅ Paquete $FUMETAOS_VERSION validado."
		case "$1" in
		--dry-run) simular ;;
		--install) instalar ;;
		esac
		;;
	*)
		printf 'Uso: %s --check | --dry-run | --install\n' "$0"
		exit 2
		;;
	esac
fi
