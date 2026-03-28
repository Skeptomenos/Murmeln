# Murmeln Index

> Last updated: 2026-03-28

## Project

- **Status:** poc
- **Tech:** Swift 6, SwiftUI, macOS, Apple Silicon
- **README:** `README.md`
- **Active Linear:** `DEV-33` — Murmeln truth pass and improvement roadmap
- **Active branch:** `apps/murmeln/DEV-33-truth-pass-roadmap`

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
- `docs/` — design notes, pipeline docs, and planning documents
- `specs/` — task-level spec/history docs
- `tasks/` — older PRD-style planning notes

## Key Docs

- `docs/audio-pipeline.md` — recording flow and warm-up state machine
- `docs/audio-cutoff-fix.md` — prior cutoff analysis and mitigation attempt
- `docs/state-machine-diagram.md` — visual state reference
- `README.md` — human-facing product description

## Planning Memory System

Use a lightweight router-plus-layers model.

| Layer | Active File | Purpose | Update When |
|---|---|---|---|
| Router | `index.md` | Points to the currently active planning files | Active file changes |
| Roadmap | `docs/plans/2026-03-28-murmeln-plan.md` | Strategy, phases, priorities, directives | Scope or priority changes |
| Findings | `docs/plans/2026-03-28-murmeln-findings.md` | Durable discoveries, evidence, and investigation notes | After investigation work |
| Phase Plan | `docs/plans/2026-03-28-murmeln-phase-0-truth-pass.md` | Execution-ready plan for the current phase | When a phase is ready to execute |

External tracker:

- `DEV-33` — short session summaries, links, and status tracking in Linear

## Planning Rules

- Write discoveries to the findings log first.
- Promote only confirmed scope or priority changes into the roadmap.
- Create a phase plan only when a phase is ready for execution.
- Archive superseded planning docs by replacing the active pointer here rather than editing history in place.
