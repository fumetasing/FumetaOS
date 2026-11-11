#!/bin/bash

validar_contenido_paquete() {
	local paquete="$1"
	local directorio archivo regla unidad
	shift

	if [[ ! -f "$paquete/VERSION" ]]; then
		echo "❌ No existe versión en paquete" >&2
		return 20
	fi
	FUMETAOS_VERSION=$(cat -- "$paquete/VERSION") || return 20
	if [[ ! "$FUMETAOS_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
		echo "❌ La versión del paquete no es válida." >&2
		return 20
	fi

	for directorio in bin core modules apps config services; do
		if [[ ! -d "$paquete/$directorio" || -L "$paquete/$directorio" ]]; then
			echo "❌ Falta un directorio válido en el paquete: $directorio" >&2
			return 20
		fi
	done
	for archivo in bin/fumetaos bin/fumetaos-doctor core/common.sh config/systemd/journald.conf.d/90-fumetaos.conf; do
		if [[ ! -s "$paquete/$archivo" ]]; then
			echo "❌ Falta un archivo del paquete: $archivo" >&2
			return 20
		fi
	done
	if [[ ! -x "$paquete/bin/fumetaos" || ! -x "$paquete/bin/fumetaos-doctor" ]]; then
		echo "❌ Los comandos del paquete deben ser ejecutables." >&2
		return 20
	fi
	for archivo in bin/fumetaos bin/fumetaos-doctor core/common.sh; do
		bash -n "$paquete/$archivo" || return 20
	done

	for unidad in "$@"; do
		for archivo in "$unidad" "${unidad%.timer}.service"; do
			if [[ ! -s "$paquete/services/$archivo" ]]; then
				echo "❌ Falta una unidad del paquete: $archivo" >&2
				return 20
			fi
		done
	done

	if [[ -d "$paquete/sudoers" ]]; then
		while IFS= read -r -d "" regla; do
			visudo -cf "$regla" >/dev/null || return 20
		done < <(find "$paquete/sudoers" -maxdepth 1 -type f -print0)
	fi
}
