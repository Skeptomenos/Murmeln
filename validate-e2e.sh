#!/bin/bash
# Murmeln Tier 1.5 gate — real-runtime end-to-end tests (Phase 8, Slice 3).
# Downloads (or reuses) real FluidAudio models and transcribes the real
# fixture corpus. NOT part of Tier 1 (validate.sh): multi-GB model downloads
# and ~90s Cohere warm-up must not gate every checkbox. Mandatory before
# Slices 5, 6, and phase closeout (see the active phase plan).
#
# Prereq: a private user-dictated corpus supplied through
# MURMELN_E2E_FIXTURES_DIR. The private monorepo default is below _planning/;
# that directory is stripped from the public split.
set -euo pipefail
cd "$(dirname "$0")"

echo "━━━ validate-e2e.sh: real-runtime E2E (MURMELN_E2E=1) ━━━"
export MURMELN_E2E_FIXTURES_DIR="${MURMELN_E2E_FIXTURES_DIR:-$PWD/_planning/artifacts/phase-8/audio-fixtures}"
echo "Private fixture corpus: $MURMELN_E2E_FIXTURES_DIR"
export MURMELN_E2E_WHISPERKIT_VARIANT="${MURMELN_E2E_WHISPERKIT_VARIANT:-openai_whisper-small}"
export MURMELN_E2E_PROVISION_WHISPERKIT=1
echo "WhisperKit coexistence is mandatory; validation variant: $MURMELN_E2E_WHISPERKIT_VARIANT (downloaded if absent)."
MURMELN_E2E=1 swift test --filter RuntimeE2E &&
echo "" &&
echo "✅ validate-e2e.sh: E2E green"
