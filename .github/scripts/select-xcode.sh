#!/bin/bash
# Selects the newest Xcode on the runner and records it in the job summary.
#
# GitHub rotates the default Xcode on its macOS images, so the version is
# discovered rather than hard-coded. The workflow prints what it chose, which is
# what makes a CI result reproducible after the fact.
set -euo pipefail

newest=""
newest_version=""

for app in /Applications/Xcode*.app; do
  [ -d "$app" ] || continue
  plist="$app/Contents/version.plist"
  [ -f "$plist" ] || continue
  version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$plist" 2>/dev/null || true)"
  [ -n "$version" ] || continue
  if [ -z "$newest_version" ] || [ "$(printf '%s\n%s\n' "$newest_version" "$version" | sort -V | tail -1)" = "$version" ]; then
    newest="$app"
    newest_version="$version"
  fi
done

if [ -z "$newest" ]; then
  echo "No Xcode installation found on this runner." >&2
  exit 1
fi

echo "Selected Xcode $newest_version at $newest"
sudo xcode-select --switch "$newest/Contents/Developer"

xcodebuild -version
swift --version

if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  {
    echo "### Toolchain"
    echo ""
    echo "- Xcode \`$newest_version\` (\`$newest\`)"
    echo "- \`$(swift --version 2>&1 | head -1)\`"
  } >> "$GITHUB_STEP_SUMMARY"
fi
