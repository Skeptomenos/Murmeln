# Murmeln Truth Pass and Local-First Roadmap

> Living planning document for Murmeln. This is the umbrella roadmap for discovery, cleanup, refactoring, UX/UI improvement, performance work, and local-first backend evolution. Each major phase should later get its own implementation plan before execution.

**Date:** 2026-03-28

**Status:** Planning / active roadmap

**Linear:** `DEV-33` - Murmeln truth pass and improvement roadmap

**Branch:** `apps/murmeln/DEV-33-truth-pass-roadmap`

**Router:** `index.md`

**Findings log:** `docs/plans/2026-03-28-murmeln-findings.md`

## Goal

Turn Murmeln into a trustworthy, fast, local-first Apple Silicon dictation app that feels good enough to use every day, while giving future implementation sessions clear source-of-truth documentation and phased priorities.

## Product Directives

- Murmeln is `local first, cloud second`.
- Murmeln is optimized for `Apple Silicon`.
- Intel Macs are not a planning constraint.
- Development must not overwrite the daily-driver app during routine iteration; create and use `Murmeln Dev`.
- Work happens in `branches`, not worktrees, unless a future need changes that.
- Cleanup and refactoring must make future support for `CohereLabs/cohere-transcribe-03-2026` via `mlx-audio` feel natural, not invasive.

## Current Product Truth

- Murmeln is a macOS menu bar push-to-talk dictation app.
- Intended core loop: hold `Fn`, speak, release, transcribe, auto-paste.
- The app is already actively used in real life, so planning should optimize for daily-driver trust, not just abstract architecture quality.
- The repository still labels the project as `poc`, but the app has grown beyond a simple proof of concept.
- The current codebase contains drift between docs, specs, and code reality.
- The current local-transcription story is unclear: the app has a local server path today, plus incomplete/orphaned WhisperKit work, while the strategic direction is now Apple Silicon local-first.

## Known User Pain Points

### Highest priority

- Endings are still cut off, especially for short or normal-speed utterances when `Fn` is released soon after speaking.
- Beginnings are sometimes cut off, but less often.
- Word accuracy can be poor in ways that hurt trust, for example converting "code as clean" into "cloud as keen".
- The app sometimes crashes.
- Murmeln feels slower than comparable tools and should feel much snappier.

### Important but secondary

- The UI is ugly and overloaded.
- Some features and settings do not earn their complexity.
- Prompt/refinement behavior is not reliable enough to trust; prompt leakage and instruction confusion have led to refinement being turned off in real use.

## Roadmap Summary

| Phase | Priority | Effort | Outcome |
|---|---|---:|---|
| Phase 0 - Truth Pass | P0 | M | Docs, specs, and code reality aligned |
| Phase 1 - Capture Correctness and Stability | P0 | M-L | Murmeln becomes trustworthy for daily use |
| Phase 2 - Local-First Architecture Foundation | P1 | L | Backend model supports future local engines cleanly |
| Phase 3 - Safe Dogfooding Workflow | P1 | M | Development no longer breaks the production app |
| Phase 4 - Product Simplification | P1 | M | Reduced feature clutter and clearer happy path |
| Phase 5 - UX/UI Redesign | P1 | L | Cleaner, more intentional app experience |
| Phase 6 - Performance Hardening | P1 | M-L | Faster stop-to-paste experience |
| Phase 7 - Local-First Expansion | Strategic P1 / Execution P2 | L | Cohere + MLX path can land on a clean foundation |

## What We Know vs. What Still Needs Discovery

### High-confidence findings

- The core product idea is strong and differentiated.
- The runtime flow is understandable enough to refactor deliberately.
- Repo/documentation drift is real and is a P0 problem.
- `AppState` is too large and owns too much orchestration.
- `SettingsView` is too large and likely too complex for the current product state.
- `HistoryStore` likely has save-order race risk because persistence uses detached tasks.
- The current WhisperKit lane appears incomplete or split-brain.

### Medium-confidence findings

- Performance issues are visible in the code, but not yet measured rigorously end-to-end.
- The current provider/refinement model is likely too broad and confusing.
- Some settings and UX complexity may reflect implementation history rather than current product need.

### Discovery still required

