# Motion audit
Baseline macOS build succeeds with the App Intents metadata warning. Priority: Calendar, Music, then other surfaces. Preserve AppKit geometry and interactions, share existing spring presets, and gate motion on the system preference. Calendar events are read-only.

## Ranked transition inventory

| Rank | File and surface | Before | After |
| --- | --- | --- | --- |
| 1 | WeekStripView.swift, date selection | Two per-cell visibility toggles | One ring springs between day cells, including across week boundaries |
| 1 | WeekStripView.swift, week scrolling and month label | Direct scrolling with an existing critically damped snap, instant month label | Preserve gesture and snap physics, gate settling, slide month text on a boundary crossing |
| 1 | WeekAgendaRowView.swift and AgendaListView.swift, day agenda | The result for the selected day replaces the drawn list instantly | Short horizontal spring in the date direction after the current request completes |
| 1 | CalendarWidgetView.swift and AgendaListView.swift, calendar agenda | Event/empty/access results redraw instantly | Short vertical reveal for changed results |
| 1 | AgendaListView.swift, event rows | Read-only drawing, with no open or close interaction | Retain read-only behavior |
| 2 | NowPlayingRowView.swift, track metadata and Playing Next | Text and queue rows replaced in place | Changed metadata and incoming queue rows slide in |
| 2 | NowPlayingWingsView.swift, artwork | Image or placeholder replaced in place | Short lateral reveal |
| 2 | NowPlayingRowView.swift, play/pause | Symbol swapped in place | Native AppKit symbol replacement |
| 2 | AudioVisualizerView.swift, playback | Loop stopped by snapping to rest, and ignored live Reduce Motion changes | Springs to rest, switches to a static indicator when Reduce Motion changes |
| 2 | NotchPanelContentView.swift, compact player | Opacity-only handoff to the existing expanding silhouette | Spring travel and opacity, coordinated with the existing panel morph |
| 3 | NotchPanelContentView.swift and GlassReveal.swift, tab switching and panel open | Outgoing body hidden, incoming tab and full container blur-reveal | Directional spring on incoming tab, full-container reveal only on opening |
| 3 | NotchPanelContentView.swift, image transform | Immediate content replacement | Incoming Transform or Tray content springs in with the panel height |
| 3 | NotchPanelContentView.swift, greeting/device/agent/mail pills | Fade in and out | Short travel on entry, existing quick exit with silhouette collapse |
| 3 | SettingsWindowController.swift, Settings panes | Crossfade | Incoming pane slides in while old pane fades |
| 3 | DockContentView.swift, overflow folder | Rising entrance and fade-only exit | Springs up and back down, reversing from its current presentation |
| 3 | DockController.swift, auto-hide and display changes | Different entrance and exit timings, reveal always restarted offscreen | Common timing, same-screen reversal, per-display staging |
| 3 | DockProfilePill.swift, profile popup | Opacity-only | Spring entry with opacity and a gated exit |
| 4 | NotchAnalyticsTabView.swift, provider | Fade | Short lateral spring |
| 4 | ClipboardTabView.swift, filters | Cards or empty state rebuilt in place | Short lateral reveal after a filter change |
| 4 | NotesTabView.swift, empty/editor state | Immediate swap | Visible state springs in |
| 4 | FileTrayView.swift, file selection | Check badge appeared instantly | Short spring for the incoming badge |
| 4 | ImageTransformView.swift, option and thumbnail states | Immediate replacement | Incoming options and resolved thumbnail spring in |
| 4 | CameraMirrorView.swift, permissions and availability | Status text and controls appeared instantly | Status content springs in, live preview remains direct |
| 4 | ColorPickerTabView.swift, current color and copy feedback | Swatch and copy glyph snapped | Spring color interpolation and native symbol replacement |
| 4 | StayAwakeTabView.swift, activation and scope | Labels and controls changed immediately | Spring on activation/scope only |
| 4 | NotchUsageTabView.swift, AI cards | Prompt and activity cards appeared instantly | Incoming card springs in |
| 4 | WelcomeView.swift and WelcomeController.swift, introduction | Half-second fade | SwiftUI spring and short offset, with reduced-motion gating |
| 5 | PanelFold.swift, OverlayAnimation.swift, CALayer+SpringAnimation.swift | Shared overlay springs followed the app preference | Common system preference gate, retargetable content reveal and shared SwiftUI spring |
| 5 | SettingsSectionViewController.swift, AppPickerView.swift, DockPreviewView.swift, DockContentView.swift | Existing row, reorder and removal motion had independent gating | Existing animation paths follow the common gate |
| 5 | UsageCalloutContentView.swift, Side Panel usage callout | Spring travel with a local fade | Spring travel and shared, gated fade |

