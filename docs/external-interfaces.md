# External interfaces

The app serves nothing. It consumes three undocumented HTTP endpoints (Claude, Copilot, Codex)
and the public GitHub Releases API, reads Keychain items and files owned by other apps, and uses
several TCC permissions. These can change without notice, so this
file records exactly what the code expects.

## HTTP

All three calls are `GET`, made from the `…UsageService` types in `Features/SidePanel/Services/`.
Any non-2xx response throws `badStatus`, and a payload without the expected keys throws
`unrecognizedPayload(keys:)` with the keys actually received. Either error becomes
`.unavailable(reason:)` in the view model, and the ring shows as unavailable. Polling interval:
60 s (Claude and Copilot).

| Source | Endpoint | Headers | Fields read |
|---|---|---|---|
| Claude | `https://api.anthropic.com/api/oauth/usage` | `Authorization: Bearer <token>`, `anthropic-beta: oauth-2025-04-20` | Session window from the first of `five_hour` / `fiveHour` / `session`. Weekly window from `seven_day` / `sevenDay` / `all_models` / `week`. Inside each: `utilization` (0–100, also `used_percent`, `percent_used`, `percentage`) and `resets_at` (also `resetsAt`, `reset_at`). |
| Copilot | `https://api.github.com/copilot_internal/user` | `Authorization: Bearer <token>`, `Accept: application/vnd.github+json`, `X-GitHub-Api-Version: 2022-11-28` | `quota_snapshots.premium_interactions.percent_remaining` (shown as 100 − value) and `quota_reset_date_utc`, falling back to `quota_reset_date`. |
| Codex | `https://chatgpt.com/backend-api/wham/usage` | `Authorization: Bearer <token>`, `User-Agent: codex-cli`, `chatgpt-account-id` when known | `rate_limit.primary_window` / `secondary_window`, told apart by `limit_window_seconds` (5 h vs weekly). |

The parsers are `ClaudeUsageService.parse(_:)`, `CopilotUsageService.parse(_:)` and `CodexUsageService.parse(_:)`.
`CopilotUsageTests` covers the Copilot parser. When an endpoint changes shape, add the new
key to the fallback list first.

## IMAP (new mail in the notch)

`IMAPMailSource` opens a TLS connection (`Network.framework`, default certificate checks) straight
from the Mac to the server set in Preferences ▸ Mail, usually port 993. It signs in with `LOGIN`,
opens the inbox read-only (`EXAMINE`), waits with `IDLE`, and on `* n EXISTS` runs
`UID FETCH <last+1>:*` for `FROM`, `SUBJECT`, `MESSAGE-ID`, the content headers and the first 6 KiB of
`BODY.PEEK[TEXT]`. Nothing is marked as read and nothing is stored: only sender, subject and a
one-line preview are kept in memory while the notch shows them. `IDLE` is restarted every 10 minutes
(and the connection is closed if the server does not answer `DONE` within 30 s). A lost connection is
retried after 5 s, doubling up to 5 min, and the messages missed meanwhile (at most 5) are shown after
reconnecting. Sender, subject and server name are logged as private.

Sign-in is a password or app-specific password (iCloud, Gmail with 2-step verification). OAuth
(`XOAUTH2`, needed for Outlook.com and for Gmail without an app password) is not implemented.

## Keychain

All reads are generic-password reads. Tokens are cached in memory only, and are never written
to disk or logged.

| Store | Item service | Notes |
|---|---|---|
| `IMAPCredentialStore` | `ugolin-olle.whoa-stash.imap`, account `<user>@<host>` | The IMAP password, as UTF-8. Written from Preferences ▸ Mail, read when connecting. |
| `ClaudeUsageCredentialStore` | `Claude Code-credentials` or `Claude Code-credentials-<hash>` | Finds the item by attributes first (no prompt), takes the most recently modified one, then reads its data through `/usr/bin/security find-generic-password -w` (no prompt). The JSON is `claudeAiOauth.accessToken` plus `expiresAt` in **milliseconds**. The token is cached until 30 s before expiry, or for 5 min when there is no expiry. An expired token raises "relance `claude`". |
| `CopilotUsageCredentialStore` | `github-copilot-app`, then `gh:github.com` | The value may be `go-keyring-base64:`-prefixed (GitHub CLI). It must start with `gho_`, `ghp_` or `github_pat_`. Cached for 5 min. |

