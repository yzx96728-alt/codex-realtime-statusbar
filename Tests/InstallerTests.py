"""Run the real installer in isolated user directories, never the user's HOME."""
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
INSTALLER = ROOT / "安装交接技能.command"
SOURCE = ROOT / "skills/handoff"


class InstallerTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="handoff install test ")
        self.directory = Path(self.temporary.name)
        self.user = self.directory / "user with spaces"

    def tearDown(self):
        self.temporary.cleanup()

    def run_install(self, *args, answer=""):
        return subprocess.run(["/bin/bash", str(INSTALLER), "--user-home", str(self.user), *args],
                              input=answer, text=True, capture_output=True)

    def existing(self, base, folder="handoff"):
        target = self.user / base / folder
        shutil.copytree(SOURCE, target)
        (target / "local-only.txt").write_text("old personal setting")
        return target

    def test_new_install_and_spaces(self):
        result = self.run_install()
        self.assertEqual(result.returncode, 0, result.stderr)
        target = self.user / ".agents/skills/handoff"
        self.assertEqual((target / "SKILL.md").read_bytes(), (SOURCE / "SKILL.md").read_bytes())
        self.assertFalse((self.user / ".codex").exists())

    def test_cancel_and_eof_preserve_existing(self):
        target = self.existing(".codex/skills")
        for answer in ("n\n", ""):
            result = self.run_install(answer=answer)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertTrue((target / "local-only.txt").exists())
        self.assertFalse((self.user / ".codex-handoff-backups").exists())

    def test_confirmed_replace_backs_up_outside_discovery(self):
        target = self.existing(".codex/skills")
        result = self.run_install(answer="y\n")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse((target / "local-only.txt").exists())
        backups = list((self.user / ".codex-handoff-backups").glob("*/handoff/local-only.txt"))
        self.assertEqual(len(backups), 1)
        self.assertEqual(backups[0].read_text(), "old personal setting")
        self.assertFalse((self.user / ".agents/skills/handoff").exists())
        self.assertFalse((self.user / ".codex/hooks.json").exists())
        self.assertFalse((self.user / ".codex/config.toml").exists())

    def test_explicit_replace(self):
        target = self.existing(".agents/skills")
        result = self.run_install("--replace")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse((target / "local-only.txt").exists())

    def test_duplicate_declared_names_stop_without_changes(self):
        first = self.existing(".agents/skills")
        second = self.existing(".codex/skills", "renamed-folder")
        result = self.run_install("--replace")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn(str(first), result.stderr)
        self.assertIn(str(second), result.stderr)
        self.assertTrue((first / "local-only.txt").exists())
        self.assertTrue((second / "local-only.txt").exists())
        self.assertFalse((self.user / ".codex-handoff-backups").exists())


if __name__ == "__main__":
    unittest.main()
