#!/bin/bash

# Grupo independiente del espejo: solo el repositorio cifrado de recuperación.
mac_mirror_validar_recovery() {
    python3 - "$MAC_RECOVERY_SOURCE" <<'PY' || return 20
from pathlib import Path
import sys
p = Path(sys.argv[1])
if not p.is_absolute() or p.resolve() != p or not p.is_dir():
    raise SystemExit('El repositorio no es un directorio real en la ruta esperada')
for name in ('data', 'index', 'snapshots', 'keys', 'locks'):
    q = p / name
    if q.is_symlink() or not q.is_dir():
        raise SystemExit('Falta un directorio del repositorio: ' + name)
config = p / 'config'
if config.is_symlink() or not config.is_file() or config.stat().st_size == 0:
    raise SystemExit('Falta la configuración del repositorio')
if not any(q.is_file() and not q.is_symlink() for q in (p / 'snapshots').iterdir()):
    raise SystemExit('El repositorio no contiene instantáneas; no se permiten borrados')
PY
    # Verifica que Restic puede descifrar su configuración con la clave instalada.
    restic --repo "$MAC_RECOVERY_SOURCE" \
        --password-file /etc/fumetaos/restic-password \
        --cache-dir /var/cache/fumetaos-restic cat config >/dev/null
}

mac_mirror_recovery_remote_script() {
    cat <<'REMOTE'
set -eu
for ruta in "$DESTINATION/backups" "$DESTINATION/backups/fumetaos" "$RECOVERY_DESTINATION"; do
    if [ -L "$ruta" ]; then
        echo "Destino de recuperación con enlace simbólico; no se copia ni borra" >&2
        exit 20
    fi
    if [ -e "$ruta" ] && [ ! -d "$ruta" ]; then
        echo "Destino de recuperación inesperado; no se copia ni borra" >&2
        exit 20
    fi
done
if [ -d "$RECOVERY_DESTINATION" ]; then
    config="$RECOVERY_DESTINATION/config"
    if [ -L "$config" ] || [ ! -f "$config" ]; then
        echo "El destino existente no tiene configuración Restic; no se borra" >&2
        exit 20
    fi
    actual=$(shasum -a 256 "$config" | awk '{print $1}')
    if [ "$actual" != "$EXPECTED_CONFIG_HASH" ]; then
        echo "El destino pertenece a otro repositorio Restic; no se borra" >&2
        exit 20
    fi
fi
REMOTE
}

mac_mirror_preparar_recovery() {
    local config_hash remote_script
    CURRENT_STEP="Validación del repositorio cifrado de recuperación"
    mac_mirror_validar_recovery || return 20
    config_hash=$(sha256sum "$MAC_RECOVERY_SOURCE/config" | awk '{print $1}') || return 20
    remote_script=$(
        printf 'DESTINATION=%q\n' "$MAC_DESTINATION"
        printf 'RECOVERY_DESTINATION=%q\n' "$MAC_RECOVERY_DESTINATION"
        printf 'EXPECTED_CONFIG_HASH=%q\n' "$config_hash"
        mac_mirror_recovery_remote_script
    )
    mac_mirror_usb_disponible || return 20
    mac_mirror_ssh_comprobar "$MAC_USER@$MAC_HOST" /bin/sh -s <<<"$remote_script" || return 20
}

mac_mirror_copiar_recovery() {
    CURRENT_STEP="Copia del repositorio cifrado de recuperación sin límite de borrados"
    mac_mirror_usb_disponible || return 20
    mac_mirror_copiar "$MAC_RECOVERY_SOURCE/" \
        "$MAC_USER@$MAC_HOST:$MAC_RECOVERY_DESTINATION/" --mkpath
}
