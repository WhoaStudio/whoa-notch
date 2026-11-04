2026-10-31: Approved purple hexagonal chest reference; keep native 18pt template status item wiring and named SVG groups.
2026-10-31: Menu icon stays closed at rest, lifts its lid while native menu opens, closes on dismissal; 180ms ease-out, template tint and Reduce Motion preserved.
2026-10-31: Launch greeting uses the full-colour chest in the notch left wing for 3.4s; finite blinking/gaze/head tilt, yields to notifications and expansion, respects Reduce Motion and overlay animation setting.
2026-11-03: DMG presentation uses built-in hdiutil + Finder scripting, a black/purple pixel background at @1x/@2x combined as Retina TIFF, and a real Applications symlink. Packaging accepts a prepared app and must not change build, signing or notarization; intended for GitHub Releases and Homebrew.

2026-11-04: Release automation uses in-repo Casks/, a universal shared DMG build, guarded atomic release push, and tag/manual Actions. Six standard optional Developer ID/notary secrets; missing credentials produce explicit unsigned/unnotarized notes. Manual retries identify their own annotated run tag; published artifacts remain immutable and cask updates never downgrade.
