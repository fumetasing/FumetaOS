#!/bin/bash

###########################################################
# FumetaOS
# Utilidades compartidas para copias espejo en Data WD
###########################################################

mac_mirror_enviar_telegram() {
	local message="$1"

	if [ ! -x "$TELEGRAM_NOTIFY" ]; then
		echo "⚠️ No se puede enviar Telegram: falta $TELEGRAM_NOTIFY"
		return 0
	fi

	if ! printf '%s\n' "$message" | "$TELEGRAM_NOTIFY"; then
		echo "⚠️ No se pudo enviar la notificación de Telegram"
	fi
}

mac_mirror_configurar_rsync() {
    RSYNC_DELETE_OPTIONS=(-a --no-owner --no-group --dry-run --delete-delay --itemize-changes --out-format='%i' --mkpath)
    RSYNC_COPY_OPTIONS=(-a --chown=server:server --delete-delay --partial --human-readable --stats --progress --mkpath)
}

mac_mirror_usb_disponible() {
    local mount=/mnt/data-wd free
    [ "$(findmnt -n -o UUID -M "$mount")" = 87d65071-48b3-439c-8e8d-4216f3c60d5d ] || return 20
    [ ! -L "$mount/FumetaOS-Server" ] && [ -w "$mount" ] || return 20
    free=$(df -k --output=avail -- "$mount" | tail -1) || return 20
    [[ "$free" =~ ^[[:space:]]*[0-9]+$ ]] && (( free >= MINIMUM_FREE_KB ))
}

mac_mirror_contar_borrados() {
	local source_dir="$1"
	local rsync_destination="$2"

	shift 2

	rsync \
		"${RSYNC_DELETE_OPTIONS[@]}" \
		"$@" \
		"$source_dir" \
		"$rsync_destination" |
		awk '$1 == "*deleting" || $1 == "deleting" { count++ } END { print count + 0 }'
}

mac_mirror_copiar() {
	local source_dir="$1"
	local rsync_destination="$2"

	shift 2

	rsync \
		"${RSYNC_COPY_OPTIONS[@]}" \
		"$@" \
		"${DRY_RUN[@]}" \
		"$source_dir" \
		"$rsync_destination"
}
