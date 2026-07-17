#!/bin/bash
# Build the same package tree that split.yml hands to the pinned public-split
# action, then assert that private/runtime artifacts cannot be published.
set -euo pipefail

APP_ROOT="$(cd "$(dirname "$0")" && pwd)"
SOURCE_ROOT="${1:-$APP_ROOT}"

if [[ ! -d "$SOURCE_ROOT" ]]; then
    echo "❌ check-public-split: source directory does not exist: $SOURCE_ROOT"
    exit 1
fi

WORK_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/murmeln-public-split.XXXXXX")"
SANITIZED_ROOT="$WORK_ROOT/sanitized"
EXPORT_ROOT="$WORK_ROOT/export"
VIOLATIONS_FILE="$WORK_ROOT/violations.txt"
trap 'rm -rf "$WORK_ROOT"' EXIT
mkdir -p "$SANITIZED_ROOT" "$EXPORT_ROOT"

# split.yml removes every directory named _planning before invoking
# danharrin/monorepo-split-github-action@v2.4.4. A fresh Actions checkout has
# none of the local build products excluded below. The pinned action then does
# `cp -ra <package_directory>/. <build_directory>`; the second copy mirrors it.
(
    cd "$SOURCE_ROOT"
    tar \
        --exclude='./.git' \
        --exclude='./.build' \
        --exclude='./build' \
        --exclude='./DerivedData' \
        --exclude='./_planning' \
        --exclude='*/_planning' \
        -cf - .
) | (
    cd "$SANITIZED_ROOT"
    tar -xf -
)
cp -a "$SANITIZED_ROOT"/. "$EXPORT_ROOT"

: > "$VIOLATIONS_FILE"

# Defense in depth: the export itself, not the source path, is authoritative.
find "$EXPORT_ROOT" -type d -name '_planning' -print >> "$VIOLATIONS_FILE"

find "$EXPORT_ROOT" -type f \( \
    -iname '*.wav' -o -iname '*.m4a' -o -iname '*.mp3' -o \
    -iname '*.aac' -o -iname '*.caf' -o -iname '*.flac' -o \
    -iname '*.aiff' -o -iname '*.aif' \
\) -print >> "$VIOLATIONS_FILE"

# Phase 8's private fixture transcripts and runtime diagnostics are unsafe
# even without their matching audio. Probe paths include source, results,
# compiled products, and timing captures because the path component is enough
# to identify their private provenance.
find "$EXPORT_ROOT" -type f \( \
    -ipath '*probe*' -o \
    -iname 'capture-diagnostics.jsonl' -o \
    -iname 'history.json' -o \
    -iname 'short_en.txt' -o -iname 'short_de.txt' -o \
    -iname 'medium_en.txt' -o -iname 'medium_de.txt' -o \
    -iname 'long_en.txt' \
\) -print >> "$VIOLATIONS_FILE"

if [[ -s "$VIOLATIONS_FILE" ]]; then
    echo "❌ check-public-split: private artifacts exist in the generated public export:"
    sed "s#^$EXPORT_ROOT/##" "$VIOLATIONS_FILE" | sort -u
    exit 1
fi

echo "✅ check-public-split: generated public export contains no private artifacts"
