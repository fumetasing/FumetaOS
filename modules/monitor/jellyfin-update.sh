#!/bin/bash
# Comprueba la versión publicada de Jellyfin sin descargarla ni instalarla.

set -o pipefail

CONTENEDOR="jellyfin"
REPOSITORIO="linuxserver/jellyfin"
ETIQUETA="latest"

if ! referencia_local="$(docker inspect --format '{{.Config.Image}}' "$CONTENEDOR" 2>/dev/null)"; then
	echo "❓ Jellyfin: contenedor no encontrado"
	exit 10
fi

case "$referencia_local" in
*@sha256:*)
	digest_local="${referencia_local##*@}"
	;;
*)
	digest_local="$(
		docker image inspect --format '{{index .RepoDigests 0}}' "$referencia_local" 2>/dev/null |
			sed 's#.*@##'
	)"
	;;
esac

if [[ ! "$digest_local" =~ ^sha256: ]]; then
	echo "❓ Jellyfin: no se pudo identificar la versión instalada"
	exit 10
fi

version_local="$(
	docker image inspect \
		--format '{{index .Config.Labels "org.opencontainers.image.version"}}' \
		"$referencia_local" 2>/dev/null || true
)"
version_local="${version_local:-versión instalada}"

token="$(
	curl --silent --show-error --fail \
		--connect-timeout 5 --max-time 15 \
		"https://auth.docker.io/token?service=registry.docker.io&scope=repository:${REPOSITORIO}:pull" |
		jq -r '.token // .access_token // empty'
)"

if [ -z "$token" ]; then
	echo "❓ Jellyfin: no se pudo consultar Docker Hub"
	exit 10
fi

digest_remoto="$(
	curl --silent --show-error --fail --head \
		--connect-timeout 5 --max-time 15 \
		-H "Authorization: Bearer $token" \
		-H 'Accept: application/vnd.oci.image.index.v1+json' \
		-H 'Accept: application/vnd.docker.distribution.manifest.list.v2+json' \
		"https://registry-1.docker.io/v2/${REPOSITORIO}/manifests/${ETIQUETA}" |
		awk -F': ' 'tolower($1) == "docker-content-digest" { gsub("\r", "", $2); print $2; exit }'
)"

if [[ ! "$digest_remoto" =~ ^sha256: ]]; then
	echo "❓ Jellyfin: no se pudo comprobar la versión remota"
	exit 10
fi

if [ "$digest_local" = "$digest_remoto" ]; then
	echo "🟢 Jellyfin al día ($version_local)"
	exit 0
fi

echo "🟡 Jellyfin: actualización disponible (actual: $version_local)"
exit 10
