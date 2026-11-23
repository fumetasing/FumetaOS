#!/bin/bash

###########################################################
# FumetaOS
# Monitor de máquinas virtuales
###########################################################

export LC_ALL=C

ERROR=0
TOTAL=0
RUNNING=0
STOPPED=0
PROBLEMS=0

if ! command -v virsh >/dev/null 2>&1; then
	echo "🔴 Libvirt no está disponible"
	exit 20
fi

VMS_OUTPUT=$(virsh -c qemu:///system list --all --name 2>/dev/null)
RET=$?

if [ "$RET" -ne 0 ]; then
	echo "🔴 No se pudo consultar Libvirt"
	exit 20
fi

mapfile -t VMS <<<"$VMS_OUTPUT"

for VM in "${VMS[@]}"; do
	[ -n "$VM" ] || continue

	TOTAL=$((TOTAL + 1))

	STATE=$(virsh -c qemu:///system domstate "$VM" 2>/dev/null)

	case "$STATE" in
	running)
		RUNNING=$((RUNNING + 1))

		IP=$(
			virsh -c qemu:///system domifaddr \
				"$VM" \
				--source agent \
				2>/dev/null |
				awk '$3 == "ipv4" && $4 !~ /^127\./ {
                        sub(/\/.*/, "", $4)
                        print $4
                        exit
                    }'
		)

		echo "🟢 $VM"
		echo "   Estado: ejecutándose"

		if [ -n "$IP" ]; then
			echo "   IP: $IP"
		else
			echo "   IP: no disponible todavía"
		fi
		;;
	"shut off")
		STOPPED=$((STOPPED + 1))

		echo "🟢 $VM"
		echo "   Estado: apagada"
		;;
	paused | pmsuspended)
		PROBLEMS=$((PROBLEMS + 1))
		if [ "$ERROR" -lt 10 ]; then
			ERROR=10
		fi

		echo "🔴 $VM"
		echo "   Estado: $STATE"
		;;
	*)
		PROBLEMS=$((PROBLEMS + 1))
		ERROR=20

		echo "🔴 $VM"
		echo "   Estado: $STATE"
		;;
	esac
done

if [ "$TOTAL" -eq 0 ]; then
	echo "ℹ️ No hay máquinas virtuales configuradas"
else
	echo
	echo "Total: $TOTAL"
	echo "Ejecutándose: $RUNNING"
	echo "Apagadas: $STOPPED"
	echo "Problemas: $PROBLEMS"
fi

exit "$ERROR"
