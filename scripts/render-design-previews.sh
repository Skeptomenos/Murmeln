#!/bin/bash
# Render the actual presentation components with sample data, offscreen.
set -euo pipefail
cd "$(dirname "$0")/.."
output="${1:-.build/ui-redesign}"
mkdir -p "$output"
swiftc -parse-as-library \
  Sources/Views/SettingsPresentation.swift \
  Sources/Views/HistoryPresentation.swift \
  Sources/Views/HistorySelectableText.swift \
  Sources/Models/HistoryEntry.swift \
  scripts/render-design-previews.swift \
  -o "$output/render-design-previews"
"$output/render-design-previews" "$output"
