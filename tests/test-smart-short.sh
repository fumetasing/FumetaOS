#!/bin/bash
# Sin dispositivos reales, esperas, root, Telegram ni conexiones.
set -euo pipefail
SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SOURCE_DIR/bin/fumetaos-smart-short-test"
TEST_DIR="$(mktemp -d)"
trap 'rm -rf -- "$TEST_DIR"' EXIT

run_case() (
    local scenario="$1" expected="$2" result=0
    SHORT_LOCK="$TEST_DIR/$scenario.lock"
    HDD_DEVICE=hdd
    SSD_DEVICE=ssd
    TEST_LOG="$TEST_DIR/$scenario.log"
    TEST_STARTED="$TEST_DIR/$scenario.started"
    : >"$TEST_LOG"
    sleep() { :; }
    smartctl_cmd() {
        printf '%s %s %s\n' "$@" >>"$TEST_LOG"
        case "$1" in
        -t)
            [ "$scenario" != start_failure ] || return 1
            touch "$TEST_STARTED";;
        -c)
            if [ "$scenario" = busy ] ||
                { [ "$scenario" = timeout ] && [ -e "$TEST_STARTED" ]; }; then
                echo 'Self-test execution status: (249) Self-test routine in progress...'
            elif [ "$scenario" = failed_result ] && [ -e "$TEST_STARTED" ]; then
                echo 'Self-test execution status: (112) read failure'
            elif [ "$scenario" = unreadable ]; then
                return 1
            else
                echo 'Self-test execution status: (   0) previous self-test completed without error'
            fi;;
        -l)
            if [ "$scenario" = wrong_test ]; then
                echo '# 1 Extended offline Completed without error 00% 1000 -'
            elif [ "$scenario" = bad_log ]; then
                echo '# 1 Short offline Completed: read failure 00% 1000 123'
            else
                echo '# 1 Short offline Completed without error 00% 1000 -'
            fi;;
        -H)
            [ "$scenario" != bad_health ] || { echo FAILED; return 1; }
            echo 'SMART overall-health self-assessment test result: PASSED';;
        *) return 1;;
        esac
    }
    smart_short_run >"$TEST_DIR/$scenario.output" 2>&1 || result=$?
    [ "$result" -eq "$expected" ] || {
        cat "$TEST_DIR/$scenario.output"; echo "Falló $scenario: $result"; exit 1;
    }
    if [ "$scenario" = busy ] || [ "$scenario" = unreadable ]; then
        ! grep -q '^-t ' "$TEST_LOG" || exit 1
    fi
    if [ "$scenario" = success ]; then
        [ "$(grep -c '^-t short ' "$TEST_LOG")" -eq 2 ] || exit 1
    fi
)

run_case success 0
for scenario in busy unreadable start_failure timeout failed_result wrong_test bad_log bad_health; do
    run_case "$scenario" 20
done
echo '✅ SMART corto: nueve escenarios simulados; sin pruebas ni esperas reales.'
