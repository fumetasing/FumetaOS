#!/bin/bash
# Consulta AdGuard Home en Docker Hub sin descargar imágenes ni instalar nada.
set -o pipefail

CONTENEDOR="adguard-home"
REPOSITORIO="adguard/adguardhome"
ETIQUETA="latest"

aviso() {
	echo "❓ AdGuard Home: $1"
	exit 10
}

for programa in docker curl jq; do
	command -v "$programa" >/dev/null 2>&1 || aviso "falta $programa para comprobar actualizaciones"
done

if ! referencia_local="$(docker inspect --format '{{.Config.Image}}' "$CONTENEDOR" 2>/dev/null)"; then
	# AdGuard Home es opcional: no penalizar instalaciones que no lo utilizan.
	nombres="$(docker ps -a --format '{{.Names}}' 2>/dev/null)" || aviso "Docker no está disponible"
	if ! printf '%s\n' "$nombres" | grep -qx "$CONTENEDOR"; then
		echo "⚪ AdGuard Home: contenedor no instalado"
		exit 0
	fi
	aviso "no se pudo consultar el contenedor"
fi

case "$referencia_local" in
adguard/adguardhome:*|adguard/adguardhome@sha256:*|docker.io/adguard/adguardhome:*|docker.io/adguard/adguardhome@sha256:*) ;;
*) aviso "imagen distinta de AdGuard; requiere revisión" ;;
esac

imagen_id="$(docker inspect --format '{{.Image}}' "$CONTENEDOR" 2>/dev/null)" || aviso "no se pudo identificar la imagen en ejecución"
[[ "$imagen_id" =~ ^sha256:[0-9a-f]{64}$ ]] || aviso "identificador de imagen no válido"

case "$referencia_local" in
*@sha256:*) digest_local="${referencia_local##*@}" ;;
*)
	digest_local="$(
		docker image inspect --format '{{range .RepoDigests}}{{println .}}{{end}}' "$imagen_id" 2>/dev/null |
			awk -F@ '$1 == "adguard/adguardhome" || $1 == "docker.io/adguard/adguardhome" {print $2; exit}'
	)" || aviso "no se pudo consultar la imagen instalada"
	;;
esac
[[ "$digest_local" =~ ^sha256:[0-9a-f]{64}$ ]] || aviso "no se pudo identificar la imagen instalada"

version_local="$(docker image inspect --format '{{index .Config.Labels "org.opencontainers.image.version"}}' "$imagen_id" 2>/dev/null)" || aviso "no se pudo consultar la versión instalada"
case "$version_local" in ""|"<no value>") version_local="imagen instalada" ;; esac

token="$(
	curl --silent --show-error --fail --connect-timeout 5 --max-time 15 \
		--get 'https://auth.docker.io/token' \
		--data-urlencode 'service=registry.docker.io' \
		--data-urlencode "scope=repository:${REPOSITORIO}:pull" 2>/dev/null |
		jq -r '.token // .access_token // empty' 2>/dev/null
)" || aviso "no se pudo consultar Docker Hub"
[ -n "$token" ] || aviso "Docker Hub no devolvió autorización de lectura"

digest_remoto="$(
	curl --silent --show-error --fail --head --connect-timeout 5 --max-time 15 \
		-H "Authorization: Bearer $token" \
		-H 'Accept: application/vnd.oci.image.index.v1+json, application/vnd.docker.distribution.manifest.list.v2+json, application/vnd.oci.image.manifest.v1+json, application/vnd.docker.distribution.manifest.v2+json' \
		"https://registry-1.docker.io/v2/${REPOSITORIO}/manifests/${ETIQUETA}" 2>/dev/null |
		awk 'tolower($0) ~ /^docker-content-digest:/ { sub(/^[^:]*:[[:space:]]*/, ""); gsub("\r", ""); print; exit }'
)" || aviso "no se pudo consultar la imagen remota"
[[ "$digest_remoto" =~ ^sha256:[0-9a-f]{64}$ ]] || aviso "Docker Hub no publicó un digest válido"

if [ "$digest_local" = "$digest_remoto" ]; then
	echo "🟢 AdGuard Home al día ($version_local)"
	exit 0
fi
echo "🟠 AdGuard Home: actualización disponible (actual: $version_local)"
exit 10
