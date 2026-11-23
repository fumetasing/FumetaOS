#!/bin/bash

###########################################################
# FumetaOS
# Monitor de organización multimedia
###########################################################

MEDIA_ROOT="/mnt/datos/Multimedia"
SERIES="$MEDIA_ROOT/Series"
MOVIES="$MEDIA_ROOT/Peliculas"

MAX_EXAMPLES=5

es_video() {
	case "${1,,}" in
	*.avi | *.m4v | *.mkv | *.mov | *.mp4 | *.mpg | *.mpeg | *.ts | *.wmv)
		return 0
		;;
	*)
		return 1
		;;
	esac
}

mostrar_ejemplos() {
	local title="$1"
	shift
	local -a entries=("$@")
	local index
	local limit="${#entries[@]}"

	echo "   $title: ${#entries[@]}"

	if [ "$limit" -gt "$MAX_EXAMPLES" ]; then
		limit="$MAX_EXAMPLES"
	fi

	for ((index = 0; index < limit; index++)); do
		echo "   • ${entries[$index]#"$MEDIA_ROOT/"}"
	done

	if [ "${#entries[@]}" -gt "$MAX_EXAMPLES" ]; then
		echo "   • … y $((${#entries[@]} - MAX_EXAMPLES)) más"
	fi
}

if [ ! -d "$SERIES" ] || [ ! -d "$MOVIES" ]; then
	echo "🔴 Biblioteca multimedia incompleta"
	echo "   Esperado: $SERIES"
	echo "   Esperado: $MOVIES"
	exit 20
fi

declare -a loose_series=()
declare -a suspicious_episodes=()
declare -a misplaced_episodes=()
declare -a empty_files=()
declare -a unreadable_files=()

while IFS= read -r -d '' file; do
	if es_video "$file"; then
		loose_series+=("$file")
	fi
done < <(
	find "$SERIES" \
		-maxdepth 1 \
		-type f \
		-print0 2>/dev/null
)

while IFS= read -r -d '' file; do
	if ! es_video "$file"; then
		continue
	fi

	name="${file##*/}"

	if [[ ! "$name" =~ [Ss][0-9]{1,2}[Ee][0-9]{1,3} ]] &&
		[[ ! "$name" =~ \[Cap\.[0-9]+\] ]]; then
		suspicious_episodes+=("$file")
	fi
done < <(
	find "$SERIES" \
		-mindepth 2 \
		-type f \
		-print0 2>/dev/null
)

while IFS= read -r -d '' file; do
	if ! es_video "$file"; then
		continue
	fi

	name="${file##*/}"

	if [[ "$name" =~ [Ss][0-9]{1,2}[Ee][0-9]{1,3} ]] ||
		[[ "$name" =~ \[Cap\.[0-9]+\] ]]; then
		misplaced_episodes+=("$file")
	fi
done < <(
	find "$MOVIES" \
		-type f \
		-print0 2>/dev/null
)

while IFS= read -r -d '' file; do
	if es_video "$file"; then
		if [ ! -s "$file" ]; then
			empty_files+=("$file")
		fi

		if [ ! -r "$file" ]; then
			unreadable_files+=("$file")
		fi
	fi
done < <(
	find "$SERIES" "$MOVIES" \
		-type f \
		-print0 2>/dev/null
)

TOTAL_PROBLEMS=$((\
	${#loose_series[@]} + \
	${#suspicious_episodes[@]} + \
	${#misplaced_episodes[@]} + \
	${#empty_files[@]} + \
	${#unreadable_files[@]}))

if [ "$TOTAL_PROBLEMS" -eq 0 ]; then
	echo "🟢 Organización multimedia correcta"
	echo "   Películas: sin episodios mal ubicados"
	echo "   Series: sin vídeos sueltos ni episodios dudosos"
	echo "   Archivos: legibles y con contenido"
	exit 0
fi

echo "🟠 Biblioteca multimedia: $TOTAL_PROBLEMS elementos para revisar"

if [ "${#loose_series[@]}" -gt 0 ]; then
	mostrar_ejemplos \
		"Vídeos sueltos en Series" \
		"${loose_series[@]}"
fi

if [ "${#suspicious_episodes[@]}" -gt 0 ]; then
	mostrar_ejemplos \
		"Episodios con nombre no reconocible" \
		"${suspicious_episodes[@]}"
fi

if [ "${#misplaced_episodes[@]}" -gt 0 ]; then
	mostrar_ejemplos \
		"Posibles episodios dentro de Películas" \
		"${misplaced_episodes[@]}"
fi

if [ "${#empty_files[@]}" -gt 0 ]; then
	mostrar_ejemplos \
		"Vídeos vacíos" \
		"${empty_files[@]}"
fi

if [ "${#unreadable_files[@]}" -gt 0 ]; then
	mostrar_ejemplos \
		"Vídeos no legibles" \
		"${unreadable_files[@]}"
fi

exit 10