Existing mechanisms retained where appropriate. NotchTabCapsuleView uses a spring for the selector, NotchPanelContentView uses a shape morph and direct swipe tracking, and BrightnessView, SidePanelContentView, VolumeDialView, SunButtonView and AirDropZoneView already use shared springs. RadialMenuView tracks the pointer directly. NowPlayingSliderView and progress clocks, Notes typing, Terminal output, live camera frames, drag targets and native menus/settings controls keep immediate or system-provided feedback. The work focuses on structural changes and key feedback. Secondary updates such as queue removal, note-to-note editing, clipboard data refresh, Tray list rebuild, some status badges, and settings controls still use their existing behavior.

## Verification

The requested macOS build and targeted CalendarAgendaTests passed. Existing Dock/AppKit diagnostics and the App Intents metadata warning may appear on recompilation. Manual motion checks remain for the Global and Calendar tabs, the compact and expanded Music player, notch tab and notification changes, Dock and Settings, and Reduce Motion toggled during playback.

## Follow-up pass

| File and surface | Before | After |
| --- | --- | --- |
| NowPlayingRowView.swift | Queue rows and headers vanished; player width jumped | Outgoing snapshots travel and dissolve without receiving input, and player geometry springs between its existing layouts |
| NotesTabView.swift | Switching notes and changing the count snapped | Editor content and changed count use short reveals; typing remains direct |
| ClipboardTabView.swift | Data refresh rebuilt visible results in place | Changed visible results and empty state use the existing filter reveal |
| FileTrayView.swift | Store changes rebuilt tiles in place | Incoming and shifted tiles, plus the empty state, use a short spring |
| ImageTransformView.swift | Failure and recovery titles snapped | Short opposing reveals |
| BatteryWidget.swift and DeviceStatusPillView.swift | Battery fill, numbers and device symbol snapped | Spring interpolation of fill, short number reveal and native symbol replacement |
| AgentActivityCardView.swift and AgentPromptCardView.swift | File/step changes and compact/full prompts swapped in place | Short reveals for changed status and content |
| PrivacySettingsViewController.swift, AISettingsViewController.swift and SettingsFormRowView.swift | Permission state, error text and control dimming snapped | Short status reveals and shared opacity timing |

## Dynamic island tab padding
The tab capsule already uses the same metrics in both modes. Use the notch's 12 pt top clearance for the shared tab body, keeping the island's existing 2 pt frame allowance. Use the notch’s 12 pt visible side gutters without its 28 pt shoulder offset in island mode. The bottom inset, Mirror rim, and separate Transform view keep their existing spacing.

## Notch container transition

Keep a fixed AppKit window and drive the painted silhouette, rim, and mask together. Reveal the body and tab switcher when the opening spring settles. Separate the current shape from its destination and reject stale completions. The collapsed player keeps fixed artwork and visualizer positions while the hover variant adds a title below. Vertical swipes start in the island or the free center of the header, and horizontal swipes keep the existing dominant-axis tracker. Trackpad commits use alignment haptics. No changes to individual tab contents.

The final macOS build and 25 targeted tests passed. The desktop capture returned a blank overlay, so visual reversal, hardware alignment, frame pacing, and physical haptic checks are pending.

The opening reveal now starts with the shape spring in both styles. Blur and opacity use separate animations so a close can fade from the visible opacity. Shape completion still handles the artwork handoff.

## Stay Awake tab rework

Use a stable status card and intrinsic control widths at the 440 pt content floor. The card toggles a 15-minute session on click, switches to indefinite after a half-second hold with an alignment haptic, and adjusts timed sessions in five-minute scroll steps. The folded island shows a passive amber cup. The approved host hook mounts and positions the indicator and informs the tab when it folds. Existing view-model and IOKit code supply the countdown, adjustment bounds, and assertion lifecycle.

An AppKit geometry check passed at 440 pt for off, timed, adjusted maximum, and indefinite states. A standalone harness with the real provider confirmed assertion creation, manual release, and timer expiry with an accelerated clock in `pmset -g assertions`. The focused suite reports a pre-existing failure in `adjustMovesDeadline`: four comparisons capture optional TimeInterval values and integer literals as different types despite identical numeric values.

The folded indicator also appears in notch mode. On hardware with a camera notch, reserve a 20 pt extension beneath the hardware for the cup while keeping the existing wing content aligned to the original band.
