#!/usr/bin/env python3
"""Vérifie les refus de publication sans jamais pousser."""
import pathlib
import shutil
import subprocess
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]


class ReleaseTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.repo = pathlib.Path(self.temp.name) / "checkout"
        self.repo.mkdir()
        shutil.copytree(ROOT / "scripts", self.repo / "scripts")
        (self.repo / "whoa-notch.xcodeproj").mkdir()
        shutil.copy(ROOT / "whoa-notch.xcodeproj/project.pbxproj",
                    self.repo / "whoa-notch.xcodeproj/project.pbxproj")
        self.git("init", "-b", "stable")
        self.git("config", "core.hooksPath", "/dev/null")
        self.git("config", "commit.gpgsign", "false")
        self.git("config", "user.email", "test@example.invalid")
        self.git("config", "user.name", "Test")
        self.git("add", ".")
        self.git("commit", "-m", "fixture")
        remote = pathlib.Path(self.temp.name) / "remote.git"
        self.git("clone", "--bare", str(self.repo), str(remote))
        self.git("remote", "add", "origin", str(remote))
        # Même un appel accidentel à push échoue avant tout transfert.
        hook = pathlib.Path(self.temp.name) / "hooks/pre-push"
        hook.parent.mkdir()
        hook.write_text("#!/bin/sh\nexit 99\n")
        hook.chmod(0o755)
        self.git("config", "core.hooksPath", str(hook.parent))
        # Les tests de refus précoces ne consultent pas le remote.

    def git(self, *args):
        return subprocess.run(["git", *args], cwd=self.repo, check=True,
                              capture_output=True, text=True).stdout

    def refuse(self, expected, version="1.2"):
        before = self.git("rev-parse", "HEAD")
        tags_before = self.git("tag", "--list")
        result = subprocess.run(["scripts/release.sh", version], cwd=self.repo,
                                capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn(expected, result.stderr)
        self.assertEqual(before, self.git("rev-parse", "HEAD"))
        self.assertEqual(self.git("tag", "--list"), tags_before)

    def test_refuse_hors_stable(self):
        self.git("switch", "-c", "feature")
        self.refuse("branche courante doit être stable")

    def test_refuse_arbre_sale(self):
        (self.repo / "untracked").touch()
        self.refuse("working tree is dirty")

    def test_refuse_modification_indexee(self):
        (self.repo / "tracked").touch()
        self.git("add", "tracked")
        self.refuse("working tree is dirty")

    def test_refuse_tag_existant(self):
        self.git("tag", "v1.2")
        self.refuse("Le tag v1.2 existe déjà")

    def test_refuse_branche_en_avance(self):
        self.git("commit", "--allow-empty", "-m", "local-only")
        self.refuse("stable doit être à jour")

    def test_version_modifie_uniquement_les_metadonnees(self):
        project = self.repo / "whoa-notch.xcodeproj/project.pbxproj"
        original = project.read_text()
        subprocess.run(["python3", "scripts/release-version.py", "1.2", str(project)],
                       cwd=self.repo, check=True)
        expected = original.replace("MARKETING_VERSION = 1.0;", "MARKETING_VERSION = 1.2;")
        expected = expected.replace("CURRENT_PROJECT_VERSION = 1;", "CURRENT_PROJECT_VERSION = 1.2;")
        self.assertEqual(project.read_text(), expected)

    def test_cask_verifie_condensat_et_refuse_retour_arriere(self):
        import hashlib
        cask = self.repo / "Casks/whoa-notch.rb"
        cask.parent.mkdir()
        cask.write_text('  version "1"\n  sha256 "initial"\n')
        dmg = self.repo / "fixture.dmg"
        dmg.write_bytes(b"DMG fixture")
        subprocess.run(["python3", "scripts/update-cask.py", "1.2", str(dmg)],
                       cwd=self.repo, check=True)
        expected = cask.read_text()
        self.assertIn('version "1.2"', expected)
        self.assertIn(hashlib.sha256(dmg.read_bytes()).hexdigest(), expected)
        subprocess.run(["python3", "scripts/update-cask.py", "1.1", str(dmg)],
                       cwd=self.repo, check=True, capture_output=True)
        self.assertEqual(cask.read_text(), expected)

    def test_refuse_version_invalide(self):
        for version in ("v1", "1.2.3.4", "1-beta", "01.2", "1;echo secret"):
            with self.subTest(version=version):
                self.refuse("Version invalide", version)


if __name__ == "__main__":
    unittest.main()
