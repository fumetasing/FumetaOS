#!/bin/bash
# Solo consulta la última release estable oficial; no instala ni reemplaza CasaOS.
set -o pipefail

aviso() {
	echo "❓ CasaOS: $1"
	exit 10
}

if ! CASAOS_BIN="$(command -v casaos)"; then
	echo "⚪ CasaOS: no instalado"
	exit 0
fi

for programa in curl jq dpkg timeout; do
	command -v "$programa" >/dev/null 2>&1 || aviso "falta $programa para comprobar actualizaciones"
done

version_local="$(timeout 5 "$CASAOS_BIN" -v 2>/dev/null)" || aviso "no se pudo consultar la versión instalada"
[[ "$version_local" =~ ^v?[0-9]+\.[0-9]+\.[0-9]+$ ]] || aviso "versión instalada no reconocida"
version_local="${version_local#v}"

release="$(curl --silent --show-error --fail --connect-timeout 5 --max-time 15 \
	-H 'Accept: application/vnd.github+json' \
	-H 'X-GitHub-Api-Version: 2022-11-28' \
	'https://api.github.com/repos/IceWhaleTech/CasaOS/releases/latest' 2>/dev/null)" || aviso "no se pudo consultar la release oficial de GitHub"

version_remota="$(printf '%s' "$release" | jq -er \
	'select(.draft == false and .prerelease == false) | .tag_name | select(type == "string")' 2>/dev/null)" || aviso "GitHub no devolvió una release estable válida"
[[ "$version_remota" =~ ^v?[0-9]+\.[0-9]+\.[0-9]+$ ]] || aviso "versión oficial no reconocida"
version_remota="${version_remota#v}"

if dpkg --compare-versions "$version_remota" gt "$version_local"; then
	echo "🟡 CasaOS: nueva versión oficial v$version_remota (actual: v$version_local; revisar el parche antes de actualizar)"
	exit 10
fi
if dpkg --compare-versions "$version_remota" eq "$version_local"; then
	echo "🟢 CasaOS: sin nueva versión oficial (actual: v$version_local)"
	exit 0
fi
echo "ℹ️ CasaOS: instalada v$version_local; última oficial v$version_remota. Revisar procedencia; no se propone bajar de versión."
exit 10
