#!/bin/bash

###########################################################
# FumetaOS
# Monitor de discos
###########################################################

source /opt/fumetaos/core/common.sh

WATCH=0

if [ "${1:-}" = "--watch" ]; then
	WATCH=1
fi

ERROR=0

check_disk() {
	local name="$1"
	local mount="$2"
	local free use color

	if ! read -r free use < <(
		df -P -h -- "$mount" | awk 'NR == 2 { sub(/%$/, "", $5); print $4, $5 }'
	) || [[ ! "$use" =~ ^[0-9]+$ ]]; then
		echo "🔴 $name: no se pudo leer el uso"
		ERROR=20
		return
	fi

	if [ "$use" -ge "$DISK_CRITICAL" ]; then
		color=🔴
		ERROR=20
	elif [ "$use" -ge "$DISK_WARNING" ]; then
		color=🟡
		if [ "$ERROR" -eq 0 ]; then
			ERROR=10
		fi
	else
		color=🟢
	fi

	if [ "$WATCH" -eq 0 ]; then
		echo "$color $name"
		echo "   Libre: $free"
		echo "   Uso:   ${use}%"
	elif [ "$color" != 🟢 ]; then
		echo "$name al ${use}%"
	fi
}

check_disk "$SSD_NAME" "/"
if [ "$WATCH" -eq 0 ]; then echo; fi
check_disk "$HDD_NAME" "/mnt/datos"
if [ "$WATCH" -eq 0 ]; then echo; fi

mostrar_volumen_wd() {
	local nombre="$1"
	local ruta="$2"
	local uuid="$3"

	if [ "$(findmnt -n -o UUID -M "$ruta")" = "$uuid" ]; then
		check_disk "$nombre" "$ruta"
	else
		echo "🔴 $nombre no está montado en Ubuntu"
		ERROR=20
	fi
}

if [ "$WATCH" -eq 0 ]; then
	mostrar_volumen_wd "Data WD" /mnt/data-wd 87d65071-48b3-439c-8e8d-4216f3c60d5d
	mostrar_volumen_wd "Time Machine WD" /mnt/time-machine-wd 707e3c0f-2728-4381-97f2-800bf12c668d
fi

exit "$ERROR"
