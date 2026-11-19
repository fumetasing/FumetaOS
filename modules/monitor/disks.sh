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
	local free
	local use

	read -r free use < <(
		df -P -h "$mount" |
			awk 'NR == 2 {
                gsub("%", "", $5)
                print $4, $5
            }'
	)

	if [ "$use" -lt "$DISK_WARNING" ]; then
		if [ "$WATCH" -eq 0 ]; then
			echo "🟢 $name"
			echo "   Libre: $free"
			echo "   Uso:   ${use}%"
			echo
		fi
	elif [ "$use" -lt "$DISK_CRITICAL" ]; then
		if [ "$WATCH" -eq 0 ]; then
			echo "🟡 $name"
			echo "   Libre: $free"
			echo "   Uso:   ${use}%"
			echo
		else
			echo "$name al ${use}%"
		fi

		ERROR=10
	else
		if [ "$WATCH" -eq 0 ]; then
			echo "🔴 $name"
			echo "   Libre: $free"
			echo "   Uso:   ${use}%"
			echo
		else
			echo "$name al ${use}%"
		fi

		ERROR=20
	fi
}

check_disk "$SSD_NAME" "/"
check_disk "$HDD_NAME" "/mnt/datos"

mostrar_volumen_wd() {
    local nombre="$1"
    local ruta="$2"
    local uuid="$3"

    if [ "$(findmnt -n -o UUID -M "$ruta")" = "$uuid" ]; then
        echo "🟢 $nombre"
        df -h --output=avail,pcent -- "$ruta" | awk 'NR==2 {print "   Libre: " $1; print "   Uso: " $2}'
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
