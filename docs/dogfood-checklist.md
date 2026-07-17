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
| T2-1 | English short dictation (hold Fn, speak one sentence, release) into a native app (e.g. TextEdit, Notes) | Transcribed text pastes at the cursor; diagnostics show `outcome=pasted` for the capture ID |
| T2-2 | German dictation (only if a German-capable model, e.g. parakeet v3, is the active backend) | Correct German text pastes; no transliteration garbage |
| T2-3 | Lock mode: engage (quick Right-Option per current binding), speak, disengage | Recording starts on engage, stops on disengage, exactly one paste; no zombie recording after disengage |
| T2-4 | Paste into an Electron app (e.g. VS Code, Slack) | Text lands in the Electron app; clipboard behavior matches T2-1 |
| T2-5 | Refinement provider down (point refinement at an unreachable provider, then dictate) | Raw transcript still pastes and appears in history with the refinement-failed marker; transcript is NOT lost (B2 behavior) |
| T2-6 | Paste failure surface (revoke Accessibility, dictate) | App reports paste failure, transcript remains on the clipboard for manual paste (B1 behavior); diagnostics show a failure outcome, not a fabricated success |
| T2-7 | Phase 8 fresh install: wipe Dev defaults (`defaults delete com.mrml.app.dev` or the Dev bundle id), launch Murmeln Dev | Settings show Parakeet v3 selected with a "Download Model" button — no error state, no Python mention, no terminal needed |
| T2-8 | Phase 8 model lifecycle: start two not-installed model downloads, switch between them, cancel one and retry it; let one finish, then delete it from Settings | Each row keeps only its own live progress and distinct downloads advance independently (or visibly queue). Cancel returns that model to Download Model without affecting the other transfer; retry completes to Ready with no late cancellation error. Delete Model asks for confirmation, removes the cache, and returns the row to Download Model; a dictation with the remaining installed model pastes correctly |
| T2-9 | Phase 8 model switch: switch Parakeet v3 → WhisperKit → back via the unified picker | Each switch shows only that model's download/load state, warms the selected installed model, and supports dictation after each switch; exactly one selection persists |
| T2-10 | Phase 8 long dictation (only if Cohere INT8 selected): lock mode, dictate >35 s continuously | One coherent paste (long-form chunk path); no truncation at the 35 s boundary |
| T2-11 | Phase 8 migration: on a profile that previously used WhisperKit or the Cohere bridge, launch the new build | The equivalent catalog model is selected; language preference carried over; no re-setup required |

## Evidence template

```
T2-1: capture <UUID> — pasted into TextEdit, text correct. PASS
T2-2: skipped — v3 backend not active.
...
```

A checklist run with no capture IDs is not evidence. If an item cannot be run,
record why — do not silently skip.
