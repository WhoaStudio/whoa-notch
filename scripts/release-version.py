#!/usr/bin/env python3
"""Valide une version et met à jour les métadonnées Xcode."""
import pathlib
import re
import sys

version = sys.argv[1] if len(sys.argv) > 1 else ""
if not re.fullmatch(r"(?:0|[1-9][0-9]{0,3})(?:\.(?:0|[1-9][0-9]{0,3})){0,2}", version):
    sys.exit("Version invalide : utilisez 1, 1.2 ou 1.2.3 (sans préfixe v).")
if len(sys.argv) == 3:
    project = pathlib.Path(sys.argv[2])
    text = project.read_text()
    for setting in ("MARKETING_VERSION", "CURRENT_PROJECT_VERSION"):
        text, count = re.subn(rf"({setting} = )[^;]+;", rf"\g<1>{version};", text)
        if count != 4:
            sys.exit(f"Configuration inattendue : {count} valeurs pour {setting}.")
    project.write_text(text)
