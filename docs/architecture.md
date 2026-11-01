# Architecture

## Overview

One process, no Dock icon (`LSUIElement`; `DockPresence` switches to `.regular` only while
Preferences is open). The SwiftUI `App` only declares an empty `Settings` scene. All real UI
is AppKit: borderless, non-activating `NSPanel`s placed at the screen edges, with layer-based
drawing.

## Layers

| Folder | Holds | May depend on |
|---|---|---|
| `App/` | `AppDelegate` (composition root), status-bar item, Dock presence | everything |
| `Features/<X>/` | one surface: controller, view model, services, views, models | `Core/`, and only the feature types `AppDelegate` passes in |
| `Core/` | settings, logging, palette/theme, shared geometry, animation, global shortcut, overlay feedback | nothing in `Features/` |

The exceptions are deliberate. `Settings` views read `SettingsStorage`, and `NotchPanel` hosts
the `PanelTabs` views and reuses the `SidePanel` rings.

## Composition root

`AppDelegate.applicationDidFinishLaunching` does all the wiring, in this order:

1. Returns immediately under XCTest (tests are hosted in the app).
2. Forces `.darkAqua` and builds `OverlayPaletteSettings` before any window, because views resolve the palette as they are built.
3. Creates each controller with `SettingsStorage.shared` and calls `activate()`.
4. Creates the device status coordinator, then the data view models: Now Playing, Playing Next, Clipboard history, Notes, Claude usage, Copilot usage and calendar agenda. Each picks a `Mock…Provider` when its launch flag is present, otherwise the real service. The Knock controller is built the same way, with `MockKnockSensor` or `SPUAccelerometerSensor`.
5. Connects each view model's `onStateChanged` (or `onItemsChanged`, `onPlayerChanged`) to the controllers' `apply(…)`. One fetch feeds every screen's panel.
6. Registers the global shortcut and applies the `--show-*` launch flags.

`CodexUsageViewModel` and `AgentActivityViewModel` exist but `AppDelegate` does not create them (TODO: not wired).

The global shortcut is a Carbon `RegisterEventHotKey` (`GlobalShortcutService`). It is chosen
from a fixed list (`GlobalShortcut`), re-registered whenever the setting changes, and toggles
the notch panel.

## Controllers and windows

- A controller owns its panels and their reveal/hide timing. The side panel, notch panel, brightness band and volume dial controllers each own a `GlobalMouseMonitor` that triggers the reveal. Panels ignore mouse events where the controller does hit-testing itself. The side panel tests the cursor against frames; the notch panel's content view hit-tests its painted silhouette.
- `SidePanelController` and `NotchPanelController` keep one window per screen, keyed by `CGDirectDisplayID` (screen order in `NSScreen.screens` changes). Both rebuild on `didChangeScreenParametersNotification`.
- The brightness band targets the screen it is shown on, not the main screen. `RoutingBrightnessBackend` picks a backend per access: DisplayServices for the built-in display, DDC/CI for external displays with an I2C line, and DisplayServices again for Apple displays without one. Both private frameworks are loaded with `dlopen`, so a missing symbol disables the feature without crashing.
- `FileShelfStore` (Tray tab) lives outside the views because the notch panel folds and switches tabs constantly. It holds the drag-out flag that stops the panel from folding while a file is dragged out.

## Persisted state

Both blobs are in `UserDefaults.standard`. Nothing else writes defaults. Three other stores live elsewhere: clipboard history in `Application Support/whoa-stash/Clipboard/` (JSON and PNG files, via `ClipboardHistoryStore`), notes in `Application Support/whoa-stash/Notes/notes.json` (via `NotesStore`, written on every edit), and Spotify tokens in the Keychain.

| Key | Owner | Contents |
|---|---|---|
| `com.whoastudio.whoa-stash.appSettings` | `SettingsStorage` | JSON of `AppSettings` (`general`, `brightness`, `edgeSlider`, `notchPanel`, `knock`, `spotify`). Written only when a value actually changes. |
| `com.whoastudio.whoa-stash.fileShelf` | `FileShelfStore` | Bookmark data for up to 4 tray files. Dropped files are moved into the tray folder. Bookmarks that no longer resolve are dropped on load. |

`AppSettings` decoding is tolerant (`AppSettings+Decoding.swift`): a missing key keeps its
default, a removed key is ignored, and an unknown enum value falls back to the default. Schema
changes must stay additive. There is no migration step.

The edge slider's settings are stored but have no Preferences pane.

## Refresh cadence

- Claude and Copilot usage are fetched on `activate()`, then every 60 s. A separate 30 s timer redraws the reset countdowns locally, with no network call.
- The calendar agenda reloads on EventKit change notifications.
- The clipboard provider polls `changeCount` every 0.5 s; history keeps 50 items.
- Playing Next refreshes when the notch panel unfolds and when the player changes.
