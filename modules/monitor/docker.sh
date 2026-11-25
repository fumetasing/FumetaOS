#!/bin/bash

# Informa del espacio Docker usado y recuperable.
# No elimina imágenes, contenedores ni caché.

source /opt/fumetaos/core/common.sh

WATCH=0
AVISO_BYTES=$((5 * 1000 * 1000 * 1000))
CRITICO_BYTES=$((10 * 1000 * 1000 * 1000))

if [ "${1:-}" = "--watch" ]; then
	WATCH=1
fi

if ! datos="$(docker system df --format '{{.Type}}|{{.Size}}|{{.Reclaimable}}' 2>/dev/null)"; then
	echo "❓ No se pudo consultar el espacio de Docker"
	exit 20
fi

if [ -z "$datos" ]; then
	echo "❓ Docker no devolvió información de espacio"
	exit 20
fi

read -r usados recuperables < <(
	printf '%s\n' "$datos" |
		awk -F'|' '
                function en_bytes(text, numero, unidad, factor) {
                        sub(/ .*/, "", text)
                        numero = text
                        sub(/[[:alpha:]]+$/, "", numero)
                        unidad = text
                        sub(/^[0-9.]+/, "", unidad)
                        unidad = toupper(unidad)

                        factor = 1
                        if (unidad == "KB") factor = 1000
                        if (unidad == "MB") factor = 1000 * 1000
                        if (unidad == "GB") factor = 1000 * 1000 * 1000
                        if (unidad == "TB") factor = 1000 * 1000 * 1000 * 1000

                        return numero * factor
                }

                {
                        usados += en_bytes($2)
                        recuperables += en_bytes($3)
                }

                END {
                        printf "%.0f %.0f\n", usados, recuperables
                }'
)

formatear_bytes() {
	numfmt --to=si --suffix=B "$1"
}

ERROR=0
ICONO="🟢"

if [ "$recuperables" -ge "$CRITICO_BYTES" ]; then
	ERROR=20
	ICONO="🔴"
elif [ "$recuperables" -ge "$AVISO_BYTES" ]; then
	ERROR=10
	ICONO="🟡"
fi

if [ "$WATCH" -eq 1 ]; then
	if [ "$ERROR" -gt 0 ]; then
		echo "Docker tiene $(formatear_bytes "$recuperables") recuperables"
	fi
	exit "$ERROR"
fi

echo "🟢 Ocupado: $(formatear_bytes "$usados")"
echo "$ICONO Recuperable: $(formatear_bytes "$recuperables")"

while IFS='|' read -r tipo tamano libre; do
	case "$tipo" in
	Images) etiqueta="Imágenes" ;;
	Containers) etiqueta="Contenedores" ;;
	"Local Volumes") etiqueta="Volúmenes" ;;
	"Build Cache") etiqueta="Caché de compilación" ;;
	*) etiqueta="$tipo" ;;
	esac

	echo "   $etiqueta: $tamano ($libre recuperables)"
done <<<"$datos"

exit "$ERROR"
