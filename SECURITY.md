# Security policy

Whoa Notch reads OAuth tokens that other apps store in the Keychain (Claude Code, GitHub Copilot,
the GitHub CLI) and keeps Spotify tokens in its own Keychain item. Issues that could leak those
tokens, or let another process drive the app, matter to us.

## Reporting a vulnerability

Please report privately through GitHub:
[Report a vulnerability](https://github.com/WhoaStudio/whoa-notch/security/advisories/new).
Don't open a public issue or pull request.

Include what you found, how to reproduce it and the macOS version. Leave real tokens and personal
data out of the report. The maintainer, Ugolin O. ([@UgolinOlle](https://github.com/UgolinOlle)),
aims to reply within a week and follows up in the private advisory until a fix ships.

## Supported versions

Only the [latest release](https://github.com/WhoaStudio/whoa-notch/releases/latest) and the latest
commit on `stable` get security fixes.
