#!/bin/bash
# Murmeln Tier 1 validation gate — the single command that defines "done".
# Per the self-correction-loop skill: one deterministic, indivisible command
# chaining ALL checks with &&. Never run a subset and call it the gate.
#
# Tier 2 (human dogfood checklist, capture-ID evidence) is documented in
# docs/dogfood-checklist.md and is required before release/phase closeout.
set -uo pipefail
cd "$(dirname "$0")"

stage() { echo ""; echo "━━━ validate.sh stage: $1 ━━━"; }

stage "swift build" &&
swift build &&
stage "swift test" &&
swift test &&
stage "xcodebuild Murmeln Dev" &&
xcodebuild -project Murmeln.xcodeproj -scheme "Murmeln Dev" -configuration "Debug Dev" build -quiet &&
stage "doc drift checks" &&
bash check-docs.sh &&
stage "git diff --check" &&
git diff --check &&
echo "" &&
echo "✅ validate.sh: all stages green"
