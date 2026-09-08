#!/bin/bash
# Build Dev with a stable local identity; never launch or overwrite a running app.
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd -P)
if [[ $# -gt 1 ]]; then
  echo "Usage: bash scripts/build-dev.sh [derived-data-directory]" >&2
  exit 2
fi

identity=$(/usr/bin/security find-identity -v -p codesigning | awk '/"Murmeln Dev"$/ {print $2}')
if [[ ! "$identity" =~ ^[[:xdigit:]]{40}$ ]]; then
  echo "A unique valid Murmeln Dev signing identity is required. Run bash scripts/setup-dev-signing.sh. No ad-hoc fallback is allowed." >&2
  exit 1
fi

derived_data="${1:-$root/build-dev}"
mkdir -p "$derived_data"
derived_data=$(cd "$derived_data" && pwd -P)
while IFS= read -r executable; do
  case "$executable" in
    "$derived_data"/*)
      echo "An app from this build directory is running. Choose a fresh output directory; this command will not stop it." >&2
      exit 1
      ;;
  esac
done < <(/bin/ps -axo comm=)

cd "$root"
xcodebuild -project Murmeln.xcodeproj -scheme "Murmeln Dev" -configuration "Debug Dev" \
  -derivedDataPath "$derived_data" CODE_SIGN_STYLE=Manual "CODE_SIGN_IDENTITY=$identity" \
  DEVELOPMENT_TEAM= build
app="$derived_data/Build/Products/Debug Dev/Murmeln Dev.app"
/usr/bin/codesign --verify --deep --strict \
  -R="identifier \"com.mrml.app.dev\" and certificate leaf = H\"$identity\"" "$app"
echo "Verified stable Dev build: $app"
echo "The app was not launched. Switching from an old ad-hoc build may require a fresh Accessibility grant."
