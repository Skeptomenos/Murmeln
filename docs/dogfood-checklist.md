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

## Evidence template

```
T2-1: capture <UUID> — pasted into TextEdit, text correct. PASS
T2-2: skipped — v3 backend not active.
...
```

A checklist run with no capture IDs is not evidence. If an item cannot be run,
record why — do not silently skip.
