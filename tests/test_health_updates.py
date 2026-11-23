import os
from pathlib import Path
import re
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
UPDATES = ('updates', 'jellyfin-update', 'transmission-update', 'filezilla-update',
           'adguard-update', 'casaos-update')


class HealthUpdateTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix='fumetaos-health-updates-')
        self.addCleanup(temporary.cleanup)
        self.base = Path(temporary.name)
        self.module_dir = self.base / 'modules/monitor'
        self.module_dir.mkdir(parents=True)
        (self.base / 'bin').mkdir()
        (self.base / 'core').mkdir()
        (self.base / 'tmp').mkdir()
        (self.base / 'started').mkdir()
        (self.base / 'VERSION').write_text('2.4.59\n')
        (self.base / 'core/common.sh').write_text(f'VERSION_FILE="{self.base}/VERSION"\n')
        source = (ROOT / 'bin/fumetaos-health').read_text()
        for name in set(re.findall(r'/opt/fumetaos/modules/monitor/([a-z-]+)\.sh', source)):
            self.stub(name, '#!/bin/bash\nexit 0\n')
        self.script = self.base / 'bin/fumetaos-health'
        self.script.write_text(source.replace('/opt/fumetaos', str(self.base)))
        self.env = dict(os.environ, TMPDIR=str(self.base / 'tmp'),
                        TEST_STARTED=str(self.base / 'started'))

    def stub(self, name, content):
        path = self.module_dir / f'{name}.sh'
        path.write_text(content)
        path.chmod(0o755)

    def run_health(self, statuses):
        for index, (name, status) in enumerate(zip(UPDATES, statuses)):
            self.stub(name, f'''#!/usr/bin/env python3
import os
from pathlib import Path
import sys
import time
folder = Path(os.environ['TEST_STARTED'])
(folder / '{index}').touch()
deadline = time.monotonic() + 3
while len(list(folder.iterdir())) < 6:
    if time.monotonic() >= deadline:
        print('Update checks did not overlap', file=sys.stderr)
        sys.exit(99)
    time.sleep(0.01)
print('check-{index}')
print('diagnostic-{index}', file=sys.stderr)
sys.exit({status})
''')
        result = subprocess.run(['bash', str(self.script)], env=self.env,
                                capture_output=True, text=True, timeout=6)
        self.assertEqual(list((self.base / 'tmp').iterdir()), [])
        self.assertEqual([line for line in result.stdout.splitlines() if line.startswith('check-')],
                         [f'check-{i}' for i in range(6)])
        self.assertEqual(result.stderr.splitlines(), [f'diagnostic-{i}' for i in range(6)])
        return result

    def test_queries_overlap_preserve_order_and_critical_status(self):
        result = self.run_health([0, 10, 0, 20, 0, 0])
        self.assertEqual(result.returncode, 20, result.stdout + result.stderr)
        self.assertIn('Estado general: REVISAR', result.stdout)

    def test_queries_preserve_warning_status(self):
        result = self.run_health([0, 0, 10, 0, 0, 0])
        self.assertEqual(result.returncode, 10, result.stdout + result.stderr)
        self.assertIn('Estado general: AVISOS', result.stdout)

    def test_queries_preserve_success_status(self):
        result = self.run_health([0, 0, 0, 0, 0, 0])
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('Estado general: PERFECTO', result.stdout)

    def test_missing_temporary_directory_is_reported(self):
        self.env['TMPDIR'] = str(self.base / 'does-not-exist')
        result = subprocess.run(['bash', str(self.script)], env=self.env,
                                capture_output=True, text=True, timeout=5)
        self.assertEqual(result.returncode, 20, result.stdout + result.stderr)
        self.assertIn('No se pudo preparar la consulta de actualizaciones', result.stderr)


    def test_cancelled_queries_remove_their_temporary_directory(self):
        import signal
        import time
        for index, name in enumerate(UPDATES):
            self.stub(name, f'''#!/usr/bin/env python3
import os
from pathlib import Path
import time
(Path(os.environ['TEST_STARTED']) / '{index}').touch()
while True:
    time.sleep(1)
''')
        process = subprocess.Popen(['bash', str(self.script)], env=self.env,
                                   stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                   text=True, start_new_session=True)
        try:
            deadline = time.monotonic() + 3
            while len(list((self.base / 'started').iterdir())) < 6:
                self.assertLess(time.monotonic(), deadline)
                time.sleep(0.01)
            os.killpg(process.pid, signal.SIGTERM)
            process.communicate(timeout=5)
            self.assertNotEqual(process.returncode, 0)
            self.assertEqual(list((self.base / 'tmp').iterdir()), [])
        finally:
            try:
                os.killpg(process.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            process.communicate(timeout=5)



if __name__ == '__main__':
    unittest.main()
