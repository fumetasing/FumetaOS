#!/bin/sh

###########################################################
# FumetaOS / Transmission
# Extracción automática de archivos RAR
###########################################################

TORRENT_ID="${TR_TORRENT_ID}"
TORRENT_DIR="${TR_TORRENT_DIR}"
TORRENT_NAME="${TR_TORRENT_NAME}"

if [ -z "$TORRENT_ID" ]; then
	exit 1
fi

if [ -z "$TORRENT_DIR" ]; then
	exit 1
fi

###########################################################
# Determinar directorio real de la descarga
###########################################################

DOWNLOAD_PATH="$TORRENT_DIR"

if [ -n "$TORRENT_NAME" ] && [ -d "$TORRENT_DIR/$TORRENT_NAME" ]; then
	DOWNLOAD_PATH="$TORRENT_DIR/$TORRENT_NAME"
fi

###########################################################
# Buscar archivos RAR
###########################################################

RAR_FILE=""

# Multipartes: empezar por part01
RAR_FILE=$(find "$DOWNLOAD_PATH" -type f -iname "*.part01.rar" -print -quit)

# RAR único o nomenclatura alternativa
if [ -z "$RAR_FILE" ]; then
	RAR_FILE=$(find "$DOWNLOAD_PATH" -type f -iname "*.rar" -print -quit)
fi

###########################################################
# Extraer RAR
###########################################################

if [ -n "$RAR_FILE" ]; then

	echo "📦 RAR detectado:"
	echo "$RAR_FILE"

	echo "📂 Extrayendo..."

	if /usr/bin/7z x "$RAR_FILE" -o"$DOWNLOAD_PATH" -aoa; then

		echo "✅ Extracción completada"

	else

		echo "❌ Error durante la extracción"

		# Mantener el torrent si la extracción falla
		exit 20

	fi

else

	echo "ℹ️ No se encontraron archivos RAR"

fi

###########################################################
# Eliminar torrent de Transmission
###########################################################

/usr/bin/transmission-remote \
	--auth "${USER}:${PASS}" \
	--torrent "$TORRENT_ID" \
	--remove || exit 20

exit 0
