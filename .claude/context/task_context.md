# Task context

## Goal

Détection de coups sur le châssis (accéléromètre SPU) : coup simple = écran éteint par défaut, double coup réglable, volet Préférences > Knock.

## Status

- Implémenté : `Features/Knock/`, `Core/Settings/KnockSettings.swift`, volet `KnockSettingsViewController`. Build OK, 135 tests OK (`KnockClassifierTests` sur échantillons simulés et sur extraits réels de `KnockRecordings`, `KnockSettingsStorageTests`). Commits : voir `git log --grep=knock`.
- Pas vérifié en conditions réelles : l'app complète avec le capteur (lancer sans `--knock=` éteint l'écran au premier coup), faux déclenchements en usage normal (bureau qui bouge, haut-parleurs).
- Gauche/droite : non exposé, voir `conversation_memory.md`.

## Open questions

- Gyroscope (autre device SPU) non enregistré pour le gauche/droite.

Release CI fix pushed from isolated worktree /private/tmp/whoa-stash-release-fix.cfdFzt, branch codex/fix-release-cask-pr. Commits 6e5e5d1 (reusable cask PR workflow, recovery dispatch, helper, 4 tests/docs) and 428deb9 (repair v1.0 cask from published DMG SHA256 c4fcade1239bd4df46dbbdb4f04f2626541d18deaceaed98057671d5faea25ee). Twelve local tests, actionlint, ShellCheck and Homebrew audit/style passed; reviewer had no material findings. Unrelated edits/staging in original stable checkout preserved. Stable protection/review unchanged. Version metadata push still requires an authorized release caller; cask changes now use PRs. GitHub connector needs reauthentication; gh CLI remains authenticated.
