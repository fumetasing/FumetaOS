import os
from pathlib import Path
import subprocess
import tempfile
import unittest

BUILDER = Path(__file__).resolve().parents[1] / "bin/fumetaos-build"
DIRECTORIES = ("bin", "core", "modules", "apps", "config", "services", "sudoers")

SUDO = """#!/bin/bash
set -e
case "$1" in
    visudo|chown) exit 0 ;;
    cp)
        if [[ "${FAIL_STEP:-}" == copy && "$2" == -r ]]; then
            exit 73
        fi
        ;;
    python3)
        if [[ "${FAIL_STEP:-}" == publish ]]; then
            exit 74
        fi
        ;;
    install)
        shift
        args=()
        while (( $# )); do
            case "$1" in
                -o|-g) shift 2 ;;
                *) args+=("$1"); shift ;;
            esac
        done
        exec install "${args[@]}"
        ;;
esac
exec "$@"
"""


class PackageBuilderTests(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory(prefix="fumetaos-package-test-")
        self.addCleanup(temp.cleanup)
        self.root = Path(temp.name)
        self.source = self.root / "source"
        self.package = self.root / "install/package"
        self.tools = self.root / "tools"
        self.tools.mkdir()
        sudo = self.tools / "sudo"
        sudo.write_text(SUDO)
        sudo.chmod(0o755)
        for directory in (*DIRECTORIES, "install"):
            (self.source / directory).mkdir(parents=True)
        (self.source / "bin/fumetaos").write_text("nuevo\n")
        (self.source / "sudoers/example").touch()
        (self.source / "VERSION").write_text("2.4.41\n")
        (self.source / "core/package-path-exchange.py").write_bytes(
            (BUILDER.parent.parent / "core/package-path-exchange.py").read_bytes()
        )
        for name in ("install.sh", "update.sh"):
            (self.source / "install" / name).write_text("#!/bin/bash\n")
        script = BUILDER.read_text()
        destination = 'PACKAGE="/opt/fumetaos/install/package"'
        self.assertEqual(script.count(destination), 1)
        self.builder = self.source / "bin/fumetaos-build"
        self.builder.write_text(script.replace(destination, 'PACKAGE="$TEST_PACKAGE"'))

    def old_package(self):
        (self.package / "bin").mkdir(parents=True)
        (self.package / "bin/fumetaos").write_text("anterior\n")
        (self.package / "bin/obsoleto").touch()
        (self.package / "VERSION").write_text("2.4.40\n")
        (self.package / "docs").mkdir()
        (self.package / "docs/referencia.md").write_text("conservar\n")

    def build(self, failure=""):
        result = subprocess.run(
            ["bash", str(self.builder)],
            env=dict(
                os.environ, PATH=f"{self.tools}:{os.environ['PATH']}",
                TEST_PACKAGE=str(self.package), FAIL_STEP=failure,
            ),
            capture_output=True, text=True, timeout=10,
        )
        self.assertEqual(list(self.package.parent.glob(".package-build.*")), [])
        return result

    def test_first_build_publishes_complete_package(self):
        result = self.build()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual((self.package / "VERSION").read_text(), "2.4.41\n")
        self.assertTrue((self.package / "install/update.sh").is_file())
        self.assertTrue(all((self.package / name).is_dir() for name in DIRECTORIES))

    def test_rebuild_replaces_managed_files_and_preserves_other_files(self):
        self.old_package()
        result = self.build()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual((self.package / "bin/fumetaos").read_text(), "nuevo\n")
        self.assertFalse((self.package / "bin/obsoleto").exists())
        self.assertEqual((self.package / "docs/referencia.md").read_text(), "conservar\n")

    def test_copy_or_publication_failure_preserves_old_package(self):
        self.old_package()
        for failure, expected in (("copy", 73), ("publish", 74)):
            with self.subTest(failure=failure):
                result = self.build(failure)
                self.assertEqual(result.returncode, expected, result.stdout + result.stderr)
                self.assertEqual((self.package / "bin/fumetaos").read_text(), "anterior\n")
                self.assertEqual((self.package / "VERSION").read_text(), "2.4.40\n")
