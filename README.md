# Whoa Stash

A macOS menu-bar app that puts controls and glanceable info on the edges of the screen.
It has no Dock icon (`LSUIElement`) and only shows one while Preferences is open.

| Surface | Where it appears | What it does |
|---|---|---|
| Brightness band | Middle of the left edge (left or right, set in Preferences) | Scroll to set the brightness of the display it is on. The built-in display goes through DisplayServices. External monitors use DDC/CI over I2C, or DisplayServices for Apple displays that don't expose DDC. |
| Volume dial | Top-left corner | Scroll to set the default output device's volume. |
| Edge slider | Right edge | Volume slider. |
| Side panel | Top-right corner | Usage rings for Claude Code and GitHub Copilot, one panel per screen. |
| Notch panel | Top centre, folded onto the notch (or a pill on screens without one) | Unfolds on hover or with a global shortcut. Tabs: **Global** (week strip, a Now Playing player, and a Playing Next column for Apple Music and Spotify), **Calendar** (month grid, agenda, three-week strip), **Tray** (a 4-file drop shelf), **Clipboard** (history of the last 50 copies: text, links, images, videos, files), **Notes** (plain-text notes: a list and an editor, saved in `Application Support/whoa-stash/Notes/`), **Mirror** (live camera preview in a circle, with a brightness slider for the preview only), **AI** (the same usage rings), **Terminal** (your login shell in a real PTY, started the first time the tab is opened and kept alive across folds; the panel stays open while the terminal has the keyboard and folds on a click elsewhere or the shortcut). While something plays, the folded notch shows "wings" with the track; a pill under the notch appears when a Bluetooth audio device (AirPods) connects. |
| Dock | Bottom centre | Custom dock: placeholder buttons and a "Building" pill (workspaces not built yet), then pinned and running apps (dot = running, globe = web app). Pinned apps are copied once from `com.apple.dock`, never written back. Clicking launches the app or brings its window forward and un-minimises it (needs Accessibility). Preferences ▸ Dock can hide the macOS Dock (auto-hide with a long delay) and restores your original values when turned off or on quit. |
| Radial menu | Under the cursor, while a mouse button is held | Hold the middle (or back/forward) button, or rest three fingers on the trackpad: a round menu opens centred on the cursor and stays on screen near edges. Move toward an item and release to run it; a short press keeps it open so you can click an item instead. Esc or a click outside closes it. Items are apps (launched) and Shortcuts.app shortcuts (run), added and reordered in Preferences ▸ Radial Menu. Off by default; needs Accessibility, and the chosen button no longer reaches other apps while it is on. |
| New mail | Notch wings, a few seconds | Sender, subject and the start of the text when a message reaches the inbox of an IMAP account set in Preferences ▸ Mail. The Mac connects directly to the mail server (IMAP IDLE, read-only); the password is in the Keychain. Off by default. Password or app password only, no OAuth yet. |
| Knock | No surface (accelerometer) | Knocking on the Mac's chassis runs an action set in Preferences ▸ Knock. Defaults: one knock turns the display off, two knocks lock the screen. Other actions: none, screen saver, Mission Control, play/pause, next track. |

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

Signing is automatic and uses the team set in the project (`2MPVX5W6KB`). To build on another account, change the team under *Signing & Capabilities*.

TODO: there is no release, archive or notarization process in the repo yet.

### What the app asks for

- **Calendars** (full access). The notch panel requests it the first time it loads the agenda. If you deny it, the panel shows an access-denied card.
- **Camera.** The Mirror tab asks the first time it is shown. The camera runs only while the panel is unfolded on that tab; the green LED goes off as soon as it folds or you switch tab. If you deny it, the tab shows a card that opens System Settings.
- **Keychain items owned by other apps.** The usage rings read the OAuth tokens that Claude Code (`Claude Code-credentials*`) and GitHub (`github-copilot-app` or `gh:github.com`) store. macOS asks you to allow the GitHub one on the first read. The Claude Code item is read through `/usr/bin/security`, which it already allows, so it never prompts. If you refuse, that ring shows as unavailable. Tokens stay in memory only.
- **Apple Events (Music).** Asked the first time the Playing Next column reads the Apple Music queue.
- **Spotify account.** Optional. Playing Next for Spotify needs a Client ID pasted in Preferences ▸ General. Tokens are stored in the Keychain under `ugolin-olle.whoa-stash.spotify`. See [docs/external-interfaces.md](docs/external-interfaces.md).
- **Accessibility.** Requested only when a knock action needs it (locking the screen sends a synthetic keystroke).
- **Local files.** The Claude and Codex readers use `~/.claude/projects`, `~/.codex/sessions` and `~/.codex/auth.json` (`$CODEX_HOME` overrides `~/.codex`). TODO: the Codex usage and agent activity code exists, but `AppDelegate` does not create `CodexUsageViewModel` or `AgentActivityViewModel`, so the Codex ring and the activity metrics are not shown yet (and `--codex-usage=<five-hour>,<weekly>` and `--activity-sample` have no visible effect).
- The app is not sandboxed (`ENABLE_APP_SANDBOX = NO`).

