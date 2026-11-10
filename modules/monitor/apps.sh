#!/bin/bash

###########################################################
# FumetaOS
# Monitor de aplicaciones CasaOS
###########################################################

ERROR=0
TOTAL=0
ACTIVE=0
FAILED=0

declare -a PROJECTS=()

declare -A PROJECT_SEEN
declare -A PROJECT_CONTAINERS
declare -A PROJECT_CONTAINER_COUNT
declare -A PROJECT_RUNNING_COUNT
declare -A PROJECT_HEALTH

declare -A CONTAINER_IMAGE
declare -A CONTAINER_HEALTH
declare -A CONTAINER_PORTS

app_name() {
	case "$1" in
	big-bear-immich)
		echo "Immich"
		;;
	big-bear-syncthing)
		echo "Syncthing"
		;;
	jellyfin)
		echo "Jellyfin"
		;;
	transmission)
		echo "Transmission"
		;;
	*)
		echo "${1#big-bear-}" |
			tr '-' ' ' |
			awk '{
                    for (i = 1; i <= NF; i++) {
                        $i = toupper(substr($i, 1, 1)) substr($i, 2)
                    }

                    print
                }'
		;;
	esac
}

app_description() {
	case "$1" in
	big-bear-immich)
		echo "Almacenamiento de fotos y vídeos"
		;;
	big-bear-syncthing)
		echo "Sincronización de archivos entre dispositivos"
		;;
	jellyfin)
		echo "Servidor multimedia Jellyfin"
		;;
	transmission)
		echo "Cliente BitTorrent para descargas automáticas"
		;;
	esac
}

main_container() {
	local project="$1"
	local container
	local first_container=""

	case "$project" in
	big-bear-immich)
		echo "immich-server"
		return
		;;
	big-bear-syncthing)
		echo "big-bear-syncthing"
		return
		;;
	jellyfin)
		echo "jellyfin"
		return
		;;
	transmission)
		echo "transmission"
		return
		;;
	esac

	while IFS= read -r container; do
		[ -n "$container" ] || continue

		if [ -z "$first_container" ]; then
			first_container="$container"
		fi

		if [ -n "${CONTAINER_PORTS[$container]-}" ]; then
			echo "$container"
			return
		fi
	done <<<"${PROJECT_CONTAINERS[$project]-}"

	echo "$first_container"
}

app_port() {
	local project="$1"
	local container
	local ports

	case "$project" in
	adguard-home)
		echo "3001"
		return
		;;
	big-bear-immich)
		echo "2283"
		return
		;;
	big-bear-syncthing)
		echo "8384"
		return
		;;
	jellyfin)
		echo "8097"
		return
		;;
	transmission)
		echo "9091"
		return
		;;
	esac

	container="$(main_container "$project")"
	ports="${CONTAINER_PORTS[$container]-}"

	awk '
        match($0, /:[0-9]+->/) {
            print substr($0, RSTART + 1, RLENGTH - 3)
            exit
        }
    ' <<<"$ports"
}

app_version() {
	local project="$1"
	local container
	local image
	local version

	container="$(main_container "$project")"
	image="${CONTAINER_IMAGE[$container]-}"

	version="$(
		docker image inspect \
			--format '{{index .Config.Labels "org.opencontainers.image.version"}}' \
			"$image" 2>/dev/null || true
	)"

	case "$version" in
	"" | "<no value>")
		;;
	*)
		echo "$version"
		return
		;;
	esac

	image="${image%@*}"
	image="${image##*/}"

	case "$image" in
	*:*)
		echo "${image##*:}"
		;;
	*)
		echo "Desconocida"
		;;
	esac
}
app_health() {
	local project="$1"
	local container
	local health
	local has_healthcheck=0
	local is_starting=0
	local response
	local status

	case "$project" in
	transmission)
		response="$(
			curl -si \
				http://localhost:9091/transmission/rpc/ \
				2>/dev/null
		)"

		status="$(head -n 1 <<<"$response")"

		if grep -Eq "200|401|409" <<<"$status"; then
			echo "healthy"
		else
			echo "unhealthy"
		fi

		return
		;;
	jellyfin)
		if curl -fs \
			http://localhost:8097/health \
			>/dev/null 2>&1 ||
			curl -fs \
				http://localhost:8097/ \
				>/dev/null 2>&1; then
			echo "healthy"
		else
			echo "unhealthy"
		fi

		return
		;;
	esac

	while IFS= read -r container; do
		[ -n "$container" ] || continue

		health="${CONTAINER_HEALTH[$container]-none}"

		if [ "$health" = "unhealthy" ]; then
			echo "unhealthy"
			return
		fi

		if [ "$health" = "healthy" ]; then
			has_healthcheck=1
		fi

		if [ "$health" = "starting" ]; then
			is_starting=1
		fi
	done <<<"${PROJECT_CONTAINERS[$project]-}"

	if [ "$is_starting" -eq 1 ]; then
		echo "starting"
	elif [ "$has_healthcheck" -eq 1 ]; then
		echo "healthy"
	else
		echo "none"
	fi
}

