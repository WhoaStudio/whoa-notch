# whoa-notch

macOS menu-bar app (Swift 6, AppKit with a SwiftUI `App` shell) that shows overlay panels at the screen edges. See @README.md for the features and launch flags.

## Commands

- Build: `xcodebuild -scheme whoa-notch -destination 'platform=macOS' build`
- Test: `xcodebuild -scheme whoa-notch -destination 'platform=macOS' test`
- One suite: append `-only-testing:whoa-notchTests/<SuiteName>` before `test`
- Logs: `log stream --predicate 'subsystem == "ugolin-olle.whoa-notch"'`
- TODO: no lint or format tooling is configured.

## Architecture

- `App/AppDelegate.swift` is the only composition root: it builds every controller and view model and wires their state callbacks together. Add new surfaces there.
- Features: Brightness, EdgeSlider, Volume, SidePanel, NotchPanel, PanelTabs (notch tab contents), Clipboard, Notes, Terminal, NowPlaying, DeviceStatus, StayAwake (IOKit power assertion, opened from the cup button in the notch header), Settings.
- Features that own windows have a `…Controller` that owns its `NSPanel`s and exposes `activate()`, plus `togglePinnedReveal()` and `apply(…State:)` where relevant. View models push state through `onStateChanged`; they don't hold controllers.
- Side panel and notch panel keep one window per connected screen and rebuild them when the screen configuration changes.
- Details: [docs/architecture.md](docs/architecture.md). Network, Keychain and permissions: [docs/external-interfaces.md](docs/external-interfaces.md).

## Conventions

- Doc comments, log messages and test names are in French. Write new ones in French too.
- The module defaults to `@MainActor` (`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`). Mark anything called from C callbacks or background queues `nonisolated`, as `Log` and `DDCTransport` do.
- Log through `Log.<category>` (OSLog), never `print`. Leave user-derived strings private and mark only technical values `.public`.
- Only `SettingsStorage` and `FileShelfStore` touch `UserDefaults`. Use `SettingsStorage.shared`, never a second instance.
- External sources go behind a protocol with a `Mock…Provider.fromLaunchArguments()` sibling, so the UI can be checked without network, Keychain or calendar access.
- Tests use Swift Testing (`@Suite` / `@Test`). `CopilotUsageTests` is the only XCTest file.

## Gotchas

- Tests are hosted in the app (`TEST_HOST`). `AppDelegate` returns early when `XCTestConfigurationFilePath` is set. Without that guard, a test run would drive real display brightness over DDC and read the Keychain.
- `AppSettings` is stored as one JSON blob. Only add fields with defaults. Decoding must keep tolerating missing keys, removed keys and unknown enum values (`SettingsStorageTests` covers this).
- The app forces `.darkAqua` appearance in `AppDelegate`. Don't add light-mode variants.
- DDC goes through private `IOAVService` symbols loaded with `dlopen`, so they are missing on Intel. Code must degrade, never crash.
- `.gitignore` covers `xcuserdata/`. Don't commit local Xcode state by accident.

## Workflow

- Keep `.Codex/context/task_context.md` current during multi-step work, and read it when resuming.
- Past decisions live in `.Codex/context/conversation_memory.md`. Check it before revisiting one, and append a line when you make one.
- Paths in `.claudeignore` are read-denied through `.Codex/settings.json`. Don't work around that with shell commands.
- To skim a large file: `npx @whoa-studio/Codex-kit compress --outline <path>`.
- Subagents: `explorer` for broad searches, `/fix <symptom>` for bugs, `reviewer` before calling a change done, `test-writer` for coverage.

<!-- Codex-kit:begin map -->
## Codebase map

- `docs/INDEX.md` maps the repo by area and size. Start there instead of listing directories.
<!-- Codex-kit:end map -->
