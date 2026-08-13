#!/bin/bash
set -euo pipefail

APP_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CHECKER="$APP_ROOT/check-public-split.sh"
LIST_PUBLISHABLE_AUDIO="$APP_ROOT/scripts/list-publishable-audio.sh"
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

# A local ignored worktree is not part of a Git checkout or public split. The
# source-level audio guard must still reject a real publishable working-tree
# file while ignoring local caches and private _planning fixtures.
AUDIO_CANDIDATE_ROOT="$FIXTURE_ROOT/audio-candidates"
mkdir -p \
    "$AUDIO_CANDIDATE_ROOT/.claude/worktrees/stale" \
    "$AUDIO_CANDIDATE_ROOT/_planning/audio-fixtures" \
    "$AUDIO_CANDIDATE_ROOT/Tests/Fixtures"
git init -q "$AUDIO_CANDIDATE_ROOT"
printf '.claude/worktrees/\n' > "$AUDIO_CANDIDATE_ROOT/.gitignore"
printf 'tracked source\n' > "$AUDIO_CANDIDATE_ROOT/README.md"
printf 'ignored dependency audio' > "$AUDIO_CANDIDATE_ROOT/.claude/worktrees/stale/dependency.wav"
printf 'private voice' > "$AUDIO_CANDIDATE_ROOT/_planning/audio-fixtures/private.wav"
git -C "$AUDIO_CANDIDATE_ROOT" add .gitignore README.md _planning/audio-fixtures/private.wav

audio_candidates=$(bash "$LIST_PUBLISHABLE_AUDIO" "$AUDIO_CANDIDATE_ROOT")
if [[ -n "$audio_candidates" ]]; then
    echo "❌ public-split test: ignored or private audio was classified as publishable:"
    echo "$audio_candidates"
    exit 1
fi

printf 'publishable voice' > "$AUDIO_CANDIDATE_ROOT/Tests/Fixtures/leaked.wav"
audio_candidates=$(bash "$LIST_PUBLISHABLE_AUDIO" "$AUDIO_CANDIDATE_ROOT")
if [[ "$audio_candidates" != *"Tests/Fixtures/leaked.wav"* ]]; then
    echo "❌ public-split test: publishable working-tree audio was not detected"
    exit 1
fi

printf 'publishable uppercase voice' > "$AUDIO_CANDIDATE_ROOT/Tests/Fixtures/UPPER.WAV"
audio_candidates=$(bash "$LIST_PUBLISHABLE_AUDIO" "$AUDIO_CANDIDATE_ROOT")
if [[ "$audio_candidates" != *"Tests/Fixtures/UPPER.WAV"* ]]; then
    echo "❌ public-split test: uppercase publishable audio was not detected"
    exit 1
fi

echo "✅ PublicSplitPrivacyTests: private content stripped; public leaks rejected"
