# Murmeln Phase 0 Truth Pass Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Reconcile Murmeln's docs, specs, and code reality into one trustworthy source of truth so later cleanup, UX, and backend work starts from accurate context.

**Architecture:** This phase is discovery-heavy and documentation-first, but it is not cosmetic documentation work. The flow is: inventory reality, compare claims against code, record evidence in the findings log, then update the roadmap/router/docs so future sessions see the current truth first. Do not implement major features in this phase; focus on supported-surface clarity, drift removal, and explicit decisions about incomplete branches like WhisperKit.

**Tech Stack:** Markdown, Swift source inspection, Swift Package tests, Linear CLI, git branch workflow

---

### Task 1: Build the truth inventory

**Files:**
- Modify: `docs/plans/2026-03-28-murmeln-findings.md`
- Review: `README.md`
- Review: `specs/README.md`
- Review: `IMPLEMENTATION_PLAN.md`
- Review: `index.md`

**Step 1: Review human-facing and planning-facing claims**

Read:
- `README.md`
- `specs/README.md`
- `IMPLEMENTATION_PLAN.md`
- `index.md`

Capture contradictions around:
- current version
- current release/install instructions
- current status (`poc` vs implied maturity)
- supported features
- local-transcription story

**Step 2: Record findings before making edits**

Add findings entries to `docs/plans/2026-03-28-murmeln-findings.md` for each confirmed contradiction.

Use this shape:

```md
### YYYY-MM-DD - Short title
- Area:
- Confidence:
- Evidence:
- Impact:
- Next step:
```

**Step 3: Verify the inventory is actionable**

Check that the findings log now answers:
- what is contradicted?
- which file is wrong or stale?
- what decision is needed?

**Step 4: Commit**

```bash
git add docs/plans/2026-03-28-murmeln-findings.md
git commit -m "docs: record Murmeln truth-pass findings"
```

### Task 2: Audit the code-backed feature surface

**Files:**
- Modify: `docs/plans/2026-03-28-murmeln-findings.md`
- Review: `Sources/Models/Provider.swift`
- Review: `Sources/Models/AppSettings.swift`
- Review: `Sources/Services/NetworkService.swift`
- Review: `Sources/Services/ModelDiscoveryService.swift`
- Review: `Sources/Services/WhisperKitService.swift`
- Review: `Sources/Views/WhisperKitSetupView.swift`
- Review: `Sources/Views/SettingsView.swift`

**Step 1: Map the actual current feature surface**

Inspect the files above and answer, in the findings log:
- which transcription backends are actually wired and usable?
- which settings are actually backed by persisted data?
- which local features are incomplete or orphaned?
- which UI claims are real vs misleading?

**Step 2: Isolate the WhisperKit decision**

Create a dedicated findings section for WhisperKit with:
- code reality
- missing settings/state
- UI exposure state
- recommendation: quarantine, remove, or defer

**Step 3: Verify against docs claims**

Compare the code-backed surface with `README.md` and note mismatches in the findings log.

**Step 4: Commit**

```bash
git add docs/plans/2026-03-28-murmeln-findings.md
git commit -m "docs: audit Murmeln supported feature surface"
```

### Task 3: Define the supported-current-state docs

**Files:**
- Modify: `README.md`
- Modify: `index.md`
- Modify: `docs/plans/2026-03-28-murmeln-plan.md`
- Modify: `docs/plans/2026-03-28-murmeln-findings.md`

**Step 1: Update the roadmap if findings changed scope or priority**

Only change `docs/plans/2026-03-28-murmeln-plan.md` if the new evidence changes:
- phase ordering
- project directives
- major priorities

Do not dump raw evidence into the roadmap.

**Step 2: Update the router if active planning state changed**

Update `index.md` if needed so it still points to the active roadmap, findings log, and active phase plan.

**Step 3: Update README to reflect supported reality**

Adjust `README.md` so that it no longer over-claims:
- versions/releases
- local-transcription capabilities
- prompt/refinement trust level if currently misleading
- any feature whose current state is contradicted by code

Keep the README useful for humans; do not turn it into a planning diary.

**Step 4: Add a findings entry summarizing the supported-current-state decision**

Record the final documentation decision in `docs/plans/2026-03-28-murmeln-findings.md`.

**Step 5: Commit**

```bash
git add README.md index.md docs/plans/2026-03-28-murmeln-plan.md docs/plans/2026-03-28-murmeln-findings.md
git commit -m "docs: align Murmeln docs with code reality"
```

### Task 4: Verify repo truth and route the next phase

**Files:**
- Modify: `docs/plans/2026-03-28-murmeln-findings.md`
- Modify: `index.md`
- Test: `Tests/`

**Step 1: Run lightweight verification**

Run:

```bash
swift test
```

Expected:
- Existing test suite completes successfully, or any pre-existing failures are clearly identified and recorded.

**Step 2: Sanity-check active planning routes**

Verify `index.md` correctly points to:
- active roadmap
- active findings log
- active Phase 0 plan

If Phase 0 is complete by the end of execution, repoint `index.md` so the next active phase plan can replace it.

**Step 3: Record Phase 0 closure findings**

Add a final findings entry summarizing:
- what contradictions were resolved
- what remains unresolved
- what decision Phase 1 now depends on

**Step 4: Commit**

```bash
git add index.md docs/plans/2026-03-28-murmeln-findings.md docs/plans/2026-03-28-murmeln-phase-0-truth-pass.md
git commit -m "docs: finalize Murmeln phase 0 truth pass"
```

## Verification Checklist

- `README.md` no longer contradicts code reality on major product claims.
- `index.md` routes future sessions to the right active planning docs.
- `docs/plans/2026-03-28-murmeln-findings.md` contains evidence, not vague opinions.
- `docs/plans/2026-03-28-murmeln-plan.md` contains strategy, not investigation noise.
- WhisperKit has an explicit documented disposition.
- `swift test` was run and the result recorded.

## Handoff Notes for Phase 1

Phase 1 should start from the final findings here and focus on root-cause investigation for:
- ending cutoff
- rare beginning cutoff
- crashes
- latency breakdown

Do not begin large UI or architecture work until the truth pass is complete.
