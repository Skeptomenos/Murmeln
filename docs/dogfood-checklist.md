# Tier 2 Validation — Human Dogfood Checklist

Tier 1 (`bash validate.sh`) cannot assert the deploy-critical path: real hotkey →
real microphone → real transcription → real paste needs a logged-in GUI session,
mic input, and Accessibility permission. This checklist is the second tier.

**When:** mandatory before a release or phase-plan closeout — not per step.
**Who:** a human, using `Murmeln Dev` (never the production app for routine dogfooding).
**Evidence format:** one line per item — the capture ID plus the observed outcome.
Capture IDs are UUIDs assigned per capture and logged to
`capture-diagnostics.jsonl` under the app-support directory — `Murmeln Dev` for
the Dev build, the production directory otherwise (`AppIdentity.appSupportDirectoryURL`).
Find the most recent ID with:

```bash
tail -5 ~/Library/Application\ Support/Murmeln\ Dev/capture-diagnostics.jsonl
```

Record results in the active phase plan (Validation or Progress section).

## Checklist

| # | Scenario | Pass condition |
|---|----------|----------------|
| T2-1 | English short dictation (hold Fn, speak one sentence, release) into a native app (e.g. TextEdit, Notes) | Transcribed text pastes at the cursor; diagnostics show `completion_reason=paste_command_posted` for the capture ID; the human observation proves insertion |
| T2-2 | German dictation (only if a German-capable model, e.g. parakeet v3, is the active backend) | Correct German text pastes; no transliteration garbage |
| T2-3 | Lock mode: engage (quick Right-Option per current binding), speak, disengage | Recording starts on engage, stops on disengage, exactly one paste; no zombie recording after disengage |
| T2-4 | Paste into an Electron app (e.g. VS Code, Slack) | Text lands in the Electron app; clipboard behavior matches T2-1 |
| T2-5 | Refinement provider down (point refinement at an unreachable provider, then dictate) | Raw transcript still pastes and appears in history with the refinement-failed marker; transcript is NOT lost (B2 behavior) |
| T2-6 | Paste failure surface using a Dev-only controlled denied-permission or Secure Input case; do not reset production permissions | Persistent generic notice appears without focus change. Clipboard remains unchanged. Copy, then manual paste recovers exact text. Diagnostics report the blocker. |
| T2-7 | Phase 8 fresh install: wipe Dev defaults (`defaults delete com.mrml.app.dev` or the Dev bundle id), launch Murmeln Dev | Settings show Parakeet v3 selected with a "Download Model" button — no error state, no Python mention, no terminal needed |
| T2-8 | Phase 8 model lifecycle: start two not-installed model downloads, switch between them, cancel one and retry it; let one finish, then delete it from Settings | Each row keeps only its own live progress and distinct downloads advance independently (or visibly queue). Cancel returns that model to Download Model without affecting the other transfer; retry completes to Ready with no late cancellation error. Delete Model asks for confirmation, removes the cache, and returns the row to Download Model; a dictation with the remaining installed model pastes correctly |
| T2-9 | Phase 8 model switch: switch Parakeet v3 → WhisperKit → back via the unified picker | Each switch shows only that model's download/load state, warms the selected installed model, and supports dictation after each switch; exactly one selection persists |
| T2-10 | Phase 8 long dictation (only if Cohere INT8 selected): lock mode, dictate >35 s continuously | One coherent paste (long-form chunk path); no truncation at the 35 s boundary |
| T2-11 | Phase 8 migration: on a profile that previously used WhisperKit or the Cohere bridge, launch the new build | The equivalent catalog model is selected; language preference carried over; no re-setup required |

## DEV-150 recovery acceptance

Run these on **macOS 26 stable and macOS 27 beta**, using the exact reviewed Dev artifact. Record OS/build, capture and paste-attempt IDs, native/Electron target, observed focus and clipboard outcome. Do not use real passwords or put transcript text in diagnostic evidence. Automated private-pasteboard tests do not establish general-pasteboard prompting behavior.

| # | Scenario | Pass condition |
|---|---|---|
| R-T2-1 | Dictate with denied paste permission, or with Secure Input active in an unsupported/secure/unverifiable target | No automatic clipboard write or paste. Notice appears without moving focus or displaying text. Both blockers remain distinct when only one clears. |
| R-T2-1a | Dictate with Secure Input active in a verified ordinary TextEdit editor; repeat with changed window/editor/caret and nonempty selection | The unchanged empty-caret target receives the exact result once and clipboard contents are restored. Changed or unverified targets receive no event. No focus activation, automatic retry or field-text read. Record real normal-path capture/attempt IDs, not the fixed diagnostic. |
| R-T2-2 | Copy, change focus, paste manually; then Dismiss | Exact selected result is copied, including after a later capture. Successful Copy/Dismiss hide the card and clear its warning icon while preserving History and deliberate menu access. Failed/busy Copy stays actionable. No delayed insertion after protection clears. |
| R-T2-3 | Copy from menu, result/variant/original/audit buttons, keyboard and native selection while paste is busy | Busy feedback; no queued write. A fresh click after completion succeeds with the intended payload. |
| R-T2-4 | Keyboard, VoiceOver, sleep/wake, lock/unlock and user switch | Menu actions are keyboard reachable and named. Notice never becomes key, hides while locked/asleep/inactive, returns only when appropriate, and remains dismissed after late save callbacks. |
| R-T2-5 | Dev-only disposable History fixture with save/delete failure, full capacity and pending delivery | Unsaved rows remain accessible; capture pauses before audio admission. Retry save or selected discard restores capacity. Normal Quit is cancelled and usable controls return. Confirmed Quit anyway warns of unsaved loss/deletion reappearance. |
| R-T2-6 | Save and normal restart, then open the exact recovery History link | Saved text/capture identity survives. Successful deletion stays deleted. The link selects the correct row, including after newer results. |
| R-T2-7 | General clipboard with empty, multi-type and unreadable representations; external copy around paste | Checked preservation or explicit skip/failure. No overwrite of an observed newer copy. Record OS access prompts separately. |
| R-T2-8 | Open Accessibility Settings with Dev access denied; return after inspecting the pane | The correct pane opens or manual directions remain visible. Navigation does not claim a grant. Only actual event-post preflight changes the menu's permission state. Do not reset permissions for this check. |
| R-T2-9 | Restart twice, recording exact old/new PIDs and bundle paths | Each restart leaves one responsive Dev process. Normal launch failure restores the old app. If a newly launched copy cannot be stopped after a failed launch, the old app keeps capture paused and reports that copy; it must not resume duplicate hotkey monitors. |

These are required human checks, not implied by a green Tier 1 gate. Production installation and release publication remain separate.

## Evidence template

```
T2-1: capture <UUID> — pasted into TextEdit, text correct. PASS
T2-2: skipped — v3 backend not active.
...
```

A checklist run with no capture IDs is not evidence. If an item cannot be run,
record why — do not silently skip.
