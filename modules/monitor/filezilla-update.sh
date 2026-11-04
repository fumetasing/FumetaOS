#!/bin/bash
# Consulta FileZilla en Docker Hub sin descargar imágenes ni instalar nada.
set -o pipefail

CONTENEDOR="big-bear-linuxserver-filezilla-app-1"
REPOSITORIO="linuxserver/filezilla"
ETIQUETA="latest"

aviso() {
	echo "❓ FileZilla: $1"
	exit 10
}

for programa in docker curl jq; do
	command -v "$programa" >/dev/null 2>&1 || aviso "falta $programa para comprobar actualizaciones"
done

if ! referencia_local="$(docker inspect --format '{{.Config.Image}}' "$CONTENEDOR" 2>/dev/null)"; then
	# FileZilla es opcional: no penalizar instalaciones que no lo utilizan.
	nombres="$(docker ps -a --format '{{.Names}}' 2>/dev/null)" || aviso "Docker no está disponible"
	if ! printf '%s\n' "$nombres" | grep -qx "$CONTENEDOR"; then
		echo "⚪ FileZilla: contenedor no instalado"
		exit 0
	fi
	aviso "no se pudo consultar el contenedor"
fi

case "$referencia_local" in
linuxserver/filezilla:*|linuxserver/filezilla@sha256:*|lscr.io/linuxserver/filezilla:*|lscr.io/linuxserver/filezilla@sha256:*) ;;
*) aviso "imagen distinta de LinuxServer; requiere revisión" ;;
esac

case "$referencia_local" in
*@sha256:*) digest_local="${referencia_local##*@}" ;;
*)
	digest_local="$(
		docker image inspect --format '{{range .RepoDigests}}{{println .}}{{end}}' "$referencia_local" 2>/dev/null |
			awk -F@ '$1 == "linuxserver/filezilla" || $1 == "lscr.io/linuxserver/filezilla" {print $2; exit}'
	)" || aviso "no se pudo consultar la imagen instalada"
	;;
esac
[[ "$digest_local" =~ ^sha256:[0-9a-f]{64}$ ]] || aviso "no se pudo identificar la imagen instalada"

version_local="$(docker image inspect --format '{{index .Config.Labels "build_version"}}' "$referencia_local" 2>/dev/null)" || aviso "no se pudo consultar la compilación instalada"
version_local="${version_local#Linuxserver.io version:- }"
version_local="${version_local%% Build-date:*}"
version_local="${version_local:-versión instalada}"

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

# Una referencia fijada puede identificar el manifiesto de una plataforma.
if [ "$digest_local" != "$digest_remoto" ]; then
	digests_plataforma="$(
		curl --silent --show-error --fail --connect-timeout 5 --max-time 15 \
			-H "Authorization: Bearer $token" \
			-H 'Accept: application/vnd.oci.image.index.v1+json, application/vnd.docker.distribution.manifest.list.v2+json, application/vnd.oci.image.manifest.v1+json, application/vnd.docker.distribution.manifest.v2+json' \
			"https://registry-1.docker.io/v2/${REPOSITORIO}/manifests/${digest_remoto}" 2>/dev/null |
			jq -r '.manifests[]? | select(.platform.os == "linux") | .digest'
	)" || aviso "no se pudieron consultar las variantes de la imagen remota"
	if grep -Fxq "$digest_local" <<< "$digests_plataforma"; then
		digest_remoto="$digest_local"
	fi
fi

if [ "$digest_local" = "$digest_remoto" ]; then
	echo "🟢 FileZilla al día ($version_local)"
	exit 0
fi
echo "🟡 FileZilla: actualización disponible (actual: $version_local)"
exit 10
