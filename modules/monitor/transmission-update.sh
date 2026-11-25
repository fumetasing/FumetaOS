#!/bin/bash

set -o pipefail

CONTENEDOR="transmission"
REPOSITORIO="linuxserver/transmission"
ETIQUETA="latest"
AUTH_HOST="auth.docker.io"
REGISTRY_HOST="registry-1.docker.io"

if ! referencia_local="$(docker inspect --format '{{.Config.Image}}' "$CONTENEDOR" 2>/dev/null)"; then
	echo "❓ Transmission: contenedor no encontrado"
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
	echo "❓ Transmission: no se pudo identificar la versión instalada"
	exit 10
fi

version_local="$(
	docker image inspect \
		--format '{{index .Config.Labels "build_version"}}' \
		"$referencia_local" 2>/dev/null || true
)"
version_local="${version_local:-versión instalada}"

AUTH_URL="https://${AUTH_HOST}/token"
token="$(
	curl --silent --show-error --fail \
		--connect-timeout 5 --max-time 15 \
		--get "$AUTH_URL" \
		--data-urlencode "service=registry.docker.io" \
		--data-urlencode "scope=repository:${REPOSITORIO}:pull" |
		jq -r '.token // .access_token // empty'
)"

if [ -z "$token" ]; then
	echo "❓ Transmission: no se pudo consultar Docker Hub"
	exit 10
fi

MANIFEST_URL="https://${REGISTRY_HOST}/v2/${REPOSITORIO}/manifests/${ETIQUETA}"
digest_remoto="$(
	curl --silent --show-error --fail --head \
		--connect-timeout 5 --max-time 15 \
		-H "Authorization: Bearer $token" \
		-H 'Accept: application/vnd.oci.image.index.v1+json' \
		-H 'Accept: application/vnd.docker.distribution.manifest.list.v2+json' \
		"$MANIFEST_URL" |
		awk -F': ' 'tolower($1) == "docker-content-digest" { gsub("\r", "", $2); print $2; exit }'
)"

if [[ ! "$digest_remoto" =~ ^sha256: ]]; then
	echo "❓ Transmission: no se pudo comprobar la versión remota"
	exit 10
fi

if [ "$digest_local" = "$digest_remoto" ]; then
	echo "🟢 Transmission al día ($version_local)"
	exit 0
fi

echo "🟡 Transmission: actualización disponible (actual: $version_local)"
exit 10
