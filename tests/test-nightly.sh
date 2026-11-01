#!/bin/bash

# Simula systemd y usa únicamente archivos temporales: no inicia tareas reales.
set -euo pipefail

SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_DIR="$(mktemp -d)"
trap 'rm -rf -- "$TEST_DIR"' EXIT

# shellcheck source=../bin/fumetaos-nightly
source "$SOURCE_DIR/bin/fumetaos-nightly"

BASE_UNITS=(
    fumetaos-backup.service
    fumetaos-timecapsule-mac-backup.service
    fumetaos-recovery-backup.service
    fumetaos-mac-backup.service
    fumetaos-system-upgrade.service
    fumetaos-docker-clean.service
)

fail() {
    echo "❌ $*" >&2
    exit 1
}

assert_status() {
    local case_name="$1" expected="$2" actual="$3"
    [ "$actual" -eq "$expected" ] ||
        fail "$case_name: código $actual; esperado $expected"
}

assert_units() {
    local case_name="$1"
    shift
    printf '%s\n' "$@" >"$TEST_DIR/$case_name/expected-units"
    diff -u "$TEST_DIR/$case_name/expected-units" "$TEST_DIR/$case_name/units" ||
        fail "$case_name: orden de servicios incorrecto"
}

assert_field() {
    local case_name="$1" field="$2" value="$3"
    grep -Fxq "$field=$value" "$TEST_DIR/$case_name/status" ||
        fail "$case_name: estado $field distinto de $value"
}

run_case() {
    local case_name="$1" day="$2" month="$3" day_of_month="$4" fail_unit="${5:-}"
    local result=0
    mkdir -p "$TEST_DIR/$case_name/stamps"

    (
        # Estas variables las consume nightly_run, definido en el archivo cargado.
        # shellcheck disable=SC2034
        VERIFY_STAMP="$TEST_DIR/$case_name/stamps/verify"
        # shellcheck disable=SC2034
        SMART_STAMP="$TEST_DIR/$case_name/stamps/smart"
        # shellcheck disable=SC2034
        STATUS_FILE="$TEST_DIR/$case_name/status"
        # shellcheck disable=SC2034
        LOCK_FILE="$TEST_DIR/$case_name/lock"
        TEST_LOG="$TEST_DIR/$case_name/units"
        FAIL_UNIT="$fail_unit"
        # shellcheck disable=SC2034
        START_DAY="$day"
        # shellcheck disable=SC2034
        START_MONTH="$month"
        # shellcheck disable=SC2034
        START_DAY_OF_MONTH="$day_of_month"

        systemctl() {
            [ "$1" = start ] || return 1
            printf '%s\n' "$2" >>"$TEST_LOG"
            [ "$2" != "$FAIL_UNIT" ]
        }

        nightly_run
    ) >"$TEST_DIR/$case_name/output" 2>&1 || result=$?

    printf '%s\n' "$result"
}

# Cada día ejecuta exactamente la prueba que le corresponde, siempre al final.
for day in 1 2 3 4 5 6 7; do
    name="weekday_$day"
    result="$(run_case "$name" "$day" 2026-11 "$day")"
    assert_status "$name" 0 "$result"
    if [ "$day" -eq 1 ]; then
        assert_units "$name" "${BASE_UNITS[@]}" fumetaos-recovery-verify.service fumetaos-smart-test.service
    else
        assert_units "$name" "${BASE_UNITS[@]}" fumetaos-smart-short-test.service
    fi
    assert_field "$name" result success
    [ ! -e "$TEST_DIR/$name/stamps/smart" ] || fail 'Se creó una marca mensual'
done

# Un fallo de verificación se registra y la larga del lunes sigue ejecutándose.
result="$(run_case verify_failure 1 2026-11 2 fumetaos-recovery-verify.service)"
assert_status verify_failure 20 "$result"
assert_units verify_failure "${BASE_UNITS[@]}" fumetaos-recovery-verify.service fumetaos-smart-test.service
assert_field verify_failure failed 'Verificación cifrada semanal'
[ ! -e "$TEST_DIR/verify_failure/stamps/verify" ] || fail 'Se marcó una verificación fallida'

result="$(run_case short_failure 2 2026-11 3 fumetaos-smart-short-test.service)"
assert_status short_failure 20 "$result"
assert_field short_failure failed 'Prueba SMART corta diaria'
result="$(run_case long_failure 1 2026-11 2 fumetaos-smart-test.service)"
assert_status long_failure 20 "$result"
assert_field long_failure failed 'Prueba SMART larga semanal'

# El primer sábado y los días posteriores no desencadenan ninguna larga mensual.
result="$(run_case first_saturday 6 2026-11 7)"
assert_status first_saturday 0 "$result"
assert_units first_saturday "${BASE_UNITS[@]}" fumetaos-smart-short-test.service
result="$(run_case late_month 5 2026-11 27)"
assert_status late_month 0 "$result"
assert_units late_month "${BASE_UNITS[@]}" fumetaos-smart-short-test.service

# Una antigua marca mensual no afecta a la larga del lunes ni se modifica.
mkdir -p "$TEST_DIR/old_stamp/stamps"
printf '%s\n' 2026-10 >"$TEST_DIR/old_stamp/stamps/smart"
result="$(run_case old_stamp 1 2026-11 2)"
assert_status old_stamp 0 "$result"
assert_units old_stamp "${BASE_UNITS[@]}" fumetaos-recovery-verify.service fumetaos-smart-test.service
[ "$(cat "$TEST_DIR/old_stamp/stamps/smart")" = 2026-10 ] || fail 'Se modificó la marca histórica'
echo '✅ Trece escenarios simulados correctos; ninguna tarea real iniciada.'