- Exact technical cause of ending cutoff in real usage despite earlier fixes documented in `docs/audio-cutoff-fix.md`.
- Exact technical cause of rare beginning cutoff.
- Crash surfaces and their clustering across audio, hotkeys, paste, or network flows.
- Prompt leakage / refinement failure modes in the real code path.
- Which parts of the UI are merely visually weak vs structurally wrong.
- Actual latency breakdown from `Fn` release to pasted text.

## Architecture Principles to Protect

### 1. Backend abstraction over provider sprawl

Refactors should move Murmeln away from a single provider-enum mindset and toward backend types with explicit capabilities.

Target mental model:

- `Cloud backend`
- `Local server backend`
- `Local native backend`

Each backend should advertise capabilities such as:

- requires API key
- local vs networked
- supported languages
- one-call refinement support
- VAD or timestamp availability
- model installation requirements
- platform/runtime requirements

### 2. Apple Silicon first

Do not let Intel compatibility hold back architecture decisions. If a future local-native backend requires Apple Silicon assumptions, that is acceptable.

### 3. Local-first UX

The best Murmeln experience should eventually require:

- no cloud account
- no API key
- no external transcription server

Cloud should remain supported, but it is not the design center.

### 4. Cohere + MLX compatibility as a design constraint

Future support for `CohereLabs/cohere-transcribe-03-2026` through `mlx-audio` implies several architectural needs today:

- explicit language selection or routing, because the model expects a language tag
- support for Apple Silicon local-native backends
- local model lifecycle management
- clear runtime capability checks
- VAD or noise-gate strategy, because the model is eager to transcribe non-speech

This does **not** mean Cohere/MLX should be implemented immediately. It means the cleanup must prepare for it.

## Phase Details

## Phase 0 - Truth Pass

**Priority:** P0  
**Effort:** M

### Goal

Create a trustworthy source of truth across docs, specs, and code reality so future execution sessions do not operate on stale or contradictory assumptions.

### Why this comes first

Documentation cleanup by itself risks polishing lies. Current repo state suggests feature drift, version drift, and incomplete work branches.

### Scope

- Reconcile project status, release/version references, and supported-feature claims.
- Inventory features that are:
  - real and supported
  - partially implemented
  - dead or misleading
- Decide how to treat the current WhisperKit code path:
  - complete it later
  - quarantine it
  - remove it
- Update docs so future LLM execution sessions get clean context.

### Deliverables

- Feature truth inventory
- Documentation alignment pass
- Explicit "current supported product surface" section in docs
- Decision note on WhisperKit status

### Success criteria

- A new execution session can read the repo and understand the real app state without being misled.
- Major contradictions between README/specs/plan/code are removed or called out explicitly.

## Phase 1 - Capture Correctness and Stability

**Priority:** P0  
**Effort:** M-L

### Goal

Make Murmeln trustworthy for daily use before broader UX polish.

### Scope

- Investigate ending cutoff for short and normal utterances.
- Investigate rare beginning cutoff.
- Investigate crash causes and cluster them by subsystem.
- Improve diagnostics around recording start, recording stop, buffer drain, audio trimming, transcription, refinement, paste, and app failure.

### Notes

- `docs/audio-cutoff-fix.md` documents a previous fix, but lived reality says the problem still exists. That mismatch itself is a key input for this phase.
- This phase should focus first on trust, not feature growth.

### Deliverables

- Root-cause notes for cutoff and crash issues
- Repro checklist for short/normal dictation failures
- Stability-focused fixes and follow-up plan

### Success criteria

- Short and normal utterances no longer reliably lose final words.
- Cutoff issues have measurable before/after evidence.
- Crash handling and reproduction improve enough that failures can be tracked instead of guessed.

## Phase 2 - Local-First Architecture Foundation

**Priority:** P1  
**Effort:** L

### Goal

Refactor Murmeln so future local-native backends fit naturally.

### Scope

- Redesign the transcription backend abstraction.
- Separate cloud, local-server, and local-native concerns.
- Reduce orchestration pressure in `AppState`.
- Break down `SettingsView` into smaller, more coherent surfaces.
- Identify state and storage boundaries needed for model-backed local engines.

### Deliverables

- Architecture note for backend model and capabilities
- Refactor roadmap for oversized classes/views
- Clear path for future MLX integration

### Success criteria

- A future MLX/Cohere backend can be added without threading conditionals through unrelated UI and networking code.

## Phase 3 - Safe Dogfooding Workflow

**Priority:** P1  
**Effort:** M

