# Debugging

## Logs

All logging goes through `Log` (`whoa-stash/Core/Log.swift`) into OSLog with subsystem
`ugolin-olle.whoa-stash`. The categories are `brightness`, `settings`, `side-panel`,
`calendar`, `camera`, `now-playing`, `clipboard`, `notes`, `sound`, `dock`, `radial-menu`, `agents`, `mail`,
`terminal`, `notch-panel`, `color-picker`, `onboarding`, `updates` and `stay-awake`.

```bash
log stream --predicate 'subsystem == "ugolin-olle.whoa-stash"'
```

```bash
log show --last 10m --predicate 'subsystem == "ugolin-olle.whoa-stash"' --style compact
```

`.debug` messages only appear when you enable debug level, either in Console.app (Action ▸
Include Debug Messages) or with `--level debug` on `log stream`. Strings that come from the user
are logged as `<private>`; that's on purpose.

## Reproducing a state without the real source

Use the launch flags listed in [the README](../README.md#development-launch-flags). Mock
providers replace the network, Keychain and EventKit, so you can reach every state of the
usage rings, the calendar card, Now Playing, Playing Next, the Bluetooth pill, agent cards (`--agent-event`), new mail, the update check and the Dock widgets without changing system state. The `--show-*` flags open a
surface without hovering, which is how screenshots are taken.

To develop the brightness band without driving a real display, swap
`SystemBrightnessService()` for `FakeBrightnessService()` in `AppDelegate`. Don't commit it.

## Known issues

| Symptom | Cause | Fix |
|---|---|---|
| Claude ring shows "unavailable" right after a Claude Code update | Claude Code wrote a new Keychain item, so the earlier grant no longer applies | Allow the Keychain prompt again |
| Claude ring: "Session Claude Code expirée" | The OAuth token in the Keychain expired | Run `claude` once to refresh it |
| Copilot ring: "Jeton GitHub illisible" | The Keychain value isn't a `gho_` / `ghp_` / `github_pat_` token | Sign in again with the GitHub Copilot app or `gh auth login` |
| A ring reports `Réponse illisible (clés reçues : …)` | The endpoint changed shape | Add the new key to the parser's fallback list (see [external-interfaces.md](external-interfaces.md)) |
| No agent card ever appears | The hooks aren't installed, or the app wasn't running (the script exits silently) | Preferences ▸ AI ▸ **Install hooks**; see [external-interfaces.md](external-interfaces.md#claude-code-hooks-agent-cards-in-the-notch) |
| Preferences ▸ AI says "Partly installed" | Hooks from an older version lack `Elicitation` or the longer `Stop` handling | **Install hooks** replaces them |
| Brightness doesn't change on an external monitor | No I2C line, or the `IOAVService` symbols are missing (Intel Macs) | Check the `brightness` log category. Without DDC, the code falls back to DisplayServices. |
| After a test run, logs show `File shelf move source does not exist` and `lecture de l'agenda échouée` | Tests exercise those error paths on purpose | Nothing to fix |
| Calendar card stays on "denied" after you change your mind | macOS doesn't show the prompt a second time | Re-enable it in System Settings ▸ Privacy & Security ▸ Calendars. To reset it fully: `tccutil reset Calendar ugolin-olle.whoa-stash` (not run while writing this doc: it revokes the grant). |
| Unit tests move your real screen brightness | The XCTest guard at the top of `applicationDidFinishLaunching` was removed | Restore it |
