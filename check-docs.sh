#!/bin/bash
# Murmeln doc drift checks (validate.sh stage 4).
# Grep-level cross-checks between prose and code: docs rot silently and no
# other gate stage reads them. Semantic doc review belongs to the independent
# verifier, not this script.
set -uo pipefail
cd "$(dirname "$0")"

fail=0
err() { echo "❌ check-docs: $1"; fail=1; }

# Doc surfaces that must not reference deleted/archived artifacts.
# _planning/ and specs_archive/ are history and exempt.
DOC_SURFACES=(README.md AGENTS.md index.md docs specs)

# 1. No references to files deleted by the 2026-06 cleanup.
for dead in loop.sh PROMPT_build.md PROMPT_plan.md; do
  hits=$(grep -rn --include='*.md' "$dead" "${DOC_SURFACES[@]}" 2>/dev/null || true)
  if [[ -n "$hits" ]]; then
    err "reference to deleted file '$dead':"$'\n'"$hits"
  fi
done

# 2. IMPLEMENTATION_PLAN.md is archived; live docs must not point at it
#    as if it still existed at the repo root.
hits=$(grep -rn --include='*.md' 'IMPLEMENTATION_PLAN.md' "${DOC_SURFACES[@]}" 2>/dev/null \
  | grep -v 'specs_archive/IMPLEMENTATION_PLAN.md' || true)
if [[ -n "$hits" ]]; then
  err "reference to IMPLEMENTATION_PLAN.md outside specs_archive/:"$'\n'"$hits"
fi

# 3. docs/audio-cutoff-fix.md must describe the design that exists in
#    Sources/Services/AudioService.swift: every audio constant the doc names
#    must be defined in the code (catches docs describing removed designs),
#    and stated seconds-values must match.
if [[ -f docs/audio-cutoff-fix.md ]]; then
  for const in drainThreshold maxWait stopGracePeriod preRollDurationSeconds; do
    if grep -q "$const" docs/audio-cutoff-fix.md && ! grep -q "$const" Sources/Services/AudioService.swift; then
      err "docs/audio-cutoff-fix.md names '$const' but AudioService.swift does not define it (stale design?)"
    fi
  done
  for const in stopGracePeriod preRollDurationSeconds; do
    code_val=$(grep -oE "$const: (TimeInterval|Double) = [0-9.]+" Sources/Services/AudioService.swift | grep -oE '[0-9.]+$' | head -1 || true)
    doc_val=$(grep -oE "\\\`$const\\\` \| [0-9.]+" docs/audio-cutoff-fix.md | grep -oE '[0-9.]+$' | head -1 || true)
    if [[ -n "$code_val" && -n "$doc_val" && "$code_val" != "$doc_val" ]]; then
      err "docs/audio-cutoff-fix.md states $const = $doc_val but AudioService.swift has $code_val"
    fi
  done
  # Tap-swapping was removed; the doc must not present it as the current design.
  if grep -qiE 'tap[- ]swap' docs/audio-cutoff-fix.md && ! grep -qiE 'tap[- ]swap' Sources/Services/AudioService.swift; then
    err "docs/audio-cutoff-fix.md describes tap-swapping but AudioService.swift has no such mechanism"
  fi
fi

# 4. AGENTS.md must document the gate, and every stage command it lists must
#    literally appear in validate.sh (prose and script may not drift apart).
if ! grep -q 'validate.sh' AGENTS.md; then
  err "AGENTS.md does not mention validate.sh as the validation gate"
fi
# Stage commands declared in AGENTS.md between the gate markers:
stage_cmds=$(sed -n '/<!-- gate-stages-begin -->/,/<!-- gate-stages-end -->/p' AGENTS.md | grep -E '^- `' | sed -E 's/^- `([^`]+)`.*/\1/')
if [[ -z "$stage_cmds" ]]; then
  err "AGENTS.md is missing the gate-stages block (<!-- gate-stages-begin/end -->)"
else
  while IFS= read -r cmd; do
    if ! grep -qF "$cmd" validate.sh; then
      err "AGENTS.md lists gate stage '$cmd' but validate.sh does not contain it"
    fi
  done <<< "$stage_cmds"
fi

# 5. Phase 8 retired the user-managed Python/Cohere bridge. Current docs must
#    describe the in-process catalog runtimes instead of resurrecting setup
#    instructions or deleted artifact names. Planning archives remain exempt.
for retired in 'mlx-audio' 'pip install' 'cohere_bridge.py'; do
  hits=$(grep -rni --include='*.md' -- "$retired" README.md AGENTS.md index.md docs 2>/dev/null || true)
  if [[ -n "$hits" ]]; then
    err "current docs reference retired bridge term '$retired':"$'\n'"$hits"
  fi
done

# 6. The shipped source/test graphs must not regain the deleted bridge stack.
#    Legacy migration values are plain strings and intentionally do not use
#    these implementation identifiers.
bridge_hits=$(grep -rnE 'CohereMLXService|cohere_bridge\.py|mlx_audio' Sources Tests Package.swift Murmeln.xcodeproj 2>/dev/null || true)
if [[ -n "$bridge_hits" ]]; then
  err "retired Python bridge remains in the shipped graph:"$'\n'"$bridge_hits"
fi

# 7. The public split publishes everything except private planning content.
#    Real-user voice is biometric/personal data and must remain below
#    _planning/ (or be supplied externally at E2E runtime), never in the
#    publishable source/test tree.
publishable_audio=$(find . \
  -path './_planning' -prune -o \
  -path './.build' -prune -o \
  -path './build' -prune -o \
  -path './DerivedData' -prune -o \
  -type f \( \
    -iname '*.wav' -o -iname '*.m4a' -o -iname '*.mp3' -o \
    -iname '*.aac' -o -iname '*.caf' -o -iname '*.flac' -o \
    -iname '*.aiff' -o -iname '*.aif' \
  \) -print | sort)
