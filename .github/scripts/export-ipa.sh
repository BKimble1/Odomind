#!/bin/bash
# Exports a signed App Store IPA from an archive.
#
#   export-ipa.sh <archive-path> <export-dir> <team-id> <key-path> <key-id> <issuer-id>
#
# Prints the path of the IPA on stdout's last line.
#
# Lives in a script rather than inline in the workflow because it writes a
# plist and retries with a second export method, and a heredoc nested inside a
# YAML block scalar is a well-known way to produce a file nobody can read.
set -euo pipefail

archive="$1"
export_dir="$2"
team="$3"
key_path="$4"
key_id="$5"
issuer="$6"

options="$(dirname "$export_dir")/ExportOptions.plist"

write_options() {
  local method="$1"
  cat > "$options" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>${method}</string>
  <key>teamID</key><string>${team}</string>
  <key>destination</key><string>export</string>
  <key>signingStyle</key><string>automatic</string>
  <key>uploadSymbols</key><true/>
  <!-- Xcode would otherwise pick its own build number, which is exactly the
       one thing App Store Connect has already been told to expect. -->
  <key>manageAppVersionAndBuildNumber</key><false/>
</dict>
</plist>
PLIST
}

attempt() {
  local method="$1"
  echo "Exporting with method '${method}'…"
  write_options "$method"
  rm -rf "$export_dir"
  xcodebuild -exportArchive \
    -archivePath "$archive" \
    -exportPath "$export_dir" \
    -exportOptionsPlist "$options" \
    -allowProvisioningUpdates \
    -authenticationKeyPath "$key_path" \
    -authenticationKeyID "$key_id" \
    -authenticationKeyIssuerID "$issuer"
}

# Xcode 15.3 renamed the App Store export method from "app-store" to
# "app-store-connect". Try the current name, fall back to the old one, so this
# works on either side of whatever the runner image ships.
if ! attempt "app-store-connect"; then
  echo "::warning::export with method 'app-store-connect' failed; retrying with 'app-store'"
  attempt "app-store"
fi

ipa="$(find "$export_dir" -name '*.ipa' -maxdepth 2 | head -1)"
if [ -z "$ipa" ]; then
  echo "::error::the export reported success but produced no .ipa" >&2
  exit 1
fi
echo "$ipa"
