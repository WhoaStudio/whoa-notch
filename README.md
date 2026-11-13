# Whoa Stash

A macOS menu-bar app that puts controls and glanceable info on the edges of the screen.
It has no Dock icon (`LSUIElement`) and only shows one while Preferences is open.

| Surface | Where it appears | What it does |
|---|---|---|
| Brightness band | Middle of the left edge (left or right, set in Preferences) | Scroll to set the brightness of the display it is on. The built-in display goes through DisplayServices. External monitors use DDC/CI over I2C, or DisplayServices for Apple displays that don't expose DDC. |
| Volume dial | Top-left corner | Scroll to set the default output device's volume. |
| Edge slider | Right edge | Volume slider. |
| Side panel | Top-right corner | Usage rings for Claude Code and GitHub Copilot, one panel per screen. |
| Notch panel | Top centre, folded onto the notch (or a pill on screens without one) | Unfolds on hover or with a global shortcut. Tabs: **Global** (week strip, a Now Playing player, and a Playing Next column for Apple Music and Spotify), **Calendar** (agenda and month grid: swipe or scroll the grid to change month, click a day to see its events and **Today** to come back, click an event to expand it; a red line marks now and past events are dimmed; without access, a card with a button to allow it or open System Settings), **Tray** (a 4-file drop shelf), **Clipboard** (history of the last 50 copies: text, links, images, videos, files), **Notes** (plain-text notes: a list and an editor, saved in `Application Support/whoa-stash/Notes/`), **Mirror** (live camera preview in a circle, with a brightness slider for the preview only; pinch or scroll to zoom 1×–3×, click to freeze the frame, double-click for 1×, hover for **Flip** and **Copy frame**; without access, a card with **Allow camera** or **Open Settings**), **AI** (what Claude Code or Claude Desktop is asking you, see *Agent cards* below; when nothing is asked, what the agent is doing: Read, Edit, Bash, Done), **Terminal** (your login shell in a real PTY, started the first time the tab is opened and kept alive across folds; the panel stays open while the terminal has the keyboard and folds on a click elsewhere or the shortcut), **Color** (a pipette that picks any colour on screen: a large preview, a HEX/RGB/HSL switch, a click-to-copy value, the 8 latest picks and a Saved row; scroll the preview to adjust brightness and hue, drag it or any swatch into another app). Two more tabs open from the header instead of the tab bar: **Stay Awake** (the cup button, keeps the Mac awake with an IOKit power assertion) and **Analytics** (the usage chip: usage, filters and activity). Preferences ▸ General ▸ Notch panel chooses which tabs appear, whether it opens on click instead of hover, and the style on screens without a notch. While something plays, the folded notch shows "wings" with the track; a pill under the notch appears when a Bluetooth audio device (AirPods) connects. |
| Dock | Bottom centre | Custom dock: pinned and running apps (dot = running, globe = web app). Hovering the dock shows a floating pill above it to switch profile. Pinned apps are copied once from `com.apple.dock`, never written back. Clicking launches the app or brings its window forward and un-minimises it (needs Accessibility). Widgets (battery, storage) are added per profile in Preferences ▸ Profiles. Preferences ▸ Dock can hide the macOS Dock (auto-hide with a long delay) and restores your original values when turned off or on quit. |
| Radial menu | Under the cursor, while a mouse button is held | Hold the middle (or back/forward) button, or rest three fingers on the trackpad: a round menu opens centred on the cursor and stays on screen near edges. Move toward an item and release to run it; a short press keeps it open so you can click an item instead. Esc or a click outside closes it. Items are apps (launched) and Shortcuts.app shortcuts (run), added and reordered in Preferences ▸ Radial Menu. Off by default; needs Accessibility, and the chosen button no longer reaches other apps while it is on. |
| New mail | Notch wings, a few seconds | Sender, subject and the start of the text when a message reaches the inbox of an IMAP account set in Preferences ▸ Mail. The Mac connects directly to the mail server (IMAP IDLE, read-only); the password is in the Keychain. Off by default. Password or app password only, no OAuth yet. |
| Agent cards | Notch wings, then the AI tab | See *Agent cards* below. |
| Update check | Preferences ▸ General ▸ Updates | Asks the GitHub Releases API for the latest version at launch and every 24 h while *auto check* is on, and from **Check for Updates…**. It installs nothing: it shows the version and opens the release page. |
| Welcome | Under the notch, at the first launch only | Plays a short animation with the **Start** and **See Tutorial** buttons and waits for a click. It is marked as seen as soon as it shows, so a relaunch does not replay it. |

