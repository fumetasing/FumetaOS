#!/bin/bash

############################################################

# FumetaOS

# Apps Core v2

############################################################

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

app_list() {

	for APP in "$APPS_DIR"/*; do

		[ -d "$APP" ] || continue
		[ -f "$APP/app.conf" ] || continue

		echo "$APP"

	done

}

app_find() {

	SEARCH_ID="$1"

	for APP in $(app_list); do

		source "$APP/app.conf"

		if [ "$APP_ID" = "$SEARCH_ID" ]; then

			echo "$APP"
			return 0

		fi

	done

	return 1

}

app_load() {

	APP_PATH="$1"

	[ -f "$APP_PATH/app.conf" ] || return 1

	unset APP_ID
	unset APP_NAME
	unset APP_DESCRIPTION
	unset APP_CATEGORY
	unset APP_ICON
	unset APP_ICON_URL

	unset APP_TYPE
	unset APP_IMAGE
	unset APP_TAG
	unset APP_CONTAINER

	unset APP_INDEX
	unset APP_PORT
	unset APP_PORT_MAP
	unset APP_PORTS
	unset APP_URL
	unset APP_WEBUI

	unset APP_HEALTH

	unset APP_COMPOSE
	unset APP_DATA
	unset APP_ENV
	unset APP_VOLUMES

	unset APP_VERSION
	unset APP_AUTHOR

	source "$APP_PATH/app.conf"

}

app_container() {

	if [ -n "$APP_CONTAINER" ]; then

		echo "$APP_CONTAINER"

	else

		echo "$APP_ID"

	fi

}

app_description() {

	echo "$APP_DESCRIPTION"

}

app_category() {

	echo "$APP_CATEGORY"

}

app_icon() {

	echo "$APP_ICON"

}

app_url() {

	echo "$APP_URL"

}

app_webui() {

	echo "$APP_WEBUI"

}

app_report_url() {

	if [ -n "$APP_URL" ]; then

		echo "$APP_URL"

	elif [ -n "$APP_WEBUI" ]; then

		echo "${APP_WEBUI//\[IP\]/localhost}"

	fi

}

app_author() {

	echo "$APP_AUTHOR"

}

app_running() {

	CONTAINER=$(app_container)

	docker ps --format '{{.Names}}' | grep -qx "$CONTAINER"

}

############################################################
# Health de aplicaciones
############################################################

app_health() {

	CONTAINER=$(app_container)

	############################################################
	# Health nativo Docker
	############################################################

	DOCKER_HEALTH=$(docker inspect "$CONTAINER" --format '{{.State.Health.Status}}' 2>/dev/null)

	if [ "$DOCKER_HEALTH" = "healthy" ] || [ "$DOCKER_HEALTH" = "unhealthy" ]; then

		echo "$DOCKER_HEALTH"
		return

	fi

	############################################################
	# Health personalizado Transmission
	############################################################

	if [ "$APP_HEALTH" = "transmission" ]; then

		RESPONSE=$(curl --connect-timeout 5 --max-time 10 -si \
			http://localhost:9091/transmission/rpc/ 2>/dev/null)

		STATUS=$(echo "$RESPONSE" | head -1)

		if echo "$STATUS" | grep -Eq "200|401|409"; then

			echo "healthy"

		else

			echo "unhealthy"

		fi

		return

	fi

	############################################################
	# Health HTTP genérico
	############################################################

	if [ -n "$APP_HEALTH" ]; then

		if curl --connect-timeout 5 --max-time 10 -fs "$APP_HEALTH" >/dev/null 2>&1; then

			echo "healthy"

		else

			echo "unhealthy"

		fi

		return

	fi

	echo "none"

}

app_version() {

	echo "$APP_VERSION"

}

app_install() {

	APP_PATH="$1"

	app_load "$APP_PATH" || return 1

	if app_running; then

		echo
		echo "⚠️ $APP_NAME ya está ejecutándose"
		return 1

	fi

	echo
	echo "📦 Instalando $APP_NAME"
	echo

	if [ -z "$APP_COMPOSE" ]; then

		echo "❌ No existe archivo compose para $APP_NAME"
		return 1

	fi

	if [ ! -f "$APP_COMPOSE" ]; then

		echo "❌ No existe compose: $APP_COMPOSE"
		return 1

	fi

	mkdir -p "$APP_DATA"

	cd "$APP_DATA" || return 1

	if docker compose -f "$APP_COMPOSE" up -d; then

		echo
		echo "✅ $APP_NAME instalado"

	else

		echo
		echo "❌ Error instalando $APP_NAME"
		return 1

	fi

}
