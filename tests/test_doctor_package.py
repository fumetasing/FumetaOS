import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

DOCTOR = Path(__file__).resolve().parents[1] / "bin/fumetaos-doctor"

COMMON = """FUMETAOS_HOME="$TEST_ROOT"
BIN_DIR="$TEST_ROOT/bin"
CORE_DIR="$TEST_ROOT/core"
MODULES_DIR="$TEST_ROOT/modules"
INSTALL_DIR="$TEST_ROOT/install"
CONFIG_FILE="$TEST_ROOT/config.conf"
VERSION_FILE="$TEST_ROOT/VERSION"
DATA_DIR="$TEST_ROOT/data"
TELEGRAM_TOKEN=mock
SSD_DEVICE=mock
HDD_DEVICE=mock
FUMETAOS_TIMERS=
sudo() { return 1; }
systemctl() { return 1; }
find() { return 1; }
"""

class DoctorPackageTests(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory(prefix="fumetaos-doctor-test-")
        self.addCleanup(temp.cleanup)
        self.root = Path(temp.name)
        self.package = self.root / "install/package"
        self.package.mkdir(parents=True)
        for directory in ("bin", "core", "modules/monitor"):
            (self.root / directory).mkdir(parents=True)
        for directory in ("services", "sudoers"):
            (self.package / directory).mkdir()
        shutil.copy2(DOCTOR, self.root / "bin")
        (self.root / "core/common.sh").write_text(COMMON)
        (self.root / "core/apps.sh").write_text("app_list() { :; }\n")
        (self.root / "modules/monitor/backups.sh").write_text("exit 0\n")
        for directory in ("bin", "core", "modules"):
            shutil.copytree(self.root / directory, self.package / directory)
        for directory in (self.root, self.package):
            (directory / "VERSION").write_text("2.4.41\n")

    def doctor_report(self):
        result = subprocess.run(
            ["bash", str(self.root / "bin/fumetaos-doctor")],
            env=dict(os.environ, TEST_ROOT=str(self.root)),
            capture_output=True, text=True, timeout=5,
        )
        # Other Doctor checks deliberately fail in the simulated installation.
        self.assertEqual(result.returncode, 20, result.stderr)
        return result.stdout

    def package_report(self):
        report = self.doctor_report()
        self.assertIn("📦 Paquete", report)
        return report.split("📦 Paquete", 1)[1].split("💾 Datos", 1)[0]

    def test_matching_version_and_directories_pass(self):
        report = self.package_report()
        self.assertIn("✅ Versión del paquete coincide con la instalación", report)
        for directory in ("bin", "core", "modules"):
            self.assertIn(f"✅ Paquete {directory} sincronizado", report)

    def test_old_package_version_fails_with_matching_scripts(self):
        (self.package / "VERSION").write_text("2.4.40\n")
        report = self.package_report()
        self.assertIn("❌ Versión del paquete coincide con la instalación", report)
        self.assertIn("✅ Paquete bin sincronizado", report)

    def test_changed_script_fails_with_matching_version(self):
        (self.package / "bin/fumetaos-doctor").write_text("# Versión anterior\n")
        report = self.package_report()
        self.assertIn("✅ Versión del paquete coincide con la instalación", report)
        self.assertIn("❌ Paquete bin sincronizado", report)
        self.assertIn("fumetaos-doctor", report)

    def test_missing_module_fails_with_matching_version(self):
        (self.package / "modules/monitor/backups.sh").unlink()
        report = self.package_report()
        self.assertIn("✅ Versión del paquete coincide con la instalación", report)
        self.assertIn("❌ Paquete modules sincronizado", report)
        self.assertIn("backups.sh", report)

    def test_doctor_flags_configuration_readable_by_other_users(self):
        config = self.root / "config.conf"
        config.write_text("# configuración de prueba\n")
        config.chmod(0o644)
        self.assertIn("❌ Configuración privada legible", self.doctor_report())
        config.chmod(0o600)
        self.assertIn("✅ Configuración privada legible", self.doctor_report())

    def test_doctor_checks_optional_packaged_configuration(self):
        self.assertNotIn("Configuración privada del paquete", self.package_report())
        config = self.package / "config/fumetaos.conf"
        config.parent.mkdir()
        config.write_text("# configuración de prueba\n")
        config.chmod(0o644)
        self.assertIn("❌ Configuración privada del paquete", self.package_report())
        config.chmod(0o640)
        self.assertIn("✅ Configuración privada del paquete", self.package_report())
