#!/bin/bash

# Crea un archivo local y, si se indica, una segunda copia idéntica.
crear_respaldo_instalacion() (
	umask 077
	local base="$1" datos="$2" prefijo="$3" sistema="$4" propietario="$5"
	shift 5
	local temporal copia_datos="" copia_sistema="" fecha nombre contenido archivo destino
	local entradas=(bin core modules config VERSION "$@")
	local origenes=() esperados=(bin/fumetaos core/common.sh modules/ config/ VERSION)
	for archivo in "${entradas[@]}"; do
		origenes+=("$base/$archivo")
	done
	for archivo in "$@"; do
		esperados+=("$archivo/")
	done

	mkdir -p -- "$datos"
	if [[ -n "$sistema" ]]; then
		mkdir -p -- "$sistema"
	fi
	temporal=$(mktemp -d)
	trap 'rm -rf -- "$temporal"; rm -f -- "$copia_datos" "$copia_sistema"' EXIT

	echo "💾 Creando backup previo..."
	# Seguir los enlaces de entrada y conservar los que haya dentro.
	cp -aH -- "${origenes[@]}" "$temporal/"
	fecha=$(date +%Y-%m-%d_%H-%M-%S)
	copia_datos=$(mktemp "$datos/.$prefijo-$fecha.XXXXXXXX")
	nombre="${copia_datos##*/}"
	nombre="${nombre#.}.tar.gz"

	tar -czf "$copia_datos" -C "$temporal" "${entradas[@]}"
	gzip -t "$copia_datos"
	contenido=$(tar -tzf "$copia_datos")
	for archivo in "${esperados[@]}"; do
		if ! grep -Fxq -- "$archivo" <<< "$contenido"; then
			echo "❌ El respaldo no contiene $archivo." >&2
			exit 20
		fi
	done

	if [[ -n "$sistema" ]]; then
		copia_sistema=$(mktemp "$sistema/.$nombre.XXXXXXXX")
		cp -- "$copia_datos" "$copia_sistema"
		cmp -- "$copia_datos" "$copia_sistema"
	fi
	if [[ -n "$propietario" ]]; then
		chown "$propietario" "$copia_datos"
		if [[ -n "$copia_sistema" ]]; then
			chown "$propietario" "$copia_sistema"
		fi
	fi

	destino="$datos/$nombre"
	ln -T -- "$copia_datos" "$destino"
	if [[ -n "$copia_sistema" ]] && ! ln -T -- "$copia_sistema" "$sistema/$nombre"; then
		rm -f -- "$destino"
		exit 20
	fi
	printf '✅ Backup creado: %s\n' "$destino"
)