The Claude item's data is read through `/usr/bin/security`, as Claude Code does itself, not with
`SecItemCopyMatching`. Claude Code rewrites the item with `security add-generic-password -U` on
every token refresh, which resets its partition list to `apple-tool:` and drops the `teamid:` that
"Always Allow" adds. A direct read would prompt again after every refresh. `/usr/bin/security` is
in the item's ACL and matches `apple-tool:`, so it never prompts.

## Local files

| Reader | Path | Notes |
|---|---|---|
| `CodexUsageCredentialStore` | `$CODEX_HOME/auth.json`, else `~/.codex/auth.json` | Reads `tokens.access_token` and `tokens.account_id`. Held in memory only, never rewritten. |
| `AgentActivityProviding` (activity logs) | `~/.claude/projects`, `~/.codex/sessions`, `~/.codex/archived_sessions` (`*.jsonl`) | Read by `LocalAgentActivityService` for the activity section of the Analytics tab: at launch, on refresh and when the month changes. |

## Claude Code hooks (agent cards in the notch)

`ClaudeHookInstaller` merges one entry per event into `~/.claude/settings.json` (backup first, only
our own entries touched) and writes the relay script `Application Support/whoa-stash/whoa-hook`. The
script sends the hook's JSON to the local socket `agent.sock` (0600, no network) and exits 0 when the
app is not running. `AgentHookServer` reads one JSON line per connection; for a request that can be
answered it keeps the connection open and writes the reply on it.

| Hook (argument) | Card | The reply the script prints | Held for |
|---|---|---|---|
| `PermissionRequest` (`permission`) | Allow / Deny / Always, or a plan: Change plan / Auto mode / Manual | `hookSpecificOutput.decision`: `behavior`, `updatedInput` (plans, questions), `updatedPermissions` (Always echoes `permission_suggestions`; plan modes send `setMode` on the session) | until answered or closed (the terminal dialog opens in parallel) |
| `PreToolUse` on `AskUserQuestion` (`question`) | one question at a time: single choice answers at once, multiple choice is ticked then sent, "Other…" opens a text field | `permissionDecision: allow` + `updatedInput` with `answers` (multiple labels joined with `, `) | 120 s, then `{}` |
| `Elicitation` (`elicit`) | MCP form, form mode only, up to 4 fields (Yes/No, a short enum, or typed text checked against `string` / `number` / `integer`) | `action: accept` + `content`, or `decline` | 120 s, then `{}` |
| `Stop` (`stop`) | free-text reply, only when Preferences ▸ AI ▸ Replies is on | `decision: block` + `reason`: Claude carries on with the text | 25 s, then `{}` |

`{}` hands the request back: Claude Code asks in its own terminal (or stops, for `Stop`). "Reply in
terminal" sends it at once; for Claude Desktop it also brings the Claude app forward. A question handed
back is not shown again by the later `PermissionRequest` until the session moves on. A `Stop` that a hook
already continued (`stop_hook_active`) is never held. The script reads `CLAUDE_CODE_ENTRYPOINT` so that
sessions from Claude Desktop's Code tab are labelled "Claude Desktop". Hooks installed by an older
version lack `Elicitation` and the longer `Stop` handling: Preferences ▸ AI shows "Partly installed", and
"Install hooks" replaces them. TODO: whether Claude Desktop's Code tab runs these hooks and honours their
replies has not been checked on a real session.

## Update check

`GitHubReleaseProvider` makes one `GET https://api.github.com/repos/WhoaStudio/whoa-stash/releases/latest`
(`Accept: application/vnd.github+json`, `User-Agent: whoa-stash`, 15 s timeout, no token). It reads `tag_name`
and `html_url` and compares the tag with `CFBundleShortVersionString`, component by component. `UpdateChecker`
runs it at launch and every 24 h while Preferences ▸ General ▸ Updates is on, and from **Check for Updates…**.
Anything other than a 200 response is shown as a failed check. Nothing is downloaded or installed: the app shows
the version and opens the release page. `--update-check=available|current|failed` replaces the call.

## System tools and private surfaces

