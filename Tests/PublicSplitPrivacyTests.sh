#!/bin/bash
set -euo pipefail

APP_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CHECKER="$APP_ROOT/check-public-split.sh"
FIXTURE_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/murmeln-public-split-test.XXXXXX")"
trap 'rm -rf "$FIXTURE_ROOT"' EXIT

mkdir -p "$FIXTURE_ROOT/_planning/audio-fixtures" "$FIXTURE_ROOT/Tests/Fixtures"
printf 'private voice' > "$FIXTURE_ROOT/_planning/audio-fixtures/private.wav"
printf 'private transcript' > "$FIXTURE_ROOT/_planning/audio-fixtures/short_en.txt"
printf '# Synthetic split fixture\n' > "$FIXTURE_ROOT/README.md"

# The workflow removes _planning before the split action copies the package.
# A private recording/transcript below that boundary must therefore pass.
bash "$CHECKER" "$FIXTURE_ROOT" >/dev/null

assert_public_leak_rejected() {
    local relative_path="$1"
    local label="$2"
    local leak_path="$FIXTURE_ROOT/$relative_path"
    mkdir -p "$(dirname "$leak_path")"
    printf 'private data' > "$leak_path"
    if bash "$CHECKER" "$FIXTURE_ROOT" >/dev/null 2>&1; then
        echo "❌ public-split test: publishable $label was accepted"
        exit 1
    fi
    rm "$leak_path"
}

assert_public_leak_rejected "Tests/Fixtures/leaked.wav" "audio leak"
assert_public_leak_rejected "Tests/Fixtures/short_en.txt" "transcript leak"
assert_public_leak_rejected "Tests/Fixtures/capture-diagnostics.jsonl" "diagnostics leak"
assert_public_leak_rejected "Tests/Fixtures/history.json" "history leak"
assert_public_leak_rejected "Tests/Fixtures/runtime-probe-results.md" "probe artifact"
assert_public_leak_rejected "Tests/Fixtures/runtime-probe/results.txt" "probe path"

echo "✅ PublicSplitPrivacyTests: private content stripped; public leaks rejected"
