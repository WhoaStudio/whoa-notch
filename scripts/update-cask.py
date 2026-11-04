#!/usr/bin/env python3
"""Met à jour le cask avec le condensat du DMG final."""
import hashlib
import pathlib
import re
import subprocess
import sys

version, dmg = sys.argv[1:]
subprocess.run([sys.executable, "scripts/release-version.py", version], check=True)
checksum = hashlib.sha256(pathlib.Path(dmg).read_bytes()).hexdigest()
cask = pathlib.Path("Casks/whoa-stash.rb")
text = cask.read_text()
current = re.search(r'^  version "([^"]+)"$', text, re.M)
if current is None:
    sys.exit("Cask inattendu : version absente.")
def numeric(value):
    parts = [int(part) for part in value.split(".")]
    return tuple(parts + [0] * (3 - len(parts)))
if numeric(version) < numeric(current[1]):
    print("Cask conservé : une version plus récente est déjà disponible.")
    sys.exit(0)
for key, value in (("version", version), ("sha256", checksum)):
    text, count = re.subn(rf'^  {key} "[^"]+"$', f'  {key} "{value}"', text, flags=re.M)
    if count != 1:
        sys.exit(f"Cask inattendu : {key} absent ou dupliqué.")
cask.write_text(text)
