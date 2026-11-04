#!/usr/bin/env python3
import hashlib
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
CORE = ROOT / 'core/mac-mirror-recovery.sh'
BIN = ROOT / 'bin/fumetaos-mac-backup'


class RecoveryMirror(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='fumetaos-restic-test-')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.repo = self.root / 'source/backups/fumetaos/recovery-repo'
        self.repo.mkdir(parents=True)
        for name in ('data', 'index', 'snapshots', 'keys', 'locks'):
            (self.repo / name).mkdir()
        (self.repo / 'config').write_bytes(b'encrypted-test-config')
        (self.repo / 'snapshots/test').write_bytes(b'test')
        self.dest = self.root / 'destination'
        self.dest.mkdir()
        self.tools = self.root / 'tools'
        self.tools.mkdir()
        p = self.tools / 'restic'
        p.write_text('#!/bin/sh\nprintf "restic\\n" >> "$RESTIC_LOG"\nexit "${FAIL_RESTIC:-0}"\n')
        p.chmod(0o755)
        self.env = dict(os.environ, PATH=str(self.tools) + ':' + os.environ['PATH'],
                        MAC_RECOVERY_SOURCE=str(self.repo), RESTIC_LOG=str(self.root / 'restic.log'))

    def local_check(self, **env):
        return subprocess.run(['bash', '-c', 'source "$1"; mac_mirror_validar_recovery', '_', str(CORE)],
                              env=dict(self.env, **env), capture_output=True, text=True)

    def remote_check(self):
        script = subprocess.check_output(['bash', '-c', 'source "$1"; mac_mirror_recovery_remote_script', '_', str(CORE)], text=True)
        env = dict(self.env, DESTINATION=str(self.dest),
                   RECOVERY_DESTINATION=str(self.dest / 'backups/fumetaos/recovery-repo'),
                   EXPECTED_CONFIG_HASH=hashlib.sha256((self.repo / 'config').read_bytes()).hexdigest())
        return subprocess.run(['sh', '-s'], input=script, env=env, capture_output=True, text=True)

    def test_valid_source(self):
        self.assertEqual(self.local_check().returncode, 0)

    def test_missing_source(self):
        shutil.rmtree(self.repo / 'data')
        self.assertNotEqual(self.local_check().returncode, 0)
        self.assertFalse((self.root / 'restic.log').exists())

    def test_linked_source(self):
        alias = self.root / 'alias'
        alias.symlink_to(self.repo, target_is_directory=True)
        self.assertNotEqual(self.local_check(MAC_RECOVERY_SOURCE=str(alias)).returncode, 0)

    def test_no_snapshots(self):
        (self.repo / 'snapshots/test').unlink()
        self.assertNotEqual(self.local_check().returncode, 0)

    def test_wrong_password(self):
        self.assertNotEqual(self.local_check(FAIL_RESTIC='1').returncode, 0)

    def test_new_destination(self):
        self.assertEqual(self.remote_check().returncode, 0)
        self.assertFalse((self.dest / 'backups').exists())

    def test_same_repository(self):
        p = self.dest / 'backups/fumetaos/recovery-repo'
        shutil.copytree(self.repo, p)
        self.assertEqual(self.remote_check().returncode, 0)

    def test_different_repository(self):
        p = self.dest / 'backups/fumetaos/recovery-repo'
        shutil.copytree(self.repo, p)
        (p / 'config').write_bytes(b'other-repository')
        self.assertNotEqual(self.remote_check().returncode, 0)

    def test_linked_destination(self):
        (self.dest / 'backups').symlink_to(self.root / 'source/backups', target_is_directory=True)
        self.assertNotEqual(self.remote_check().returncode, 0)

    def test_existing_destination_without_config(self):
        (self.dest / 'backups/fumetaos/recovery-repo').mkdir(parents=True)
        self.assertNotEqual(self.remote_check().returncode, 0)

    def filters(self):
        s = BIN.read_text()
        a = s.index('RSYNC_FILTER_OPTIONS=(')
        b = s.index('\n)', a) + 2
        return s[a:b]

    def test_rsync_quota_excludes_restic_and_ps4(self):
        # Rsync real, solo en dos carpetas temporales; nunca datos del servidor.
        source = self.root / 'source'
        shutil.copytree(source, self.dest, dirs_exist_ok=True)
        for i in range(85):
            (self.dest / 'backups/fumetaos/recovery-repo/data' / str(i)).write_text('old')
        (source / 'PS4 & PS5').mkdir()
        (self.dest / 'PS4 & PS5').mkdir()
        (self.dest / 'PS4 & PS5/old').write_text('old')
        for i in range(3):
            (self.dest / ('personal-' + str(i))).write_text('old')
        command = self.filters() + '\nrsync -an --delete-delay --itemize-changes "${RSYNC_FILTER_OPTIONS[@]}" --exclude="/PS4 & PS5/" --filter="P /PS4 & PS5/***" "$1/" "$2/"'
        result = subprocess.run(['bash', '-c', command, '_', str(source), str(self.dest)], capture_output=True, text=True, check=True)
        deleted = [line.split()[-1] for line in result.stdout.splitlines() if line.startswith('*deleting')]
        self.assertEqual(set(deleted), {'personal-0', 'personal-1', 'personal-2'})
        self.assertTrue((self.dest / 'personal-0').exists())  # Simulación, sin borrados.

    def test_copy_groups(self):
        source = self.root / 'source'
        (source / 'PS4 & PS5').mkdir()
        s = BIN.read_text()
        a = s.index('ejecutar_rsync_con_reintentos() {')
        b = s.index('\ncase "${1:-}" in', a)
        wrapper = '''set -euo pipefail
source "$1"
SOURCE_DIR="$2/"; MAC_USER=test; MAC_HOST=test; MAC_DESTINATION=/destination
MAC_RECOVERY_SOURCE="$SOURCE_DIR/backups/fumetaos/recovery-repo"
MAC_RECOVERY_DESTINATION=/destination/backups/fumetaos/recovery-repo
DRY_RUN=()
mac_mirror_usb_disponible() { return 0; }
mac_mirror_preparar_recovery() { return 0; }
mostrar_error() { echo "$*" >&2; exit 20; }
mac_mirror_contar_borrados() { echo 3; }
fumetaos_cupo_diario() { [ "$1" = 3 ] && [ "$2" = reserve ]; echo 3; }
mac_mirror_copiar() { printf 'COPY'; printf ' <%s>' "$@"; printf '\\n'; }
'''
        wrapper += self.filters() + '\n' + s[a:b] + '\nejecutar_rsync_con_reintentos\n'
        r = subprocess.run(['bash', '-c', wrapper, '_', str(CORE), str(source)], capture_output=True, text=True, check=True)
        copies = [line for line in r.stdout.splitlines() if line.startswith('COPY')]
        self.assertEqual(len(copies), 3)
        self.assertIn('PS4 & PS5/', copies[0])
        self.assertIn('recovery-repo/', copies[1])
        self.assertIn('--mkpath', copies[1])
        self.assertNotIn('--max-delete', copies[0] + copies[1])
        self.assertIn('--max-delete=3', copies[2])
        self.assertIn('P /backups/fumetaos/recovery-repo/***', copies[2])


if __name__ == '__main__':
    unittest.main(verbosity=2)
