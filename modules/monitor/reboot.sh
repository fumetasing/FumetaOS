#!/bin/bash

###########################################################

# FumetaOS

# Monitor de reinicio pendiente

###########################################################

REBOOT_FILE="/var/run/reboot-required"
PACKAGES_FILE="/var/run/reboot-required.pkgs"

if [ ! -f "$REBOOT_FILE" ]; then
	exit 0
fi

echo "🟡 Reinicio pendiente"
echo "   Ubuntu requiere reiniciar el servidor"

if [ -s "$PACKAGES_FILE" ]; then
	PACKAGES=$(tr '\n' ', ' <"$PACKAGES_FILE" | sed 's/, $//')

	if [ -n "$PACKAGES" ]; then
		echo "   Paquetes: $PACKAGES"
	fi
fi

exit 10