| Feature | What it uses |
|---|---|
| Hiding the macOS Dock (Preferences ▸ Dock) | `/usr/bin/defaults write com.apple.dock autohide` and `autohide-delay`, then a Dock restart. The original values are kept and put back when the setting is turned off or the app quits. A detached shell watcher puts them back if the app disappears without quitting normally. |
| Dock pins | Copied once from `com.apple.dock` (`persistent-apps`), never written back. Clicking an app raises its window through Accessibility. |
| Radial menu | An active `CGEventTap` on the chosen mouse button (needs Accessibility); items run apps or `/usr/bin/shortcuts run`. |
| Stay Awake | An IOKit power assertion, taken from the cup button. `--stay-awake=mock` takes none. |
| Color tab | The system `NSColorSampler`, which brings its own cursor, Esc handling and any screen-capture permission prompt. |
| Battery widget | IOKit power-source notifications (no polling). The storage widget reads disk usage every 60 s. |
| Claude Desktop reply notification | Accessibility (`AXManualAccessibility` on the Claude app), optional, Preferences ▸ AI ▸ Claude Desktop. |

## Environment variables

| Variable | Read by | Effect |
|---|---|---|
| `SHELL` | Terminal tab | The login shell it starts; `/bin/zsh` when unset or empty. |
| `CODEX_HOME` | Codex usage and activity readers | Replaces `~/.codex`. |
| `CLAUDE_CODE_ENTRYPOINT` | the `whoa-hook` relay script | Labels sessions from Claude Desktop's Code tab "Claude Desktop". |
| `XCTestConfigurationFilePath`, `XCTestBundlePath` | `AppDelegate` | Either one makes the app return before building anything, so a test run never drives real hardware. |
| `RELEASE_CI` | `scripts/release.sh` | `1` only in the release workflow, where `GITHUB_RUN_ID` is also set. Don't set it locally. |
| `MACOS_CERTIFICATE_P12_BASE64`, `MACOS_CERTIFICATE_PASSWORD`, `MACOS_SIGNING_IDENTITY`, `APPLE_ID`, `APPLE_APP_SPECIFIC_PASSWORD`, `APPLE_TEAM_ID` | `scripts/build-dmg.sh` | Developer ID signing and notarization when **all six** are set; see the README. |


## Permissions

New mail needs none: the app is not sandboxed, so outgoing connections are allowed, and no
entitlement was added.

| Permission | Requested by | Fallback |
|---|---|---|
| Calendars, full access (`NSCalendarsFullAccessUsageDescription`) | `EventKitCalendarService.requestAccess()`, only while the status is `.notDetermined` | Notch panel shows the denied card |
| Camera (`NSCameraUsageDescription`) | Mirror tab (`AVCameraMirrorService`), the first time the tab is shown | The tab shows a card that opens System Settings |
| Apple Events to Music (`NSAppleEventsUsageDescription`) | `AppleMusicQueueProvider`, through `/usr/bin/osascript`, on the first read of the Apple Music queue | The Playing Next column stays empty |
| Accessibility (`NSAccessibilityUsageDescription`) | `AccessibilityPermissionService`, from the Dock (raising windows), the radial menu (mouse event tap) and the Claude Desktop watcher | The action, or the feature, is skipped |

The Info.plist strings are in French and live in the target's build settings
(`INFOPLIST_KEY_…`, generated Info.plist). There is no Info.plist file.

## Now Playing

- **System now-playing source.** `MediaRemoteNowPlayingProvider` runs `/usr/bin/perl` with the vendored
  `mediaremote-adapter` (`Vendor/MediaRemoteAdapter`, shipped as `MediaRemoteAdapter.bin` plus the
  `.pl` script in Resources) and reads its JSON stream. It is the only route to MediaRemote since
  macOS 15.4, and it relies on a private framework.
- **Playing Next, Apple Music.** `AppleMusicQueueProvider` asks Music for the next tracks of the
  current playlist through `osascript`. It returns nothing while shuffle is on.
- **Playing Next, Spotify.** `SpotifyQueueProvider` calls `GET https://api.spotify.com/v1/me/player/queue`
  with the user's account. Sign-in is OAuth 2 PKCE (`SpotifyAuthorizer`): the browser opens once, and
  Spotify redirects to `http://127.0.0.1:48731/callback`, served by a loopback socket that only
  listens while connecting. The user creates the Spotify app, registers that redirect URI and pastes its
  Client ID in Preferences, General. Tokens live in the Keychain (service
  `ugolin-olle.whoa-stash.spotify`), never in `UserDefaults`. Scope: `user-read-playback-state`.
- Launch flags: `--now-playing=playing|paused`, `--playing-next=mock`.
