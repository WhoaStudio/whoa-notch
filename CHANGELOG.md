# Changelog

All notable changes to Whoa Notch are listed here. Versions follow the Git tags (`v1.0`, `v1.0.1`, …).

## [1.0.1] - Unreleased

### Added

- Analytics tab: usage comparison across Claude, Codex and Copilot, a pace gauge, and loading and error states with Retry.
- AI tab: parallel agent sessions, steering a running session, and optional replies after a turn (Preferences ▸ AI ▸ Replies).
- Color tab: HEX/RGB/HSL formats, Recent and Saved swatches, drag and drop, brightness and hue on scroll.
- Clipboard tab: previews for text, links, colours, images, videos and files; pins; swipe to remove; drag out to another app.
- Calendar tab: month grid that pages by swipe or scroll, day selection and expandable events.
- Mirror tab: zoom, freeze, flip and copy frame; the camera prompt now waits for **Allow camera**.
- Stay Awake: status and controls split, with manual time adjustment.
- Update check against GitHub Releases (Preferences ▸ General ▸ Updates).
- Notch panel: open on click instead of hover; Now Playing clock and refreshed player.
- Dock: profile pill, magnification toggle and context menu.

### Changed

- File tray, Notes and Terminal tabs refreshed.
- Preferences use native macOS switches.
- Release DMGs are built universal (Apple Silicon and Intel); the Homebrew cask is updated through pull requests.

### Removed

- The knock gesture.

### Fixed

- Now Playing artwork keeps its proportions.
- Signed builds can request calendar access (hardened-runtime entitlement).
- The About box shows the copyright.

## [1.0] - 2026-11-04

First public release.

[1.0.1]: https://github.com/WhoaStudio/whoa-notch/compare/v1.0...v1.0.1
[1.0]: https://github.com/WhoaStudio/whoa-notch/releases/tag/v1.0
