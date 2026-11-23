import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(os.environ.get('TEST_AUDIT_ROOT', Path(__file__).resolve().parents[1]))


class RuntimeRegressionTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix='fumetaos-runtime-test-')
        self.addCleanup(temporary.cleanup)
        self.folder = Path(temporary.name)
        self.env = dict(os.environ, PATH=f"{self.folder}:{os.environ['PATH']}")

    def stub(self, name, body):
        path = self.folder / name
        path.write_text('#!/bin/bash\n' + body)
        path.chmod(0o755)

    def run_script(self, name, replacements=None):
        text = (ROOT / name).read_text()
        for old, new in (replacements or {}).items():
            self.assertIn(old, text)
            text = text.replace(old, new)
        script = self.folder / 'script.sh'
        script.write_text(text)
        return subprocess.run(['bash', str(script)], input='Test message\n',
                              text=True, capture_output=True, env=self.env, timeout=5)

    def test_transmission_list_failure_is_not_success(self):
        self.stub('docker', 'exit 9\n')
        result = self.run_script('bin/fumetaos-transmission-cleanup')
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn('No hay torrents', result.stdout)

    def test_transmission_remove_failure_is_not_success(self):
        self.stub('docker', '''case "$*" in
*--list*) echo '1 100% 1GB Done 0 0 1 Idle Title' ;;
*) exit 9 ;;
esac
''')
        result = self.run_script('bin/fumetaos-transmission-cleanup')
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn('✅', result.stdout)

    def test_transmission_success_keeps_downloaded_files(self):
        self.stub('docker', '''case "$*" in
*--list*) echo '1 100% 1GB Done 0 0 1 Idle Title' ;;
*--remove-and-delete*) exit 99 ;;
*) exit 0 ;;
esac
''')
        result = self.run_script('bin/fumetaos-transmission-cleanup')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('sus archivos se conservan', result.stdout)

    def telegram(self, body):
        config = self.folder / 'test.conf'
        config.write_text('TELEGRAM_TOKEN=test-token\nTELEGRAM_CHAT_ID=test-chat\n')
        self.stub('curl', body)
        return self.run_script('bin/telegram-notify',
                              {'/opt/fumetaos/config/fumetaos.conf': str(config)})

    def test_telegram_has_connection_and_total_timeouts(self):
        result = self.telegram('''[[ "$*" == *"--connect-timeout 10"* && "$*" == *"--max-time 30"* ]] || exit 99
printf '%s\\n' '{"ok":true}'
''')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_telegram_accepts_valid_json_with_whitespace(self):
        result = self.telegram("printf '%s\\n' '{\"ok\": true}'\n")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_telegram_rejects_api_and_connection_errors(self):
        for body in ("echo '{\"ok\":false}'\n", 'exit 28\n'):
            with self.subTest(body=body):
                result = self.telegram(body)
                self.assertNotEqual(result.returncode, 0)

    def long_test(self, status, max_wait=43200):
        self.stub('smartctl', 'exit 99\n')
        reply = ('return 1' if status is None else
                 f"echo 'Self-test execution status: ({status}) test result'")
        stub = f'''HDD_DEVICE=hdd
SSD_DEVICE=ssd
HDD_NAME=HDD
SSD_NAME=SSD
id() {{ echo 0; }}
sleep() {{ touch "{self.folder}/started"; }}
smartctl_cmd() {{
 case "$1" in
 -t) touch "{self.folder}/long-running" ;;
 -l) echo '# 1 Extended offline Completed without error 00% 1000 -' ;;
 -H) echo PASSED ;;
 -c)
   if [[ "$2" == hdd && -e "{self.folder}/long-running" && ! -e "{self.folder}/started" ]]; then
     echo "Self-test routine in progress"
   elif [[ "$2" == ssd && -e "{self.folder}/started" ]]; then
     {reply}
   else
     echo 'Self-test execution status: (0) completed without error'
   fi ;;
 esac
}}
'''
        return self.run_script('bin/fumetaos-smart-test', {
            'source /opt/fumetaos/core/common.sh': stub,
            'TELEGRAM_NOTIFY="/opt/fumetaos/bin/telegram-notify"': 'TELEGRAM_NOTIFY=""',
            'MAX_WAIT_SECONDS=43200': f'MAX_WAIT_SECONDS={max_wait}',
            'LOCK_FILE="/run/lock/fumetaos-smart-test.lock"': f'LOCK_FILE="{self.folder}/test.lock"',
        })

    def test_long_smart_rejects_aborted_ssd_even_when_health_passes(self):
        result = self.long_test(16)
        self.assertEqual(result.returncode, 20, result.stdout + result.stderr)
        self.assertIn('SSD Sistema: la prueba larga no terminó correctamente', result.stdout)
        self.assertNotIn('✅ Pruebas SMART largas terminadas correctamente', result.stdout)

    def test_long_smart_reports_unreadable_ssd_status(self):
        result = self.long_test(None)
        self.assertEqual(result.returncode, 20, result.stdout + result.stderr)
        self.assertIn('No se pudo consultar el estado SMART de SSD', result.stdout)

    def test_long_smart_accepts_completed_ssd(self):
        result = self.long_test(0)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_long_smart_reports_in_progress_at_deadline(self):
        result = self.long_test(0, max_wait=0)
        self.assertEqual(result.returncode, 21, result.stdout + result.stderr)
        self.assertIn('prueba larga aún en curso', result.stdout)
        self.assertNotIn('no terminó correctamente', result.stdout)

    def test_disk_monitor_rejects_missing_hdd_mount(self):
        common = '''SSD_NAME=SSD
HDD_NAME=HDD
DISK_WARNING=90
DISK_CRITICAL=93
'''
        self.stub('mountpoint', '[[ "${@: -1}" != /mnt/datos ]]\n')
        self.stub('findmnt', '''case "$*" in
*/mnt/data-wd*) echo 87d65071-48b3-439c-8e8d-4216f3c60d5d ;;
*) echo 707e3c0f-2728-4381-97f2-800bf12c668d ;;
esac
''')
        self.stub('df', '''echo 'Filesystem Size Used Available Use% Mounted on'
echo '/dev/test 100G 10G 90G 10% /'
''')
        result = self.run_script('modules/monitor/disks.sh',
                                 {'source /opt/fumetaos/core/common.sh': common})
        self.assertEqual(result.returncode, 20, result.stdout + result.stderr)
        self.assertNotIn('🟢 HDD', result.stdout)

    def test_quality_excludes_python_from_bash_checks(self):
        project = self.folder / 'project'
        for name in ('bin', 'core', 'modules', 'apps', 'install'):
            (project / name).mkdir(parents=True)
        (project / 'bin/test-bash').write_text('#!/bin/bash\necho ok\n')
        (project / 'bin/test-sh').write_text('#!/bin/sh\necho ok\n')
        (project / 'bin/test-python').write_text('#!/usr/bin/env python3\nprint("ok")\n')
        quality = project / 'bin/fumetaos-quality'
        quality.write_bytes((ROOT / 'bin/fumetaos-quality').read_bytes())
        self.stub('shellcheck', '[[ "$*" != *test-python* && "$*" == *test-sh* ]]\n')
        self.stub('shfmt', '[[ "$*" != *test-python* ]]\n')
        self.stub('git', 'exit 0\n')
        result = subprocess.run(['bash', str(quality)], capture_output=True,
                                text=True, env=self.env, timeout=5)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        alias = self.folder / 'alias-bin'
        alias.symlink_to(project / 'bin', target_is_directory=True)
        self.stub('git', f'[[ "$PWD" == "{project}" ]]\n')
        result = subprocess.run(['bash', str(alias / 'fumetaos-quality')], capture_output=True,
                                text=True, env=self.env, timeout=5)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        (project / 'bin/test-python').write_text('#!/usr/bin/env python3\ndef broken(\n')
        result = subprocess.run(['bash', str(quality)], capture_output=True,
                                text=True, env=self.env, timeout=5)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('SyntaxError', result.stderr)

    def test_latest_backup_handles_large_history_without_sigpipe(self):
        text = (ROOT / 'bin/fumetaos-backup').read_text()
        function = text.split('latest_backup() {', 1)[1].split('create_backup() {', 1)[0]
        self.stub('find', '''for ((i=1; i<=10000; i++)); do
 printf '%s /backup/file-%0500d.tar.gz\\n' "$i" "$i"
done
''')
        result = subprocess.run(['bash', '-c', 'set -eo pipefail\nDATA_DIR=x\nSYSTEM_DIR=y\nPREFIX=z\nlatest_backup() {' + function + '\nlatest_backup'],
                                capture_output=True, text=True, env=self.env, timeout=10)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(result.stdout.strip().endswith('10000.tar.gz'))


    def test_firewall_distinguishes_active_from_inactive(self):
        checker = self.folder / 'checker'
        checker.write_text('#!/bin/bash\nexit 0\n')
        checker.chmod(0o755)
        self.stub('sudo', '''case "$*" in
*"status verbose"*) printf 'Status: %s\\nDefault: deny (incoming)\\n' "$TEST_UFW_STATUS" ;;
*"status"*) printf 'Status: %s\\n' "$TEST_UFW_STATUS" ;;
*) exit 0 ;;
esac
''')
        for status, expected in (('active', 0), ('inactive', 20)):
            with self.subTest(status=status):
                self.env['TEST_UFW_STATUS'] = status
                result = self.run_script('modules/monitor/security.sh', {
                    'UFW_BIN="/usr/sbin/ufw"': f'UFW_BIN="{checker}"',
                    'DOCKER_STATUS="/opt/fumetaos/bin/fumetaos-docker-firewall-status"': f'DOCKER_STATUS="{checker}"',
                })
                self.assertEqual(result.returncode, expected, result.stdout + result.stderr)
                if status == 'inactive':
                    self.assertNotIn('🟢 Firewall UFW activo', result.stdout)

    def test_app_health_uses_bounded_http_request(self):
        self.stub('docker', 'exit 1\n')
        self.stub('curl', '[[ "$*" == *"--connect-timeout 5"* && "$*" == *"--max-time 10"* ]]\n')
        text = (ROOT / 'core/apps.sh').read_text()
        text = '\n'.join(line for line in text.splitlines() if not line.startswith('source '))
        script = self.folder / 'apps.sh'
        script.write_text(text + '\nAPP_CONTAINER=test\nAPP_HEALTH=http://example.invalid\napp_health\n')
        result = subprocess.run(['bash', str(script)], capture_output=True, text=True, env=self.env, timeout=5)
        self.assertEqual(result.stdout.strip(), 'healthy', result.stderr)

    def test_timecapsule_access_failure_has_a_timeout(self):
        self.stub('systemctl', 'exit 0\n')
        self.stub('findmnt', 'echo cifs\n')
        self.stub('timeout', '''[[ "$*" == *"--kill-after=5 15 ls /DATA/TimeCapsule"* ]] || exit 99
exit 124
''')
        self.stub('ls', 'exit 0\n')
        self.stub('df', '''echo 'Filesystem Size Used Available Use% Mounted on'
echo '/dev/test 100G 10G 90G 10% /'
''')
        result = self.run_script('modules/monitor/timecapsule.sh', {
            'source /opt/fumetaos/core/common.sh': 'DISK_WARNING=90\nDISK_CRITICAL=93',
            'SMB_CLIENT="/usr/sbin/mount.cifs"': 'SMB_CLIENT="/usr/bin/true"',
        })
        self.assertEqual(result.returncode, 20, result.stdout + result.stderr)
        self.assertIn('sin acceso desde CasaOS', result.stdout)

    def test_smart_services_always_restore_idle_even_if_initially_inactive(self):
        import shlex
        self.env['TEST_LOG'] = str(self.folder / 'systemctl.log')
        self.stub('systemctl', '''printf '%s\\n' "$*" >> "$TEST_LOG"
case "$1" in
cat) exit 0 ;;
is-active) exit 3 ;;
*) exit 0 ;;
esac
''')
        for service, disks in (('fumetaos-smart-test', ['datos']), ('fumetaos-smart-short-test', ['datos', 'wd'])):
            with self.subTest(service=service):
                content = (ROOT / 'services' / f'{service}.service').read_text()
                log = Path(self.env['TEST_LOG'])
                log.unlink(missing_ok=True)
                for phase in ('ExecStartPre=', 'ExecStopPost='):
                    line = next(line for line in content.splitlines() if line.startswith(phase))
                    args = shlex.split(line[len(phase):])
                    self.assertEqual(args[:2], ['/usr/bin/bash', '-c'])
                    code = args[2].replace('$$', '$').replace('/usr/bin/systemctl', str(self.folder / 'systemctl'))
                    result = subprocess.run(['bash', '-c', code], capture_output=True, text=True, env=self.env, timeout=5)
                    self.assertEqual(result.returncode, 0, result.stderr)
                operations = log.read_text().splitlines()
                for disk in disks:
                    self.assertIn(f'stop hd-idle-{disk}.service', operations)
                    self.assertIn(f'start hd-idle-{disk}.service', operations)
                if service == 'fumetaos-smart-test':
                    self.assertNotIn('stop hd-idle-wd.service', operations)
                    self.assertNotIn('start hd-idle-wd.service', operations)

    def test_recovery_reports_restart_failures_and_attempts_all_components(self):
        text = (ROOT / 'bin/fumetaos-recovery-backup').read_text()
        definitions = text.split('\n[ "$(id -u)" -eq 0 ] ||', 1)[0]
        self.assertNotEqual(definitions, text)
        for component, expected in (('none', 0), ('casaos', 20), ('docker', 20), ('vm', 20)):
            with self.subTest(component=component):
                self.env['TEST_FAIL'] = component
                self.env['TEST_LOG'] = str(self.folder / 'restart.log')
                stub = r'''
SERVICES_STOPPED=1
CASAOS_WAS_ACTIVE=1
VMS_STOPPED=1
RUNNING_CONTAINERS=(app)
RUNNING_VMS=(vm)
VM_BACKUP_DIR="$TEST_EMPTY_DIR"
systemctl() { echo casaos >> "$TEST_LOG"; [[ "$TEST_FAIL" != casaos ]]; }
docker() { echo docker >> "$TEST_LOG"; [[ "$TEST_FAIL" != docker ]]; }
virsh() {
    if [[ "$*" == *domstate* ]]; then echo 'shut off'; return 0; fi
    echo vm >> "$TEST_LOG"
    [[ "$TEST_FAIL" != vm ]]
}
if limpiar; then exit 0; else exit $?; fi
'''
                self.env['TEST_EMPTY_DIR'] = str(self.folder / 'nonexistent-vm-cache')
                log = Path(self.env['TEST_LOG'])
                log.unlink(missing_ok=True)
                result = subprocess.run(['bash', '-c', definitions + stub], capture_output=True,
                                        text=True, env=self.env, timeout=5)
                self.assertEqual(result.returncode, expected, result.stdout + result.stderr)
                self.assertEqual(log.read_text().splitlines(), ['casaos', 'docker', 'vm'])


    def test_vm_warning_does_not_hide_an_earlier_critical_error(self):
        self.stub('virsh', '''case "$*" in
*"list --all --name"*) printf 'broken\\npaused\\n' ;;
*"domstate broken"*) echo crashed ;;
*"domstate paused"*) echo paused ;;
*) exit 1 ;;
esac
''')
        result = self.run_script('modules/monitor/virtual-machines.sh')
        self.assertEqual(result.returncode, 20, result.stdout + result.stderr)

    def test_app_url_replaces_literal_ip_placeholder(self):
        text = (ROOT / 'core/apps.sh').read_text()
        text = '\n'.join(line for line in text.splitlines() if not line.startswith('source '))
        result = subprocess.run(['bash', '-c', text + '\nAPP_URL=\nAPP_WEBUI="http://[IP]:8097"\napp_report_url\n'],
                                capture_output=True, text=True, env=self.env, timeout=5)
        self.assertEqual(result.stdout.strip(), 'http://localhost:8097', result.stderr)


    def test_legacy_torrent_hook_propagates_removal_failure(self):
        self.env.update(TR_TORRENT_ID='1', TR_TORRENT_DIR=str(self.folder), TR_TORRENT_NAME='', USER='test', PASS='test')
        self.stub('find', 'exit 0\n')
        for code, expected in ((0, 0), (9, 20)):
            with self.subTest(code=code):
                self.stub('test-remote', f'exit {code}\n')
                result = self.run_script('apps/transmission/scripts/torrent-done.sh',
                    {'/usr/bin/transmission-remote': str(self.folder / 'test-remote')})
                self.assertEqual(result.returncode, expected, result.stdout + result.stderr)


if __name__ == '__main__':
    unittest.main()