## Agent cards

When Claude Code (terminal or editor) or the Code tab of Claude Desktop asks for something, the notch shows it and you can answer from there. This needs the hooks: Preferences ▸ AI ▸ **Install hooks** merges one entry per event into `~/.claude/settings.json` (a backup is kept) and writes a relay script that talks to a local socket. Without them nothing appears. Which hook carries which card, and what is sent back, is in [docs/external-interfaces.md](docs/external-interfaces.md#claude-code-hooks-agent-cards-in-the-notch).

| Request | Card |
|---|---|
| Tool permission | The command or file, then **Deny**, **Allow** and **Always** (only when Claude Code proposes a rule to remember). |
| Plan | **Change plan**, **Auto mode**, **Manual**. |
| Question (`AskUserQuestion`, up to 4 questions) | Choices as rows (with descriptions) or chips. A single choice answers at once; a multiple choice is ticked, then sent with **Next** / **Send**. **Other…** swaps the choices for a text field (✕ closes it). A bar per question shows the step. |
| MCP form | The same card, with Yes/No, short lists or typed fields. **Decline** refuses it. |
| Reply after a turn | A text field that sends your text back so Claude carries on. Off by default: Preferences ▸ AI ▸ **Replies**. |
| A notification with nothing to answer | Read-only: the header says where to answer (**Open Claude** for Claude Desktop). |

- While the notch is folded, the wings say what is asked (`Allow?`, `Plan ready`, `Question`, `3 questions`, `Form`) and `+N` when more requests wait. A ring around the dot empties over the last 30 s before a question or reply is handed back to the terminal (120 s for a question or form, 25 s for a reply). A permission has no limit.
- A request you can answer opens the panel on the AI tab by itself, sized to the card. It does not take the keyboard: click the card once. Then `1`–`4` pick an option, the arrows or Tab move a focus outline, Return validates the focused option or sends a multiple choice, and Esc closes **Other…** and then folds the panel (the request stays pending in the wings). Return never allows a tool or accepts a plan.
- **Reply in terminal** (or **Reply in Claude**) hands the request back to the agent's own dialog at once.
- Claude Desktop's chat (not the Code tab) can also show a *Reply ready* notification: Preferences ▸ AI ▸ Claude Desktop, optional, through Accessibility.

## Install

Requires macOS 26.5 or later, on Apple Silicon or Intel.

Download the DMG from [GitHub Releases](https://github.com/WhoaStudio/whoa-stash/releases/latest), open it, and drag **whoa-stash.app** into **Applications**.

Or install the cask from this repository (no separate tap repository):

```bash
brew tap WhoaStudio/stash https://github.com/WhoaStudio/whoa-stash
brew install --cask WhoaStudio/stash/whoa-stash
```

If Homebrew requests tap trust, run `brew trust --cask WhoaStudio/stash/whoa-stash` and retry installation.

The cask becomes usable once the first release’s cask-update PR is merged. Release notes state whether the download is Developer ID signed and notarized. Without signing credentials, releases use an ad-hoc signature and are unnotarized; macOS may block them. After verifying the download source, use **System Settings → Privacy & Security → Open Anyway** if available.

## Releasing

From a clean `stable` checkout, synchronized with `origin/stable`:

```bash
scripts/release.sh 1.2
```

Use one to three numeric components, such as `1`, `1.2`, or `1.2.3`, without `v`. The command validates the branch, working tree, remote state, and tag availability; updates Xcode's marketing and build versions; commits; creates `v1.2`; and atomically pushes the commit and tag. It prints the Actions URL and watches the run when an authenticated `gh` is available. It does not commit any unrelated files. There is no root Makefile.

Alternatively, open **Actions → Release → Run workflow**, select **stable**, and enter the version without `v`. That run creates the commit/tag and completes the release itself. Pushing any `v*` tag also starts a release; the job rejects invalid versions and commits outside `stable`. The build always takes its version from the tag.

The workflow builds a universal Release app, verifies and mounts the DMG, publishes it with `SHA256SUMS` and automatically generated commit/PR notes, then opens a PR updating `version` and `sha256` in `Casks/whoa-stash.rb`. The cask PR must pass **Build and test** and receive the required approving review before merging into `stable`. Pull after a release before starting the next one.

The version-commit step still requires the release caller to be allowed to push release metadata to `stable` and create tags. Cask updates never push directly to `stable`. Allow Actions to create pull requests in the repository’s Actions settings; the cask workflow requests contents and pull-request write permissions. A tag pushed without a version commit still supplies the build's version.

To recover a cask update for an already published release, run **Actions → Update Homebrew cask → Run workflow** on `stable` and enter its version without `v` (for example `1.0`). This downloads the existing release DMG; it does not rebuild or republish it. With the default `GITHUB_TOKEN`, GitHub may require approval before running the PR’s CI. Optionally configure `CASK_PR_TOKEN` with a GitHub App installation token or fine-grained PAT permitted to write contents and pull requests to run PR checks without that workflow approval. The required PR review still applies.

Failed runs can be rerun: manual runs reuse only their own tag, published DMGs remain unchanged, and older releases cannot downgrade the cask.

To build and verify the same DMG locally without committing, tagging, or publishing:

```bash
scripts/build-dmg.sh 1.2
```

Output: `Build/release/1.2/whoa-stash-1.2.dmg`, `SHA256SUMS`, and `signing-status.txt`. Uses the selected Xcode; CI selects Xcode 26.6. Swift package build plugins are allowed as in CI; review dependency changes before building.

Verify the release tooling without pushing:

```bash
python3 scripts/tests/test-release.py
python3 scripts/tests/test-cask-pr.py
actionlint .github/workflows/release.yml .github/workflows/update-cask.yml
scripts/check-cask.sh
```

The cask check runs `brew audit --cask --strict` and `brew style` through a temporary local tap with isolated Homebrew trust settings.

### Optional signing and notarization

No signing secrets are required to release. To enable Developer ID signing and Apple notarization, configure **all six** repository Actions secrets (or export these names for local builds):

| Secret | Value |
|---|---|
| `MACOS_CERTIFICATE_P12_BASE64` | Base64-encoded export of a Developer ID Application certificate **and private key** (`base64 -i certificate.p12`). |
| `MACOS_CERTIFICATE_PASSWORD` | Password protecting that `.p12` export. |
| `MACOS_SIGNING_IDENTITY` | Full certificate name, e.g. `Developer ID Application: Your Name (TEAMID)`. |
| `APPLE_ID` | Apple Developer account email. |
| `APPLE_APP_SPECIFIC_PASSWORD` | App-specific password for that account. |
| `APPLE_TEAM_ID` | Developer team ID. |

If any are missing, the build falls back to ad-hoc signing and explicitly labels the release unsigned and unnotarized. If all are present but signing/notarization fails, the job fails rather than publishing an unsigned fallback. Credentials are imported into a temporary keychain, removed when the script exits. The signed path signs nested Mach-O binaries and the app with hardened runtime, notarizes and staples the app, then notarizes and staples the final DMG before calculating its checksum.

## Requirements

- macOS 26.5 or later (the deployment target)
- Xcode 26.6 (the version this README was checked with)
- One Swift package: [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) (Terminal tab). Xcode asks once to trust its `SwiftTermBuildInfoPlugin` build plugin; `xcodebuild` fails until you do. The Now Playing source is a vendored copy of [mediaremote-adapter](Vendor/MediaRemoteAdapter/README.md), shipped as `MediaRemoteAdapter.bin` and a Perl script in `whoa-stash/Resources/MediaRemoteAdapter/`.

## Build and run

Open `whoa-stash.xcodeproj` and run the `whoa-stash` scheme (⌘R), or from the terminal:

```bash
xcodebuild -scheme whoa-stash -destination 'platform=macOS' build
```

```bash
open "$(xcodebuild -scheme whoa-stash -showBuildSettings 2>/dev/null | awk '/ BUILT_PRODUCTS_DIR /{print $3}')/whoa-stash.app"
```

Signing is automatic. `Config/Base.xcconfig` sets the maintainer's team (`2MPVX5W6KB`). To build with your own team, or with none, copy `Config/Local.xcconfig.example` to `Config/Local.xcconfig` (git-ignored) and override `DEVELOPMENT_TEAM` and `CODE_SIGN_IDENTITY` there.

### What the app asks for

- **Calendars** (full access). The notch panel requests it the first time it loads the agenda. If you deny it, the panel shows an access-denied card.
- **Camera.** The Mirror tab asks the first time it is shown. The camera runs only while the panel is unfolded on that tab; the green LED goes off as soon as it folds or you switch tab. If you deny it, the tab shows a card that opens System Settings.
- **Keychain items owned by other apps.** The usage rings read the OAuth tokens that Claude Code (`Claude Code-credentials*`) and GitHub (`github-copilot-app` or `gh:github.com`) store. macOS asks you to allow the GitHub one on the first read. The Claude Code item is read through `/usr/bin/security`, which it already allows, so it never prompts. If you refuse, that ring shows as unavailable. Tokens stay in memory only.
- **Apple Events (Music).** Asked the first time the Playing Next column reads the Apple Music queue.
- **Spotify account.** Optional. Playing Next for Spotify needs a Client ID pasted in Preferences ▸ General. Tokens are stored in the Keychain under `ugolin-olle.whoa-stash.spotify`. See [docs/external-interfaces.md](docs/external-interfaces.md).
- **Accessibility.** Requested only where a feature needs it: the Dock (bringing a window forward and un-minimising it), the radial menu (a mouse-button event tap) and the optional Claude Desktop watcher.
- **Network.** Usage rings (Anthropic and GitHub endpoints), the update check (GitHub Releases), Spotify (Playing Next, optional) and the IMAP server you set in Preferences ▸ Mail. The IMAP password is stored in the Keychain. All of them are listed in [docs/external-interfaces.md](docs/external-interfaces.md).
- **Claude Code settings.** `~/.claude/settings.json` is edited only when you press **Install hooks**, and our entries are removed by **Uninstall**.
- **Local files.** The Claude and Codex readers use `~/.claude/projects`, `~/.codex/sessions` and `~/.codex/auth.json` (`$CODEX_HOME` overrides `~/.codex`). They feed the Codex usage and the activity section of the Analytics tab in the notch panel.
- The app is not sandboxed (`ENABLE_APP_SANDBOX = NO`).

For the Claude ring, log in to Claude Code on the machine. For the Copilot ring, sign in to the GitHub Copilot app or the GitHub CLI.

## Development launch flags

Pass them after `--args` in the `open` command above, or add them to the scheme's *Arguments Passed On Launch*.

| Flag | Effect |
|---|---|
| `--show-welcome` | Plays the welcome panel (with the Start and See Tutorial buttons) even if it was already seen, without changing the setting. |
| `--show-onboarding` | Opens the older onboarding window, which is no longer shown automatically. |
| `--show-settings[=general\|appearance\|screens\|privacy\|brightness\|radialMenu\|dock\|profiles\|ai\|mail\|about]` | Opens Preferences on that pane (default `general`). |
| `--show-notch-panel` | Unfolds the notch panel without hovering. |
| `--notch-tab=global\|calendar\|tray\|clipboard\|notes\|mirror\|ai\|terminal\|color\|stay-awake\|analytics` | With `--show-notch-panel`, unfolds on that tab. |
| `--color-picker=sample` | Color tab with a fake pipette: each **Pick** returns the next of five fixed colours after 1 s (one pick in five is a cancel), with no screen sampling. |
| `--stay-awake=mock` | Stay Awake tab with a fake power source: the UI works, no real assertion is taken. |
| `--show-usage-panel` | Opens the side panel without hovering. |
| `--agent-event=stop\|notify\|permission\|permission-long\|desktop\|question\|question-multi\|plan\|elicit\|reply\|clear\|work[,project]` | Shows a fixed AI agent card in the notch instead of waiting for a Claude Code hook (`desktop` labels it Claude Desktop). Answering it does nothing outside the app. |
| `--dock=sample` | Dock with fixed running apps (Safari, Terminal, Finder) instead of the real ones. |
| `--show-radial-menu` | Opens the radial menu under the cursor, left open, without the mouse button. |
| `--show-volume-dial` | Opens the volume dial without hovering. |
| `--clipboard-history=sample` | Fixed sample clips in the Clipboard tab, in a throwaway store. |
| `--usage-compare` | Opens the Analytics tab with the provider comparison (three rows) already open. |
| `--usage-delay=<seconds>` | Makes the mock usage sources (`--claude-usage`, `--codex-usage`, `--copilot-usage`) wait before answering, to see the loading state. |
| `--usage-fail=<list>` | Makes the mock usage sources fail: `claude`, `codex`, `copilot` or `all`, comma separated; add `:expired` for an expired session (Claude and Codex), for example `claude:expired,copilot`. |
| `--claude-usage=<session>,<weekly>` | Fixed Claude percentages, for example `73,7`. Skips the network and Keychain. |
| `--copilot-usage=<percent>` | Fixed Copilot percentage. |
| `--codex-usage=<five-hour>,<weekly>` | Fixed Codex percentages (consumed), for example `40,12`, shown in the Analytics tab. Skips the network and `auth.json`. |
| `--activity-sample` | A few days of fixed agent activity in the Analytics activity section, instead of reading the session logs. |
| `--update-check=available\|current\|failed` | Fake release source: `available` reports v999.0, `current` reports v0.0.1, `failed` (or any other value) makes the check fail. |
| `--battery=<0-100>` | Fixed battery level for the Dock battery widget; add `--battery-plugged` to show it as plugged in. |
| `--storage=<used%>,<freeGB>` | Fixed disk usage for the Dock storage widget, for example `62,120`. |
| `--now-playing=playing\|paused\|long` | Fake Now Playing source, with a simulated visualizer. `long` is a 2 h 54 min track with a long title, to check the time format and truncation. |
| `--playing-next=mock` | Fixed Playing Next queue instead of Apple Music and Spotify. |
| `--mail=sample` | Shows a fixed new-mail message in the notch about 2 s after launch, without any account. |
| `--simulate-bluetooth-device=airpodsmax\|airpodspro[,<battery>]` | Shows the Bluetooth device pill without hardware, for example `airpodsmax,82`. |
| `--camera-mirror=granted\|denied\|notDetermined` | Fake camera for the Mirror tab: a gradient instead of video, with the given access state. |
| `--calendar-agenda=granted\|denied\|notDetermined` | A fixed sample day with the given access state. |

## Credits

Sound Effect by <a href="https://pixabay.com/users/universfield-28281460/?utm_source=link-attribution&utm_medium=referral&utm_campaign=music&utm_content=293341">Official Profile</a> from <a href="https://pixabay.com//?utm_source=link-attribution&utm_medium=referral&utm_campaign=music&utm_content=293341">Pixabay</a>

## Tests

```bash
xcodebuild -scheme whoa-stash -destination 'platform=macOS' test
```

Run a single suite:

```bash
xcodebuild -scheme whoa-stash -destination 'platform=macOS' -only-testing:whoa-stashTests/SettingsStorageTests test
```

The suite is in `whoa-stashTests/`. It has 536 tests: 534 in Swift Testing across 78 suites, and 2 in XCTest (`CopilotUsageTests`).

CI builds and tests pull requests and pushes to `stable`. No app linter or formatter is configured.

## Project structure

```
whoa-stash/
  App/          entry point, AppDelegate (composition root), menu-bar item, Dock presence
  Core/         shared code: settings, logging, theme, geometry, animation, shortcuts
  Features/     one folder per surface: Brightness, EdgeSlider, Volume, SidePanel,
                NotchPanel, PanelTabs (notch tab contents), Agents (agent cards, hooks),
                Analytics, Clipboard, ColorPicker, Notes, Terminal, StayAwake, NowPlaying,
                DeviceStatus, Dock, RadialMenu, Mail, Updates, Welcome, Onboarding,
                Settings (Preferences window)
  Resources/    asset catalog (app icon, menu-bar glyph), MediaRemoteAdapter (binary + script)
whoa-stashTests/  unit tests
Vendor/           third-party sources (MediaRemoteAdapter), not built by the Xcode project
Design/Icon/      icon source SVGs (see Design/Icon/README.md)
docs/             architecture and debugging notes
```

More detail: [docs/architecture.md](docs/architecture.md), [docs/external-interfaces.md](docs/external-interfaces.md), [docs/debugging.md](docs/debugging.md).

## Contributing

Bug reports, fixes and small features are welcome. Start with [CONTRIBUTING.md](CONTRIBUTING.md) for setup, conventions and the branch flow: branch off `stable` and open pull requests against `stable`. Each pull request needs one review and a passing CI check.

- [Code of Conduct](CODE_OF_CONDUCT.md) (Contributor Covenant 2.1)
- [Security policy](SECURITY.md): report vulnerabilities privately, never in a public issue
- [Issue forms](.github/ISSUE_TEMPLATE/): [bug report](.github/ISSUE_TEMPLATE/bug_report.yml), [feature request](.github/ISSUE_TEMPLATE/feature_request.yml)
- [Pull request template](.github/pull_request_template.md) and [code owners](.github/CODEOWNERS)

Maintainer: Ugolin O. ([@UgolinOlle](https://github.com/UgolinOlle)), [WhoaStudio](https://github.com/WhoaStudio).

## License

[MIT](LICENSE) © 2026 Ugolin O. and WhoaStudio. Vendored and package code keeps its own license: see [Vendor/MediaRemoteAdapter](Vendor/MediaRemoteAdapter/README.md) and [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm).
