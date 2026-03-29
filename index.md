# Murmeln Index

> Last updated: 2026-03-29

## Project

- **Status:** poc
- **Tech:** Swift 6, SwiftUI, macOS, Apple Silicon
- **README:** `README.md`
- **Active roadmap Linear:** `DEV-33` — Murmeln truth pass and improvement roadmap
- **Active phase Linear:** none currently active
- **Last completed phase Linear:** `DEV-38` — Phase 2: Murmeln capture correctness and stability
- **Active phase plan:** none currently active
- **Last completed phase plan:** `_planning/plans/2026-03-29-murmeln-phase-2-capture-correctness-and-stability.md`
- **Recommended execution branch:** none until the next phase is promoted

## Commands

```bash
# Build (debug)
swift build

# Build (release via xcodebuild)
xcodebuild -scheme Murmeln -configuration Release -derivedDataPath build build

# Run all tests
swift test

# Run a single test file
swift test --filter AppStateTests

# Run a single test method
swift test --filter "AppStateTests/initialStateIsIdle"

# Run tests matching pattern
swift test --filter "HotkeyService"

# Install release build to /Applications
cp -r build/Build/Products/Release/Murmeln.app /Applications/
```

## Structure

- `Sources/` — app entry, state, services, and SwiftUI views
- `Tests/` — Swift Testing suites
- `docs/` — public design notes, pipeline docs, and historical implementation references
- `_planning/` — private planning docs, findings, and execution plans
- `specs/` — task-level spec/history docs
- `tasks/` — older PRD-style planning notes

## Key Docs

- `docs/architecture-overview.md` — short current-state technical map
- `docs/audio-pipeline.md` — recording flow and warm-up state machine
- `docs/audio-cutoff-fix.md` — prior cutoff analysis and mitigation attempt
- `docs/state-machine-diagram.md` — deep visual reference; not the first authority for current-state truth
- `_planning/index.md` — planning catalog and active planning files
- `README.md` — human-facing product description

## Document Authority

When docs disagree, use this order:

1. `README.md` — current human-facing product story and supported state
2. `docs/architecture-overview.md` — current top-layer technical truth
3. `_planning/plans/2026-03-28-murmeln-findings.md` — evidence and unresolved contradictions
4. `_planning/plans/2026-03-28-murmeln-plan.md` — strategy, priorities, and phase ordering
5. Deep references like `docs/audio-pipeline.md`, `docs/state-machine-diagram.md`, `specs/README.md`, and `IMPLEMENTATION_PLAN.md` — useful context, but not authoritative when stale

## Planning Memory System

Use a lightweight router-plus-layers model.

| Layer | Active File | Purpose | Update When |
|---|---|---|---|
| Router | `index.md` | Points to the currently active planning files | Active file changes |
| Roadmap | `_planning/plans/2026-03-28-murmeln-plan.md` | Strategy, phases, priorities, directives | Scope or priority changes |
| Findings | `_planning/plans/2026-03-28-murmeln-findings.md` | Durable discoveries, evidence, and investigation notes | After investigation work |
| Phase Plan | `none currently active` (last completed: `_planning/plans/2026-03-29-murmeln-phase-2-capture-correctness-and-stability.md`) | Execution-ready plan for the current phase | When the active phase changes |

External tracker:

- `DEV-33` — umbrella roadmap tracking in Linear
- `DEV-38` — completed Phase 2 execution tracking in Linear
- `DEV-37` — completed Phase 1 execution tracking in Linear

## Planning Rules

- Write discoveries to the findings log first.
- Promote only confirmed scope or priority changes into the roadmap.
- Create a phase plan only when a phase is ready for execution.
- Archive superseded planning docs by replacing the active pointer here rather than editing history in place.
