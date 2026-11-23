import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class AppMonitorTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix='fumetaos-app-monitor-')
        self.addCleanup(temporary.cleanup)
        self.folder = Path(temporary.name)
        self.log = self.folder / 'calls.log'
        self.env = dict(os.environ, PATH=f"{self.folder}:{os.environ['PATH']}",
                        TEST_LOG=str(self.log), TEST_COUNT='10')
        self.stub('docker', '''printf '%s\\n' "$1" >> "$TEST_LOG"
case "$1" in
info) exit 0 ;;
ps)
    [[ "${TEST_LIST_FAIL:-0}" != 1 ]] || exit 1
    for ((i=1; i<=TEST_COUNT; i++)); do
        printf '%s|container%s|%s|%simage%s:latest|%s|0.0.0.0:8000->80/tcp\\n' \\
            "${TEST_PROJECT:-proj$i}" "$i" "${TEST_STATE:-running}" "${TEST_ALIAS:-}" "$i" "${TEST_HEALTH:-healthy}"
    done ;;
image)
    if [[ "$*" == *'.RepoTags'* ]]; then
        [[ "${TEST_BATCH_FAIL:-0}" != 1 ]] || exit 1
        for ((i=1; i<=TEST_COUNT; i++)); do
            printf 'image%s:latest|%s\\n' "$i" "${TEST_VERSION:-v$i}"
        done
    else
        reference="${@: -1}"
        [[ "$reference" =~ image([0-9]+) ]] || exit 1
        printf '%s\\n' "${TEST_VERSION:-v${BASH_REMATCH[1]}}"
    fi ;;
*) exit 99 ;;
esac
''')
        self.stub('curl', '''echo curl >> "$TEST_LOG"
[[ "$*" == *"--connect-timeout 5"* && "$*" == *"--max-time 10"* ]] || exit 99
printf 'HTTP/1.1 200 OK\\r\\n\\r\\nHealthy\\n'
''')

    def stub(self, name, body):
        path = self.folder / name
        path.write_text('#!/bin/bash\n' + body)
        path.chmod(0o755)

    def monitor(self):
        return subprocess.run(['bash', str(ROOT / 'modules/monitor/apps.sh')],
                              capture_output=True, text=True, env=self.env, timeout=5)

    def calls(self, name):
        return self.log.read_text().splitlines().count(name)

    def test_ten_apps_use_one_image_query_and_one_container_query(self):
        result = self.monitor()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.calls('image'), 1)
        self.assertEqual(self.calls('ps'), 1)
        self.assertEqual(self.calls('info'), 0)
        self.assertIn('Total: 10', result.stdout)
        for i in range(1, 11):
            self.assertIn(f'Versión: v{i}', result.stdout)

    def test_unknown_alias_keeps_individual_query_fallback(self):
        self.env.update(TEST_COUNT='1', TEST_ALIAS='private/')
        result = self.monitor()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('Versión: v1', result.stdout)
        self.assertEqual(self.calls('image'), 2)

    def test_batch_failure_keeps_versions_using_individual_queries(self):
        self.env.update(TEST_COUNT='2', TEST_BATCH_FAIL='1')
        result = self.monitor()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('Versión: v1', result.stdout)
        self.assertIn('Versión: v2', result.stdout)
        self.assertEqual(self.calls('image'), 3)

    def test_missing_version_preserves_tag_fallback(self):
        self.env.update(TEST_COUNT='1', TEST_VERSION='<no value>')
        result = self.monitor()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('Versión: latest', result.stdout)

    def test_failed_container_listing_is_reported(self):
        self.env['TEST_LIST_FAIL'] = '1'
        result = self.monitor()
        self.assertEqual(result.returncode, 20, result.stdout + result.stderr)
        self.assertNotIn('Total: 0', result.stdout)

    def test_empty_inventory_uses_no_image_queries(self):
        self.env['TEST_COUNT'] = '0'
        result = self.monitor()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('Total: 0', result.stdout)
        self.assertEqual(self.calls('image'), 0)

    def test_stopped_transmission_does_not_trigger_http_checks(self):
        self.env.update(TEST_COUNT='1', TEST_PROJECT='transmission', TEST_STATE='exited')
        result = self.monitor()
        self.assertEqual(result.returncode, 20, result.stdout + result.stderr)
        self.assertIn('Detenido', result.stdout)
        self.assertEqual(self.calls('curl'), 0)

    def test_running_transmission_uses_bounded_http_checks(self):
        self.env.update(TEST_COUNT='1', TEST_PROJECT='transmission')
        result = self.monitor()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('Health: 🟢 healthy', result.stdout)
        self.assertEqual(self.calls('curl'), 1)


    def test_unhealthy_running_application_has_a_red_heading(self):
        self.env.update(TEST_COUNT='1', TEST_HEALTH='unhealthy')
        result = self.monitor()
        self.assertEqual(result.returncode, 20, result.stdout + result.stderr)
        self.assertIn('🔴 Proj1', result.stdout)
        self.assertNotIn('🟢 Proj1', result.stdout)



if __name__ == '__main__':
    unittest.main()
