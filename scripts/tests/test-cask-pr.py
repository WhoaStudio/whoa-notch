#!/usr/bin/env python3
"""Vérifie la publication du cask dans une PR avec un remote local."""
import hashlib
import os
import pathlib
import shutil
import subprocess
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]


class CaskPRTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.work = pathlib.Path(self.temp.name)
        self.repo = self.work / "checkout"
        (self.repo / "scripts").mkdir(parents=True)
        (self.repo / "Casks").mkdir()
        self.cask = self.repo / "Casks/whoa-notch.rb"
        self.cask.write_text('  version "1"\n  sha256 "initial"\n')
        for name in ("open-cask-pr.sh", "release-version.py", "update-cask.py"):
            shutil.copy(ROOT / "scripts" / name, self.repo / "scripts" / name)
        self.script(self.repo / "scripts/check-cask.sh", 'exit "${AUDIT_STATUS:-0}"\n')
        self.bin = self.work / "bin"
        self.bin.mkdir()
        self.script(self.bin / "gh", '''printf '%s\\n' "$*" >> "$CALLS"
if [[ "$1 $2" == 'pr list' ]]; then
  printf '%s' "${EXISTING_PR:-}"
elif [[ "$1 $2" == 'pr create' ]]; then
  echo 'https://example.invalid/pull/1'
else
  exit 90
fi
''')
        self.calls = self.work / "calls"
        self.calls.touch()
        self.env = dict(os.environ, PATH=f"{self.bin}:{os.environ['PATH']}",
                        CALLS=str(self.calls))
        self.git("init", "-b", "stable")
        self.git("config", "core.hooksPath", "/dev/null")
        self.git("config", "commit.gpgsign", "false")
        self.git("config", "user.email", "test@example.invalid")
        self.git("config", "user.name", "Test")
        self.git("add", ".")
        self.git("commit", "-m", "fixture")
        self.initial = self.git("rev-parse", "HEAD").strip()
        self.remote = self.work / "remote.git"
        self.git("clone", "--bare", str(self.repo), str(self.remote))
        self.git("remote", "add", "origin", str(self.remote))
        self.dmg = self.work / "fixture.dmg"
        self.dmg.write_bytes(b"published DMG")

    def script(self, path, body):
        path.write_text("#!/bin/bash\nset -euo pipefail\n" + body)
        path.chmod(0o755)

    def git(self, *args):
        return subprocess.run(["git", *args], cwd=self.repo, check=True,
                              capture_output=True, text=True).stdout

    def run_script(self, version="1.2", **env):
        return subprocess.run(["scripts/open-cask-pr.sh", version, str(self.dmg)],
                              cwd=self.repo, env=dict(self.env, **env),
                              capture_output=True, text=True)

    def assert_stable_unchanged(self):
        self.assertEqual(self.git("--git-dir", str(self.remote), "rev-parse", "stable").strip(),
                         self.initial)

    def test_pousse_branche_et_ouvre_pr_sans_modifier_stable(self):
        result = self.run_script()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("pr create --base stable --head codex/cask-v1.2", self.calls.read_text())
        remote_cask = self.git("--git-dir", str(self.remote), "show",
                               "codex/cask-v1.2:Casks/whoa-notch.rb")
        self.assertIn('version "1.2"', remote_cask)
        self.assertIn(hashlib.sha256(self.dmg.read_bytes()).hexdigest(), remote_cask)
        self.assert_stable_unchanged()

    def test_relance_reutilise_branche_et_pr(self):
        self.assertEqual(self.run_script().returncode, 0)
        self.git("switch", "stable")
        self.git("branch", "-D", "codex/cask-v1.2")
        self.calls.write_text("")
        result = self.run_script(EXISTING_PR="https://example.invalid/pull/1")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn("pr create", self.calls.read_text())
        self.assertIn("PR mise à jour", result.stdout)
        self.assert_stable_unchanged()

    def test_audit_en_echec_ne_pousse_pas(self):
        result = self.run_script(AUDIT_STATUS="1")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.calls.read_text(), "")
        self.assertEqual(self.git("branch", "--list", "codex/cask-v1.2"), "")
        self.assert_stable_unchanged()

    def test_version_ancienne_ne_cree_pas_de_pr(self):
        result = self.run_script("0.9")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.calls.read_text(), "")
        self.assert_stable_unchanged()


if __name__ == "__main__":
    unittest.main()
