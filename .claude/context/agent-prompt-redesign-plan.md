# Agent prompt cards: redesign plan (awaiting approval)

Scope: visual and interaction design of the notch / island surfaces where the user answers an agent.
Out of scope: `AgentHookServer`, `ClaudeHookInstaller`, the hook script, `AgentEvent.replyJSON` and every
`Decision` it sends. The plan borrows layout and interaction patterns from Coucou (`NotchBuddy/Sources/App/IslandViewContent.swift`,
`IslandRootView.swift`, `IslandWindowController.swift`, `Widgets/MochiLiveActivity.swift`). No names, mascot, icons, sounds or hex palette copied.

## 1. What we handle today

| Agent | How it reaches us | Prompt types |
|---|---|---|
| Claude Code (terminal, editor) | hooks → `agent.sock` | all six below |
| Claude Desktop (Code tab) | same hooks, `source = .claudeDesktop` | same six, label "Claude Desktop", "Reply in Claude" opens the app (not verified on the real app) |
| Claude Desktop (chat) | `ClaudeDesktopWatcher` (Accessibility) | "Reply ready" wings only, nothing to answer |
| Codex | **not handled** (only usage readers exist, not wired) | none |
| ChatGPT | **not handled** | none |

No iPhone surface exists. Our "Dynamic Island" is the island pill on Macs without a notch, which shows the same wings as the notch.

| # | Prompt | Folded (wings / island pill) | Unfolded (AI tab, `AgentPromptCardView`) |
|---|---|---|---|
| P1 | Tool permission (`PermissionRequest`, answerable) | logo + orange dot + project · "Needs input" | One-line capsule: dot, `Allow: <command>?`, **Allow** (green fill) · **Deny** (dark red) · Always (if `permission_suggestions`), logo, gold glow. Command truncated to one line, full text only in a tooltip. |
| P2 | Plan (`ExitPlanMode`) | same | Card: header (dot · project · source · "Plan"), title bold + body dim in a dark box, row Change plan (red) · **Auto mode** (green) · Manual. |
| P3 | `AskUserQuestion` (1–4 questions, single/multi) | same | Card "Question i/N": body repeats every option as text with ○●☐☑ markers and descriptions; *then* a row of equal-width buttons with the same labels (truncated) + Other…; multi adds Send/Next; second row "Reply in terminal". Other… swaps in a text field + Back. |
| P4 | MCP form (`Elicitation`) | same | Same as P3, "Form i/N", free-text fields, red Decline. |
| P5 | Free reply after a turn (`Stop`, opt-in) | same | "Finished" + last message, text field "Reply to Claude…" + Send, Dismiss button. |
| P6 | Notification text (not answerable) | same | Read-only card, hint "Answer in Claude Code". |

Today's interaction facts:
- The panel never opens by itself. The user has to hover the folded notch, then land on the AI tab.
- The AI tab is a fixed 240 pt high (`NotchPanelGeometry.aiTabHeight`). Long plans and questions are truncated, and a short permission leaves empty space.
- Keyboard: only Return in a text field. No Esc, no digit keys for options, no key hints.
- Motion: one `springReveal` (8 pt slide) when the card or pill appears. Moving between questions, opening Other…, and the footer changing all happen with no animation.
- Every button gets a colour (green, red or grey), so a card has two or three loud buttons and no single primary.

## 2. Coucou, same prompts

