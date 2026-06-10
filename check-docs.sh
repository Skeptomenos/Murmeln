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

if [[ "$fail" -ne 0 ]]; then
  echo "check-docs.sh: FAILED"
  exit 1
fi
echo "check-docs.sh: all drift checks green"
