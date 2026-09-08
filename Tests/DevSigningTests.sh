#!/bin/bash
# Real code-identity regression. Does not launch apps or access TCC/clipboard/audio.
set -euo pipefail
identity="${1:--}"
temporary=$(mktemp -d "${TMPDIR:-/tmp}/murmeln-signing-test.XXXXXX")
trap 'rm -rf "$temporary"' EXIT

for version in 1 2; do
  app="$temporary/version-$version.app"
  mkdir -p "$app/Contents/MacOS"
  cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.mrml.app.dev</string>
<key>CFBundleExecutable</key><string>fixture</string>
</dict></plist>
PLIST
  printf 'int main(void) { return %s; }\n' "$version" > "$temporary/main.c"
  /usr/bin/clang "$temporary/main.c" -o "$app/Contents/MacOS/fixture"
  /usr/bin/codesign --force --sign "$identity" --timestamp=none "$app"
  /usr/bin/codesign --verify --strict "$app"
done

first="$temporary/version-1.app"
second="$temporary/version-2.app"
old_requirement=$(/usr/bin/codesign -d -r- "$first" 2>&1 | sed -nE 's/^(# )?designated => //p')
new_requirement=$(/usr/bin/codesign -d -r- "$second" 2>&1 | sed -nE 's/^(# )?designated => //p')
old_hash=$(/usr/bin/codesign -dvvv "$first" 2>&1 | sed -n 's/^CDHash=//p')
new_hash=$(/usr/bin/codesign -dvvv "$second" 2>&1 | sed -n 's/^CDHash=//p')
[[ -n "$old_requirement" && -n "$new_requirement" && -n "$old_hash" && -n "$new_hash" && "$old_hash" != "$new_hash" ]]
echo "First CDHash: $old_hash"
echo "Second CDHash: $new_hash"
echo "Previous designated requirement: $old_requirement"
# This is the broken boundary: a changed binary must satisfy the old identity.
/usr/bin/codesign --verify --strict -R="$old_requirement" "$second"
[[ "$old_requirement" == "$new_requirement" ]]
echo "PASS: different binaries retain one designated requirement and satisfy the previous identity."