| Aspect | Coucou | Us |
|---|---|---|
| Card chrome | One dark card with a soft radial **wash** rising from the bottom edge: amber for permission/plan, cyan for questions. The colour is in the wash, not the buttons. | Flat `white 0.07` card. The colour is in the buttons. |
| Header | Coloured session dot · **project** · grey verb phrase ("needs permission", "has a plan ready", "is asking"), and a `1/3` queue count when other requests wait. | dot · project · source, and an orange kind label on the right. No queue count. |
| Permission body | Mono code block, several lines, wraps. | One truncated line (P1). |
| Permission buttons | Content-sized capsules, left-aligned: Deny (secondary) · **Allow (only primary: light fill, dark text)** · Always (secondary). Codex, Copilot: no Always. Agents that can't hold: "Reply in terminal" replaces Always. | Equal-width, Allow · Deny · Always, two coloured. |
| Plan buttons | Change plan · **Auto mode** · Manual (one primary). | Same order, but Change plan is red and Auto mode green. |
| Questions | Optional small `header` label, then question 13 pt semibold. Options with descriptions → **full-width rows** (label + description). Without descriptions → **wrapping chips**. Selected = tinted fill + stroke. Single-select: one click answers and moves on. Multi: one primary Send/Next, disabled until valid. | Options listed twice (text list + truncated buttons). Selected = green "allow" fill. |
| Other… | Replaces the options in place: autofocused field, Return submits, Esc or ✕ closes. | Field below, plus a Back button. Esc does nothing. |
| Reply in terminal | Small underlined **text link** top-right of the header (tertiary). | A full-width button row. |
| Keyboard | `1`…`n` pick options. Esc in the notch folds it but keeps the request pending. Esc typed in another app never folds a pending approval. A global "go to alert" shortcut opens the waiting card. Buttons can show a key hint chip. | none |
| How it grows | A request **auto-expands** the island and holds it open until answered. Size is per view, grows with a spring (response 0.5, damping 0.72) and shrinks with an ease. | Hover only, fixed height. |
| Transitions | Views cross-fade: incoming spring (0.4/0.8, delay 0.16) with scale 0.97→1, outgoing ease-in 0.16. Question steps animate. | Only the first reveal. |
| Phone / Lock Screen / Dynamic Island | Deny (bordered red, ✕) left, **Allow** (prominent green) right, equal width; orange "waiting for your OK" with an elapsed timer; new phases slide up from the bottom. | No phone. The Mac island pill shows "Needs input" only. |

## 3. Polish plan (highest impact first)

Each item stands on its own and keeps the same `Decision` values.

### 1. One card layout for every prompt, colour moved into a wash
- Drop the one-line P1 capsule. Permission becomes a card like the others: header, then a mono code block (up to 4 lines, wrapped, middle-truncated past that, full text in the tooltip and selectable), then buttons.
- Card chrome: dark base plus a bottom radial wash by kind (amber: permission and plan; cyan: question and form; neutral: reply and notification), from `OverlayPalette`, not Coucou's values.
- Header: dot · **project** · grey verb ("needs permission", "has a plan", "is asking", "finished"), source as a small secondary label, queue count `1/N` on the right.
- Files: `Features/Agents/Views/AgentPromptCardView.swift` (layout, new `PromptCardBackground` / `PromptHeader` private views), `Core/Theme/OverlayPalette` (wash colours) if a token is missing.