if [[ -n "$publishable_audio" ]]; then
  err "recorded audio exists in the publishable tree; move it under _planning/ or supply MURMELN_E2E_FIXTURES_DIR:"$'\n'"$publishable_audio"
fi

# 8. Reproduce the split workflow's sanitized package copy and inspect the
#    generated export itself. This catches privacy regressions that a source
#    path convention cannot prove, including leaked transcripts/diagnostics and
#    text-only probe artifacts. The synthetic regression also proves the guard
#    rejects leaks while allowing private files removed with _planning/.
if ! bash Tests/PublicSplitPrivacyTests.sh; then
  err "public-split privacy regression suite failed"
fi
if ! bash check-public-split.sh; then
  err "generated Murmeln public split contains private artifacts"
fi

# 9. The active Phase 8 headline and follow-up must agree with the shipped
#    four-entry catalog. Qwen3-ASR was disproven at the pinned FluidAudio tag;
#    it is follow-on work, not a Phase 8 acceptance claim.
PHASE_8_PLAN="_planning/plans/2026-07-08-murmeln-phase-8-local-runtime-catalog.md"
phase_8_goal=$(grep -m1 '^\*\*Goal:\*\*' "$PHASE_8_PLAN" || true)
if grep -qi 'Qwen3-ASR' <<< "$phase_8_goal"; then
  err "Phase 8 goal still promises Qwen3-ASR although the shipped catalog defers it"
fi
if ! grep -qE '^-[[:space:]]+\[ \].*MLXAudioRuntime.*Qwen3-ASR 0\.6B/1\.7B' "$PHASE_8_PLAN"; then
  err "Phase 8 follow-ups do not explicitly defer both Qwen3-ASR 0.6B and 1.7B"
fi

# 10. A green Tier 1.5 gate must exercise WhisperKit + FluidAudio coexistence.
#     An optional/acknowledged return makes the advertised six-test gate pass
#     without running the cross-runtime boundary Alfred asked it to prove.
whisper_optional_hits=$(grep -n 'MURMELN_E2E_WHISPERKIT_OPTIONAL' \
  validate-e2e.sh Tests/RuntimeE2E/FluidAudioRuntimeE2ETests.swift 2>/dev/null || true)
if [[ -n "$whisper_optional_hits" ]]; then
  err "Tier 1.5 still permits an optional WhisperKit coexistence pass:"$'\n'"$whisper_optional_hits"
fi
if ! grep -qF 'try #require(whisper.isModelDownloaded(variant)' Tests/RuntimeE2E/FluidAudioRuntimeE2ETests.swift; then
  err "WhisperKit coexistence test does not require the selected variant to be installed"
fi

# 11. The two planning routers must identify the same active and most-recently
#     completed plans. A merged phase must not remain active or advertise an
#     obsolete review state.
project_active_plan=$(sed -nE 's/^- \*\*Active phase plan:\*\* `([^`]+)`.*/\1/p' index.md | head -1)
planning_active_plan=$(sed -nE 's/^- Phase Plan: `([^`]+)`.*/\1/p' _planning/index.md | head -1)
project_completed_plan=$(sed -nE 's/^- \*\*Last completed phase plan:\*\* `([^`]+)`.*/\1/p' index.md | head -1)
planning_completed_plan=$(sed -nE 's/^- Last completed phase plan: `([^`]+)`.*/\1/p' _planning/index.md | head -1)

if [[ -z "$project_active_plan" || -z "$planning_active_plan" ]]; then
  err "planning routers must both name an active phase plan"
elif [[ "$project_active_plan" != "$planning_active_plan" ]]; then
  err "planning routers disagree on the active phase plan: index.md='$project_active_plan', _planning/index.md='$planning_active_plan'"
elif [[ ! -f "$project_active_plan" ]]; then
  err "active phase plan does not exist: $project_active_plan"
elif ! grep -qE '^\*\*Status:\*\* Active' "$project_active_plan"; then
  err "active phase plan does not declare an Active status: $project_active_plan"
fi

if [[ -z "$project_completed_plan" || -z "$planning_completed_plan" ]]; then
  err "planning routers must both name the last completed phase plan"
elif [[ "$project_completed_plan" != "$planning_completed_plan" ]]; then
  err "planning routers disagree on the last completed phase plan: index.md='$project_completed_plan', _planning/index.md='$planning_completed_plan'"
elif [[ ! -f "$project_completed_plan" ]]; then
  err "last completed phase plan does not exist: $project_completed_plan"
elif ! grep -qE '^\*\*Status:\*\* Completed' "$project_completed_plan"; then
  err "last completed phase plan does not declare a Completed status: $project_completed_plan"
fi

if [[ "$project_active_plan" == "$PHASE_8_PLAN" || "$planning_active_plan" == "$PHASE_8_PLAN" ]]; then
  err "merged Phase 8 plan is still routed as active"
fi
if ! grep -qE '^\*\*Status:\*\* Completed .*PR #217.*7592218' "$PHASE_8_PLAN"; then
  err "Phase 8 plan does not record PR #217 and merge commit 7592218 as completed"
fi
phase_8_stale_review=$(grep -niE 'ready for Alfred review|re-review pending' \
  index.md _planning/index.md "$PHASE_8_PLAN" 2>/dev/null || true)
if [[ -n "$phase_8_stale_review" ]]; then
  err "current planning docs retain a stale Phase 8 review state:"$'\n'"$phase_8_stale_review"
fi

if [[ "$fail" -ne 0 ]]; then
  echo "check-docs.sh: FAILED"
  exit 1
fi
echo "check-docs.sh: all drift checks green"
