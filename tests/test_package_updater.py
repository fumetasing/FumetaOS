import os
from pathlib import Path
import stat
import subprocess
import tarfile
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
DIRECTORIES = ("bin", "core", "modules")


class PackageUpdaterTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="fumetaos-updater-test-")
        self.addCleanup(temporary.cleanup)
        self.base = Path(temporary.name)
        self.package = self.base / "install/package"
        for root in (self.base, self.package):
            for directory in DIRECTORIES:
                (root / directory).mkdir(parents=True)
                (root / directory / "example").write_text(
                    "old\n" if root == self.base else "new\n"
                )
        (self.base / "VERSION").write_text("2.4.41\n")
        (self.package / "VERSION").write_text("2.4.42\n")
        for command in ("bin/fumetaos", "bin/fumetaos-doctor", "core/common.sh"):
            file = self.package / command
            file.write_text("#!/bin/bash\n")
            file.chmod(0o755)
        journal = self.package / "config/systemd/journald.conf.d/90-fumetaos.conf"
        journal.parent.mkdir(parents=True)
        journal.write_text("[Journal]\n")
        (self.package / "services").mkdir()
        (self.package / "apps").mkdir()
        timers = ("watch", "history", "history-clean", "report", "nightly", "timecapsule-watch")
        for timer in timers:
            for kind in ("service", "timer"):
                (self.package / "services" / f"fumetaos-{timer}.{kind}").write_text("[Unit]\n")
        for name in ("package-validation.sh", "installation-backup.sh"):
            (self.base / "core" / name).write_bytes((ROOT / "core" / name).read_bytes())
        self.script = self.base / "install/update.sh"
        self.script.write_text(
            (ROOT / "install/update.sh").read_text().replace(
                'BASE="/opt/fumetaos"', 'BASE="$TEST_BASE"'
            )
        )
        self.exchange = ROOT / "core/package-path-exchange.py"
        self.installer = self.base / "install/install.sh"
        self.installer.write_text(
            (ROOT / "install/install.sh").read_text().replace(
                'BASE="/opt/fumetaos"', 'BASE="$TEST_BASE"'
            )
        )


    def run_script(self, command):
        return subprocess.run(
            ["bash", "-c", command, "_", str(self.script)],
            env=dict(os.environ, TEST_BASE=str(self.base), TEST_EXCHANGE=str(self.exchange)),
            capture_output=True, text=True, timeout=10,
        )

    def check(self):
        return self.run_script('bash "$1" --check')

    def test_check_accepts_complete_package_without_applying_it(self):
        result = self.check()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((self.base / "VERSION").read_text(), "2.4.41\n")
        self.assertEqual((self.base / "bin/example").read_text(), "old\n")

    def test_check_rejects_missing_required_file(self):
        (self.package / "bin/fumetaos-doctor").unlink()
        result = self.check()
        self.assertEqual(result.returncode, 20, result.stderr)
        self.assertIn("bin/fumetaos-doctor", result.stderr)

    def test_check_rejects_different_linked_version(self):
        version = self.base / "VERSION"
        original = version.rename(self.base / "project-version")
        version.symlink_to(original)
        result = self.check()
        self.assertEqual(result.returncode, 20, result.stderr)
        self.assertIn("VERSION está enlazada", result.stderr)
        self.assertEqual(original.read_text(), "2.4.41\n")

    def test_check_rejects_linked_code_when_it_differs(self):
        destination = self.base / "bin"
        original = destination.rename(self.base / "project-bin")
        destination.symlink_to(original)
        result = self.check()
        self.assertEqual(result.returncode, 20, result.stderr)
        self.assertIn("directorio enlazado bin difiere", result.stderr)

    def test_copy_failure_leaves_all_active_directories_intact(self):
        result = self.run_script("""
source "$1"
TEMPORAL=$(mktemp -d "$BASE/.update.XXXXXXXX")
cp() {
    if [[ "${3##*/}" == core ]]; then return 73; fi
    command cp "$@"
}
preparar_directorios
sustituir_directorios
""")
        self.assertEqual(result.returncode, 20, result.stderr)
        for directory in DIRECTORIES:
            self.assertEqual((self.base / directory / "example").read_text(), "old\n")

    def test_exchange_failure_rolls_back_previous_directory(self):
        result = self.run_script("""
source "$1"
TEMPORAL=$(mktemp -d "$BASE/.update.XXXXXXXX")
cp -- "$TEST_EXCHANGE" "$TEMPORAL/package-path-exchange.py"
preparar_directorios
python3() {
    if [[ "${4##*/}" == core ]]; then return 74; fi
    command python3 "$@"
}
sustituir_directorios
""")
        self.assertEqual(result.returncode, 20, result.stderr)
        self.assertIn("Revirtiendo", result.stderr)
        for directory in DIRECTORIES:
            self.assertEqual((self.base / directory / "example").read_text(), "old\n")

    def prepare_backup_fixture(self):
        for name, contents in (
            ("bin/fumetaos", "programa\n"),
            ("core/common.sh", "biblioteca\n"),
            ("config/fumetaos.conf", "configuración de prueba\n"),
        ):
            path = self.base / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(contents)
        (self.base / "modules/enlace-interno").symlink_to("example")
        for name in (*DIRECTORIES, "VERSION"):
            original = self.base / name
            target = original.rename(self.base / f"project-{name}")
            original.symlink_to(target)

    def backup(self, fail_second_copy=False):
        mock = """
cp() {
    if [[ "$1" == -- ]]; then return 73; fi
    command cp "$@"
}
""" if fail_second_copy else ""
        return self.run_script("""
source "$1"
BACKUP_DIR="$BASE/backups-data"
SYSTEM_BACKUP_DIR="$BASE/backups-system"
TMPDIR="$BASE"
export TMPDIR
chown() { :; }
""" + mock + "\ncrear_backup\n")

    def test_update_backup_contains_link_targets_and_has_private_permissions(self):
        self.prepare_backup_fixture()
        result = self.backup()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        data, = (self.base / "backups-data").iterdir()
        system, = (self.base / "backups-system").iterdir()
        self.assertEqual(data.name, system.name)
        self.assertEqual(data.read_bytes(), system.read_bytes())
        for archive in (data, system):
            self.assertEqual(stat.S_IMODE(archive.stat().st_mode), 0o600)
        with tarfile.open(data) as archive:
            self.assertEqual(archive.extractfile("VERSION").read(), b"2.4.41\n")
            self.assertEqual(archive.extractfile("bin/fumetaos").read(), b"programa\n")
            self.assertEqual(archive.extractfile("core/common.sh").read(), b"biblioteca\n")
            self.assertTrue(archive.getmember("modules/enlace-interno").issym())
        self.assertEqual(list(self.base.glob("tmp.*")), [])

    def test_backup_failure_leaves_no_partial_archives(self):
        self.prepare_backup_fixture()
        result = self.backup(fail_second_copy=True)
        self.assertEqual(result.returncode, 73, result.stdout + result.stderr)
        for directory in ("backups-data", "backups-system"):
            self.assertEqual(list((self.base / directory).iterdir()), [])
        self.assertEqual(list(self.base.glob("tmp.*")), [])

    def test_installer_check_and_dry_run_accept_complete_package(self):
        for mode in ("--check", "--dry-run"):
            with self.subTest(mode=mode):
                result = self.run_script(f'bash "$TEST_BASE/install/install.sh" {mode}')
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertIn("Paquete 2.4.42 validado", result.stdout)
                self.assertFalse((self.base / "data").exists())

    def test_installer_modes_reject_missing_unit_before_system_changes(self):
        (self.package / "services/fumetaos-nightly.service").unlink()
        for mode in ("--check", "--dry-run", "--install"):
            with self.subTest(mode=mode):
                result = self.run_script(f"""
systemctl() {{
    printf "unexpected" > "$TEST_BASE/systemctl-called"
    return 99
}}
export -f systemctl
bash "$TEST_BASE/install/install.sh" {mode}
""")
                self.assertEqual(result.returncode, 20, result.stdout + result.stderr)
                self.assertIn("fumetaos-nightly.service", result.stderr)
                self.assertFalse((self.base / "systemctl-called").exists())
                self.assertFalse((self.base / "data").exists())
                self.assertEqual((self.base / "VERSION").read_text(), "2.4.41\n")

    def test_installer_backups_at_the_same_time_are_private_and_distinct(self):
        self.prepare_backup_fixture()
        apps = self.base / "apps"
        apps.mkdir()
        (apps / "example").write_text("app\n")
        result = self.run_script("""
source "$TEST_BASE/install/install.sh"
BACKUP_DIR="$BASE/backups-data"
date() { echo 2026-11-11_07-00-00; }
umask 022
crear_backup_previo
printf '%s\n' "nuevo" > "$BASE/config/fumetaos.conf"
crear_backup_previo
""")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        archives = list((self.base / "backups-data").iterdir())
        self.assertEqual(len(archives), 2)
        configurations = set()
        for path in archives:
            self.assertTrue(path.name.startswith("fumetaos-preinstall-2026-11-11_07-00-00."))
            self.assertEqual(stat.S_IMODE(path.stat().st_mode), 0o600)
            with tarfile.open(path) as archive:
                self.assertEqual(archive.extractfile("apps/example").read(), b"app\n")
                configurations.add(archive.extractfile("config/fumetaos.conf").read())
        self.assertEqual(configurations, {"configuración de prueba\n".encode(), b"nuevo\n"})