### 2. One primary button per card, consistent order
- `PromptButton` styles become `.primary` (light fill, dark text), `.secondary` (white 0.09), `.destructiveSecondary` (only for a form's Decline), `.link` (underlined text). Capsules sized to content, aligned left.
- Permission: Deny · **Allow** · Always (Always only when `offersAlways`, as today).
- Plan: Change plan · **Auto mode** · Manual.
- Question multi / form field: **Send / Next** only.
- Reply: **Send** in the field, "Dismiss" as a link.
- "Reply in terminal" / "Reply in Claude" moves to a header link on P2–P5.
- Codex note: Coucou hides Always for Codex. We already key it on `permission_suggestions`, not on the agent name. A future Codex source gets Allow / Deny with no view change.
- Files: `AgentPromptCardView.swift` (`PromptButton`, `footer(for:)`, `formFooter`).

### 3. Real question layout
- Remove the duplicated text list from the body box.
- Options with any description → full-width rows (label 12 medium, description 11 grey, wraps). All short labels → wrapping chips (simple flow layout in frames).
- Selected state: tint + 1 pt stroke, a checkbox glyph for multi. No green "allow" fill.
- Single-select click answers and advances (as today). Multi: primary Send/Next, disabled until valid (as today).
- Other…: the field replaces the options in place, autofocused, with ✕ to close. "Back" is removed.
- Step indicator `i/N` as small segments in the header.
- Optional, needs your OK because it touches parsing: show `AskUserQuestion`'s `header` field as a small label (needs a `header` property on `AgentEvent.Question`, read-only, nothing sent back changes).
- Files: `AgentPromptCardView.swift`, `Models/AgentPromptForm.swift` (only if a "close Other" state is renamed; no behaviour change).

### 4. Panel grows to the card, and opens by itself
- Height: the AI tab asks the card for its fitting height (min 120, max ~380, then the body scrolls). Height springs on content change (question step, Other… opening). Uses the existing `SpringPreset` (no new curves), and `OverlayAnimation.allowsMotion` for reduced motion.
- Auto-present: an answerable prompt (`replyID != nil`) unfolds the panel on the AI tab and holds it open until it is answered, handed back or expired. It folds on Esc in the panel or a click elsewhere, and the prompt stays pending in the wings. Fullscreen rule unchanged.
- It does **not** take the keyboard when it opens (typing in the terminal must not land in the card). The panel becomes key only after hover/click on the card (same mechanism as the Terminal and Notes tabs: `wantsKeyboard` / `holdsKeyboardFocus`).
- Optional: a Preferences ▸ AI toggle "Open the notch for requests" (default on). Needs a defaulted field in `AISettings`.
- Files: `NotchPanel/NotchPanelController.swift` (`presentAgentEvent`: unfold + hold), `NotchPanel/Views/NotchPanelContentView.swift` (variable AI height, hold-open while a prompt waits), `NotchPanel/Models/NotchPanelGeometry.swift` (`aiTabHeight` → min/max + fitting height), `PanelTabs/Views/Usage/NotchUsageTabView.swift` (forward `fittingHeight`). Optional: `Core/Settings/AISettings.swift`, `AppSettings+Decoding.swift`, `Settings/Views/AISettingsViewController.swift`.

### 5. Keyboard
- When the card is key: `1`–`4` pick options (and toggle in multi), Return = Send/Next for multi and text fields, Esc closes Other… first, then folds the panel (prompt stays pending). Tab and arrows move focus between options.
- **Not** Return = Allow. A stray Return should never approve a command. Coucou doesn't bind it either.
- Key hint chips (`1`, `↩`, `esc`) on options and the primary button, dimmed.
- Esc from another app never folds a pending prompt (we have no global Esc today; keep it that way).
- Files: `AgentPromptCardView.swift` (`keyDown`, `acceptsFirstResponder`, hint chips), `NotchPanelContentView.swift` (Esc routing, the `wantsKeyboard` flag for the AI tab while a prompt is shown).

### 6. Transitions
- Card swap (permission → next queued prompt, step to the next question): outgoing fades out in ~0.15 s, incoming fades in and scales from 0.97 with a short delay, both on `CALayer` like `springReveal`.
- Buttons appearing (phase change, Other… opening): slide up 6 pt + fade, the iOS "phase in" pattern.
- Answered: a brief check state on the pressed button (~250 ms) before the card leaves, so the click gets feedback.
- Files: `Core/Extensions/CALayer+SpringAnimation.swift` (one `crossfadeIn` helper), `AgentPromptCardView.swift`.

### 7. Folded wings and island pill say what is asked
- Right wing: kind-specific status in the wash colour ("Allow?", "Plan ready", "Question 1/3", "Form"), plus `+N` when several prompts wait. Left wing unchanged (logo + dot + project).
- Questions are handed back to the terminal after 120 s. Show a thin countdown ring around the dot for the last 30 s so the hand-back isn't a surprise.
- On the island pill (no-notch Macs) the same text, shortened to fit 150 pt wings.
- Files: `Views/AgentEventPillView.swift`, `NotchPanelController.swift` (pass the queue count and the hand-back deadline, read from `AgentPromptStore` only).

### 8. Free-reply and read-only cards
- P5: last message as the body (3 lines max), single-line field with a round send button inside it, "Dismiss" link.
- P6: same card chrome, neutral wash, "Answer in Claude Code" as the header link (or "Open Claude" for Desktop).
- Files: `AgentPromptCardView.swift`.

## 4. Not planned (and why)
- **Codex and ChatGPT prompts.** No event source exists for either. Adding one changes how events are received, which is out of scope. Items 1–2 keep the card agent-agnostic so a later source fits.
- **Lock Screen / iPhone Dynamic Island.** There is no iOS target or relay. Building one changes how replies are sent. Coucou's phone layout (Deny left, Allow right, equal width, elapsed timer) is noted as the reference if it's ever added.

## 5. Verification per item
- Existing flags, no hooks needed: `--show-notch-panel --notch-tab=ai --agent-event=permission|permission-long|plan|question|question-multi|elicit|reply|desktop`. Screenshot each before and after.
- `AgentPromptCardViewTests` clicks and types on the real card. Update it for the new button order and titles, and add digit/Esc key tests. `AgentPromptFormTests` should pass unchanged.
- One real Claude Code session with reinstalled hooks: permission, single question, 3-question multi-select, plan. Still unverified today.