load_container_cache() {
	local project
	local container
	local state
	local image
	local health
	local ports

	while IFS='|' read -r project container state image health ports; do
		[ -n "$project" ] || continue
		[ -n "$container" ] || continue

		if [ -z "${PROJECT_SEEN[$project]+x}" ]; then
			PROJECTS+=("$project")
			PROJECT_SEEN["$project"]=1
		fi

		PROJECT_CONTAINERS["$project"]+="$container"$'\n'

		PROJECT_CONTAINER_COUNT["$project"]=$((${PROJECT_CONTAINER_COUNT[$project]:-0} + 1))

		if [ "$state" = "running" ]; then
			PROJECT_RUNNING_COUNT["$project"]=$((${PROJECT_RUNNING_COUNT[$project]:-0} + 1))
		fi

		CONTAINER_IMAGE["$container"]="$image"
		CONTAINER_HEALTH["$container"]="${health:-none}"
		CONTAINER_PORTS["$container"]="$ports"
	done < <(
		docker ps -a \
			--format \
			'{{.Label "com.docker.compose.project"}}|{{.Names}}|{{.State}}|{{.Image}}|{{.HealthStatus}}|{{.Ports}}'
	)

	if [ "${#PROJECTS[@]}" -gt 0 ]; then
		mapfile -t PROJECTS < <(
			printf '%s\n' "${PROJECTS[@]}" |
				sort
		)
	fi
}

if ! docker info >/dev/null 2>&1; then
	echo "🔴 Docker no está disponible para el usuario actual"
	exit 20
fi

load_container_cache

for PROJECT in "${PROJECTS[@]}"; do
	CONTAINERS="${PROJECT_CONTAINER_COUNT[$PROJECT]:-0}"
	RUNNING="${PROJECT_RUNNING_COUNT[$PROJECT]:-0}"
	HEALTH="$(app_health "$PROJECT")"

	PROJECT_HEALTH["$PROJECT"]="$HEALTH"

	TOTAL=$((TOTAL + 1))

	if [ "$CONTAINERS" -gt 0 ] &&
		[ "$RUNNING" -eq "$CONTAINERS" ] &&
		[ "$HEALTH" != "unhealthy" ] &&
		[ "$HEALTH" != "starting" ]; then
		ACTIVE=$((ACTIVE + 1))
	else
		FAILED=$((FAILED + 1))
	fi
done

echo
echo "Total: $TOTAL"
echo "Activas: $ACTIVE"
echo "Problemas: $FAILED"
echo

for PROJECT in "${PROJECTS[@]}"; do
	NAME="$(app_name "$PROJECT")"
	DESCRIPTION="$(app_description "$PROJECT")"
	CONTAINERS="${PROJECT_CONTAINER_COUNT[$PROJECT]:-0}"
	RUNNING="${PROJECT_RUNNING_COUNT[$PROJECT]:-0}"
	VERSION="$(app_version "$PROJECT")"
	PORT="$(app_port "$PROJECT")"
	HEALTH="${PROJECT_HEALTH[$PROJECT]:-none}"

	if [ "$CONTAINERS" -gt 0 ] &&
		[ "$RUNNING" -eq "$CONTAINERS" ]; then
		if [ "$HEALTH" = "starting" ]; then
			echo "🟡 $NAME"
		else
			echo "🟢 $NAME"
		fi

		if [ -n "$DESCRIPTION" ]; then
			echo "   $DESCRIPTION"
		fi

		echo "   Estado: 🟢 Ejecutando"
		echo "   Versión: $VERSION"

		if [ -n "$PORT" ]; then
			echo "   URL: http://localhost:$PORT"
			echo "   Puerto: $PORT"
		fi

		case "$HEALTH" in
		starting)
			echo "   Health: 🟡 Arrancando; comprobación en curso"
			;;
		healthy)
			echo "   Health: 🟢 healthy"
			;;
		unhealthy)
			echo "   Health: 🔴 unhealthy"
			ERROR=20
			;;
		*)
			echo "   Health: 🟡 Sin healthcheck"
			;;
		esac
	else
		echo "🔴 $NAME"

		if [ -n "$DESCRIPTION" ]; then
			echo "   $DESCRIPTION"
		fi

		echo "   Estado: 🔴 Detenido"
		ERROR=20
	fi

	echo
done

if [ "$FAILED" -gt 0 ]; then
	ERROR=20
fi

exit "$ERROR"