For the Claude ring, log in to Claude Code on the machine. For the Copilot ring, sign in to the GitHub Copilot app or the GitHub CLI.

## Development launch flags

Pass them after `--args` in the `open` command above, or add them to the scheme's *Arguments Passed On Launch*.

| Flag | Effect |
|---|---|
| `--show-settings[=general\|brightness\|knock\|about]` | Opens Preferences on that pane (default `general`). |
| `--show-notch-panel` | Unfolds the notch panel without hovering. |
| `--notch-tab=global\|calendar\|tray\|clipboard\|notes\|mirror\|ai\|terminal\|stay-awake` | With `--show-notch-panel`, unfolds on that tab. |
| `--stay-awake=mock` | Stay Awake tab with a fake power source: the UI works, no real assertion is taken. |
| `--show-usage-panel` | Opens the side panel without hovering. |
| `--dock=sample` | Dock with fixed running apps (Safari, Terminal, Finder) instead of the real ones. |
| `--show-radial-menu` | Opens the radial menu under the cursor, left open, without the mouse button. |
| `--show-volume-dial` | Opens the volume dial without hovering. |
| `--clipboard-history=sample` | Fixed sample clips in the Clipboard tab, in a throwaway store. |
| `--claude-usage=<session>,<weekly>` | Fixed Claude percentages, for example `73,7`. Skips the network and Keychain. |
| `--copilot-usage=<percent>` | Fixed Copilot percentage. |
| `--now-playing=playing\|paused` | Fake Now Playing source, with a simulated visualizer. |
| `--playing-next=mock` | Fixed Playing Next queue instead of Apple Music and Spotify. |
| `--mail=sample` | Shows a fixed new-mail message in the notch about 2 s after launch, without any account. |
| `--knock=single\|double` | Simulates a knock about 2 s after launch, instead of reading the accelerometer. |
| `--simulate-bluetooth-device=airpodsmax\|airpodspro[,<battery>]` | Shows the Bluetooth device pill without hardware, for example `airpodsmax,82`. |
| `--camera-mirror=granted\|denied\|notDetermined` | Fake camera for the Mirror tab: a gradient instead of video, with the given access state. |
| `--calendar-agenda=granted\|denied\|notDetermined` | A fixed sample day with the given access state. |
| `--logo-lid=closed\|peek\|open` | With the notch open on Global, freezes the logo's lid in that pose, with no hover or click, to check it. |

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

The suite is in `whoa-stashTests/`: The suite has 146 tests: 144 in Swift Testing across 26 suites, and 2 in XCTest (`CopilotUsageTests`).

TODO: there is no linter, formatter or CI configured.

## Project structure

```
whoa-stash/
  App/          entry point, AppDelegate (composition root), menu-bar item, Dock presence
  Core/         shared code: settings, logging, theme, geometry, animation, shortcuts
  Features/     one folder per surface: Brightness, EdgeSlider, Volume, SidePanel,
                NotchPanel, PanelTabs (notch tab contents), Clipboard, NowPlaying,
                DeviceStatus, Knock, Settings (Preferences window)
  Resources/    asset catalog (app icon, menu-bar glyph), MediaRemoteAdapter (binary + script)
whoa-stashTests/  unit tests
Vendor/           third-party sources (MediaRemoteAdapter), not built by the Xcode project
Design/Icon/      icon source SVGs (see Design/Icon/README.md)
AppIcons/         older generated icon pack, not used by the build
docs/             architecture and debugging notes
```

More detail: [docs/architecture.md](docs/architecture.md), [docs/external-interfaces.md](docs/external-interfaces.md), [docs/debugging.md](docs/debugging.md).
