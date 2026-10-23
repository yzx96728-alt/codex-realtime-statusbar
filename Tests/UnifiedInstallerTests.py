"""Exercise the shipped transaction with a real signed app in isolated paths.
No real application is stopped/launched and no login item or TCC state is changed.
Usage: python3 Tests/UnifiedInstallerTests.py /absolute/path/to/staged/package
"""
from pathlib import Path
import hashlib
import os
import shutil
import subprocess
import sys
import tempfile
import unittest

PAYLOAD = Path(sys.argv.pop(1)).resolve()
APP = 'Codex实时状态栏.app'


class UnifiedInstallerTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='unified install spaces ')
        self.root = Path(self.temp.name)
        self.source = self.root / 'download with spaces'
        shutil.copytree(PAYLOAD, self.source)
        self.user = self.root / 'test user'
        self.destination = self.user / 'Applications' / APP

    def tearDown(self):
        self.temp.cleanup()

    def run_install(self, *args, answer='y\n\n'):
        return subprocess.run(['/bin/bash', str(self.source / '安装或升级.command'),
                               '--user-home', str(self.user), '--destination', str(self.destination),
                               '--no-launch', *args], input=answer, text=True, capture_output=True)

    def test_new_install_identical_skill_and_repeat_upgrade(self):
        first = self.run_install()
        self.assertEqual(first.returncode, 0, first.stdout + first.stderr)
        subprocess.run(['codesign', '--verify', '--deep', '--strict', str(self.destination)], check=True)
        installed = (self.destination / 'Contents/MacOS/CCUsage').read_bytes()
        second = self.run_install('--existing-app', str(self.destination))
        self.assertEqual(second.returncode, 0, second.stdout + second.stderr)
        self.assertIn('skipped', second.stdout)
        self.assertEqual(installed, (self.destination / 'Contents/MacOS/CCUsage').read_bytes())
        self.assertEqual(len(list((self.user / 'Library/Application Support/CodexRealtimeStatusbar/Backups').glob('*/previous.app'))), 1)
        self.assertFalse((self.user / '.codex/config.toml').exists())
        self.assertFalse((self.user / '.codex-handoff-backups').exists())

    def test_existing_install_lock_blocks_replacement(self):
        old = self.user / 'old app' / APP
        shutil.copytree(self.source / APP, old)
        lock = self.user / 'Library/Application Support/CodexRealtimeStatusbar/install.lock'
        lock.mkdir(parents=True)
        result = self.run_install('--existing-app', str(old))
        self.assertNotEqual(result.returncode, 0)
        self.assertTrue(old.exists())
        self.assertTrue(lock.exists())
        self.assertFalse(self.destination.exists())

    def test_cancel_makes_no_install(self):
        result = self.run_install(answer='n\n')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(self.user.exists())

    def test_tampered_payload_rejected_before_mutation(self):
        (self.source / 'skills/handoff/SKILL.md').write_text('tampered')
        result = self.run_install()
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(self.user.exists())

    def test_existing_arbitrary_location_migrated_and_backed_up(self):
        old = self.user / 'old app location' / APP
        shutil.copytree(self.source / APP, old)
        result = self.run_install('--existing-app', str(old))
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertFalse(old.exists())
        backups = list((self.user / 'Library/Application Support/CodexRealtimeStatusbar/Backups').glob('*/previous.app'))
        self.assertEqual(len(backups), 1)
        self.assertEqual((backups[0] / 'Contents/Info.plist').read_bytes(), (self.destination / 'Contents/Info.plist').read_bytes())

    def test_duplicate_skills_pause_only_skill_update(self):
        for base in ('.agents/skills/handoff', '.codex/skills/another-name'):
            shutil.copytree(self.source / 'skills/handoff', self.user / base)
        result = self.run_install()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('skill update paused/failed', result.stderr)
        self.assertTrue(self.destination.exists())
        self.assertTrue((self.user / '.codex/skills/another-name/SKILL.md').exists())

    def test_replacement_failure_restores_old_app(self):
        old = self.user / 'legacy app' / APP
        shutil.copytree(self.source / APP, old)
        # A destination whose final component is too long passes preflight but
        # causes the final rename to fail after the original was backed up/moved.
        self.destination = self.user / 'Applications' / ('x' * 256 + '.app')
        result = self.run_install('--existing-app', str(old))
        self.assertNotEqual(result.returncode, 0)
        self.assertTrue(old.exists(), result.stdout + result.stderr)
        subprocess.run(['codesign', '--verify', '--strict', str(old)], check=True)
        self.assertEqual(len(list((self.user / 'Library/Application Support/CodexRealtimeStatusbar/Backups').glob('*/previous.app'))), 1)


if __name__ == '__main__':
    unittest.main()
