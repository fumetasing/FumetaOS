#!/bin/bash

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

BASE="/opt/fumetaos"
PACKAGE="$BASE/install/package"

BACKUP_DIR="/mnt/datos/backups/fumetaos"
SYSTEM_BACKUP_DIR="/var/backups/fumetaos"

UPDATE_KEEP=3

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

limpiar_backups_update() {
	mapfile -t BACKUPS < <(
		find "$BACKUP_DIR" \
			-maxdepth 1 \
			-type f \
			-name 'fumetaos-update-*.tar.gz' \
			-printf '%f\n' |
			sort -r
	)

	for OLD_FILE in "${BACKUPS[@]:$UPDATE_KEEP}"; do
		rm -f \
			"$BACKUP_DIR/$OLD_FILE" \
			"$SYSTEM_BACKUP_DIR/$OLD_FILE"

		echo "🗑️ Backup de update eliminado:"
		echo "$OLD_FILE"
	done
}

crear_backup() {
	crear_respaldo_instalacion "$BASE" "$BACKUP_DIR" fumetaos-update "$SYSTEM_BACKUP_DIR" server:server
	limpiar_backups_update
}

validar_paquete() {
	local directorio
	validar_contenido_paquete "$PACKAGE" $FUMETAOS_TIMERS

	if [[ -L "$BASE/VERSION" ]] && ! cmp -s -- "$BASE/VERSION" "$PACKAGE/VERSION"; then
		echo "❌ VERSION está enlazada al proyecto y difiere del paquete." >&2
		return 20
	fi
	for directorio in bin core modules; do
		if [[ -L "$BASE/$directorio" ]]; then
			if ! diff -qr -- "$BASE/$directorio" "$PACKAGE/$directorio"; then
				echo "❌ El directorio enlazado $directorio difiere del paquete." >&2
				return 20
			fi
		elif [[ ! -d "$BASE/$directorio" ]]; then
			echo "❌ Falta el directorio de la instalación: $directorio" >&2
			return 20
		fi
	done

}

preparar_directorios() {
	local directorio
	for directorio in bin core modules; do
		[[ ! -L "$BASE/$directorio" ]] || continue
		cp -r -- "$PACKAGE/$directorio" "$TEMPORAL/$directorio" || return 20
	done
}

sustituir_directorios() {
	local directorio
	local aplicado
	local aplicados=()

	for directorio in bin core modules; do
		[[ -d "$TEMPORAL/$directorio" ]] || continue
		if [[ -L "$BASE/$directorio" || ! -d "$BASE/$directorio" ]] ||
			! python3 -B "$TEMPORAL/package-path-exchange.py" "$TEMPORAL/$directorio" "$BASE/$directorio"; then
			echo "❌ No se pudo sustituir $directorio. Revirtiendo los directorios ya sustituidos." >&2
			for aplicado in "${aplicados[@]}"; do
				if ! python3 -B "$TEMPORAL/package-path-exchange.py" "$TEMPORAL/$aplicado" "$BASE/$aplicado"; then
					trap - EXIT
					echo "❌ Reversión incompleta. Se conserva el directorio $TEMPORAL." >&2
					return 20
				fi
			done
			return 20
		fi
		aplicados+=("$directorio")
	done
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
actualizar() {
	echo
	echo "🔄 FumetaOS Update"
	echo

	if [[ "$EUID" -ne 0 ]]; then
		echo "❌ Ejecuta el instalador con sudo." >&2
		exit 20
	fi
	exec 9<"$BASE/install"
	flock -n 9 || {
		echo "❌ Ya hay una construcción o actualización del paquete en curso." >&2
		exit 20
	}
	validar_paquete
	echo "Versión destino: $FUMETAOS_VERSION"

	TEMPORAL=$(mktemp -d "$BASE/.update.XXXXXXXX")
	trap 'rm -rf --one-file-system -- "$TEMPORAL"' EXIT
	cp -- "$SCRIPT_DIR/../core/package-path-exchange.py" "$TEMPORAL/package-path-exchange.py"
	preparar_directorios

	crear_backup
	sustituir_directorios
	configurar_journald

	if [ -d "$PACKAGE/sudoers" ]; then
		echo "🔐 Instalando permisos limitados"
		find "$PACKAGE/sudoers" -maxdepth 1 -type f -print0 |
			while IFS= read -r -d "" REGLA_SUDOERS; do
				install -m 440 "$REGLA_SUDOERS" "/etc/sudoers.d/$(basename "$REGLA_SUDOERS")"
			done
	fi

	echo "⚙️ Actualizando servicios"
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

	# Evitar una ejecución inmediata solo en la primera activación.
	if [ ! -e /var/lib/systemd/timers/stamp-fumetaos-nightly.timer ]; then
		install -d -m 755 /var/lib/systemd/timers || exit 20
		touch /var/lib/systemd/timers/stamp-fumetaos-nightly.timer || exit 20
	fi

	echo
	echo "⏱️ Actualizando timers"

	# Desde 2.4.21, Docker se limpia dentro de la cadena nocturna.
	systemctl disable --now fumetaos-docker-clean.timer 2>/dev/null || true
	rm -f /etc/systemd/system/fumetaos-docker-clean.timer
	systemctl daemon-reload

	for TIMER in $FUMETAOS_TIMERS; do
		systemctl enable "$TIMER"
		systemctl restart "$TIMER"
	done

	echo
	echo "🏷️ Actualizando versión"
	if [[ ! -L "$BASE/VERSION" ]]; then
		install -m 644 -- "$PACKAGE/VERSION" "$BASE/VERSION"
	fi

	echo
	echo "🩺 Ejecutando Doctor"
	if "$BASE/bin/fumetaos-doctor"; then
		:
	else
		ESTADO_DOCTOR=$?
		echo "❌ Doctor ha detectado problemas; revisa las comprobaciones anteriores." >&2
		echo "Los cambios aplicados no se han revertido." >&2
		exit "$ESTADO_DOCTOR"
	fi

	echo
	echo "✅ Actualización completada"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
	case "${1:-}" in
	--update)
		actualizar
		;;
	--check)
		validar_paquete
		echo "✅ Paquete e instalación compatibles para actualizar a $FUMETAOS_VERSION."
		;;
	*)
		printf 'Uso: %s --check | --update\n' "$0"
		exit 2
		;;
	esac
fi
