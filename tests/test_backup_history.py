import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
MONITOR = ROOT / "modules/monitor/backups.sh"
NOW = 1_800_000_000
HOUR = 3600

TIMEOUT = """#!/bin/bash
shift
case "$1" in
  systemctl)
    if [[ "$3" == *.timer ]]; then
      printf '%s\\n' ActiveState=active 'NextElapseUSecRealtime=mañana'
    else
      printf '%s\\n' LoadState=loaded ActiveState=inactive Result=success
    fi
    ;;
  journalctl)
    if [[ "$*" == *"UNIT=$FAILED_JOURNAL_UNIT "* ]]; then
      exit 1
    fi
    if [[ "$*" == *MESSAGE_ID=39f53479d3a045ac8e11786248231fbf* ]]; then
      age=$DAILY_AGE
      if [[ "$*" == *UNIT=fumetaos-recovery-verify.service* ]]; then
        age=$VERIFY_AGE
      fi
      printf '%s.000000\\n' "$((TEST_NOW - age))"
    fi
    ;;
  *)
    printf '%s\\n' "$*" >> "$UNEXPECTED_CALLS"
    exit 99
    ;;
esac
"""

class BackupHistoryTests(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory(prefix="fumetaos-backup-history-")
        self.addCleanup(temp.cleanup)
        self.root = Path(temp.name)
        self.unexpected = self.root / "unexpected"

        self.stub("timeout", TIMEOUT)
        self.stub("date", """#!/bin/bash
if [[ "$1" == +%s ]]; then
  printf '%s\\n' "$TEST_NOW"
else
  printf '%s\\n' 'Fecha simulada'
fi
""")
        for program in ("ssh", "ip", "python3", "sleep"):
            self.stub(program, """#!/bin/bash
printf '%s\\n' "$0" >> "$UNEXPECTED_CALLS"
exit 99
""")

    def stub(self, name, content):
        path = self.root / name
        path.write_text(content)
        path.chmod(0o755)

    def history(self, daily_age=HOUR, verify_age=HOUR, failed_journal_unit=""):
        env = dict(
            os.environ,
            PATH=f"{self.root}:{os.environ['PATH']}",
            TEST_NOW=str(NOW),
            DAILY_AGE=str(daily_age),
            VERIFY_AGE=str(verify_age),
            FAILED_JOURNAL_UNIT=failed_journal_unit,
            UNEXPECTED_CALLS=str(self.unexpected),
        )
        result = subprocess.run(
            ["bash", str(MONITOR), "--solo-historial"],
            capture_output=True, text=True, env=env, timeout=5,
        )
        self.assertFalse(self.unexpected.exists(), result.stdout + result.stderr)
        self.assertNotIn("USB del Mac", result.stdout)
        return result

    def test_recent_backups_and_verification_are_current(self):
        result = self.history()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("✅ Copia local", result.stdout)
        self.assertIn("✅ Espejo general al Mac", result.stdout)
        self.assertIn("✅ Verificación cifrada", result.stdout)

    def test_daily_backups_and_weekly_verification_use_different_limits(self):
        result = self.history(daily_age=31 * HOUR, verify_age=31 * HOUR)
        self.assertEqual(result.returncode, 20, result.stdout + result.stderr)
        self.assertIn("🔴 Copia local", result.stdout)
        self.assertIn("🔴 Espejo general al Mac", result.stdout)
        self.assertIn("límite 30 h", result.stdout)
        self.assertIn("✅ Verificación cifrada", result.stdout)

    def test_old_verification_is_reported_even_with_recent_daily_backups(self):
        result = self.history(verify_age=193 * HOUR)
        self.assertEqual(result.returncode, 20, result.stdout + result.stderr)
        self.assertIn("✅ Copia local", result.stdout)
        self.assertIn("🔴 Verificación cifrada", result.stdout)
        self.assertIn("límite 192 h", result.stdout)

    def test_unavailable_journal_is_reported_as_unconfirmed(self):
        result = self.history(failed_journal_unit="fumetaos-mac-backup.service")
        self.assertEqual(result.returncode, 10, result.stdout + result.stderr)
        self.assertIn("🟡 Espejo general al Mac", result.stdout)
        self.assertIn("estado no confirmado", result.stdout)