### Goal

Stop breaking the production app during development.

### Scope

- Introduce `Murmeln Dev` as a separate app target or separate build identity.
- Separate bundle ID, settings, Application Support path, and history data for dev vs prod.
- Define a promotion checklist before replacing the daily-driver build.
- Keep macOS VM/emulator work as a later optional path, not a current blocker.

### Deliverables

- Safe dev-app workflow
- Dev/prod environment isolation
- Smoke checklist for promotion to daily-driver use

### Success criteria

- A broken experimental build no longer takes out the production app the user depends on.

## Phase 4 - Product Simplification

**Priority:** P1  
**Effort:** M

### Goal

Reduce complexity that does not currently help the user.

### Scope

- Audit settings and features for real value.
- Revisit prompt/refinement behavior and whether current UX should be simplified, hidden, or redesigned.
- Decide what the default Murmeln happy path is.
- Reduce the cognitive load of the app.

### Deliverables

- Feature audit
- Keep / simplify / remove decisions
- Default-path product definition

### Success criteria

- Murmeln becomes easier to understand and harder to misconfigure.

## Phase 5 - UX/UI Redesign

**Priority:** P1  
**Effort:** L

### Goal

Make Murmeln feel clear, deliberate, and pleasant.

### Scope

- Redesign settings information architecture.
- Improve history workflow and readability.
- Improve overlay and state feedback.
- Create a more intentional visual system and copy tone.

### Deliverables

- UI/UX design direction
- Surface-by-surface redesign plan
- Updated happy-path interaction model

### Success criteria

- The app looks and feels purposeful rather than accreted.

## Phase 6 - Performance Hardening

**Priority:** P1  
**Effort:** M-L

### Goal

Make Murmeln feel snappy in real daily use.

### Scope

- Measure latency from `Fn` release to text ready.
- Measure latency from text ready to paste completed.
- Identify avoidable work in the current processing pipeline.
- Compare local and cloud paths on perceived responsiveness.

### Deliverables

- Baseline performance measurements
- Latency breakdown by stage
- Priority optimization targets

### Success criteria

- Perceived responsiveness is competitive with alternative tools for the main daily-use path.

## Phase 7 - Local-First Expansion

**Priority:** Strategic P1 / Execution P2  
**Effort:** L

### Goal

Add serious Apple Silicon local transcription on top of a clean foundation.

### Scope

- Plan support for `CohereLabs/cohere-transcribe-03-2026` via `mlx-audio`.
- Design language selection/default behavior for a model that expects language input.
- Design VAD/noise-gate strategy for eager transcription behavior.
- Design model installation, storage, and lifecycle UX.

### Deliverables

- Backend integration design note
- UX note for local model setup and language handling
- Implementation plan for Cohere/MLX phase

### Success criteria

- Cohere/MLX can be added without rethinking the entire app architecture.

## Dogfooding and Testing Strategy

### Immediate policy

- Use `Murmeln Dev` for routine development and testing.
- Do not overwrite the production app during normal iteration.
- Use real-machine testing for hotkeys, microphone access, paste behavior, and overlay behavior.
- Defer macOS VM/emulator work until there is a clear test need it solves.

### Why this is the right first step

- Murmeln integrates deeply with the real desktop environment.
- Many bugs are tied to real hotkeys, permissions, clipboard behavior, and app focus.
- A separate dev app solves the current pain faster and more directly than setting up virtualization.

### Acceptance checklist before promoting a build

- Short utterance captures full ending
- Normal sentence captures full ending
- No beginning cutoff in normal use
- Paste succeeds in at least one primary target app
- No obvious prompt leakage
- No crash during repeated dictation runs

## Open Questions to Carry Forward

- Should prompt/refinement be redesigned, simplified, or temporarily de-emphasized until the core local path is stronger?
- Should WhisperKit be completed later, quarantined, or removed if MLX/Cohere becomes the preferred local path?
- What should the default local backend eventually be for Apple Silicon users?
- What performance target should define "snappy enough" for Murmeln?

## Immediate Next Planning Steps

1. Run the truth inventory across docs, specs, and current code.
2. Deep-dive the cutoff/stability issues with real reproduction notes.
3. Draft the backend capability model that supports local-first expansion.
4. Define the `Murmeln Dev` dogfooding workflow.
5. Convert Phase 0 into a dedicated implementation plan before execution.
