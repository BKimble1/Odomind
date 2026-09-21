#!/bin/bash
# Manual distribution only. Never enable shell tracing around credentials.
set -euo pipefail
umask 077

signing_dir="${RUNNER_TEMP:?}/odomind-signing"
keychain_path="$signing_dir/signing.keychain-db"
profile_dir="$HOME/Library/MobileDevice/Provisioning Profiles"

case "${1:-}" in
  prepare)
    mkdir -p "$signing_dir"
    python3 - <<'PY'
import base64, os, pathlib, re
root = pathlib.Path(os.environ['RUNNER_TEMP']) / 'odomind-signing'
if not re.fullmatch(r'[A-Z0-9]{10}', os.environ.get('APPLE_TEAM_ID', '')):
    raise SystemExit('Set the APPLE_TEAM_ID variable in the testflight environment.')
for key, filename in [('BUILD_CERTIFICATE_BASE64', 'certificate.p12'),
                      ('BUILD_PROVISION_PROFILE_BASE64', 'profile.mobileprovision')]:
    value = os.environ.get(key, '')
    if not value:
        raise SystemExit('Missing environment secret: ' + key)
    try:
        decoded = base64.b64decode(''.join(value.split()), validate=True)
    except ValueError:
        raise SystemExit(key + ' must contain base64-encoded file bytes.')
    (root / filename).write_bytes(decoded)
if not os.environ.get('P12_PASSWORD'):
    raise SystemExit('Set P12_PASSWORD to the nonempty certificate export password.')
PY
    security cms -D -i "$signing_dir/profile.mobileprovision" > "$signing_dir/profile.plist"
    python3 - <<'PY'
import datetime, hashlib, os, pathlib, plistlib, re
root = pathlib.Path(os.environ['RUNNER_TEMP']) / 'odomind-signing'
with (root / 'profile.plist').open('rb') as f:
    profile = plistlib.load(f)
team = os.environ['APPLE_TEAM_ID']
entitlements = profile.get('Entitlements', {})
prefixes = profile.get('ApplicationIdentifierPrefix', [])
expected = [p + '.com.idlery.odomind' for p in prefixes]
if entitlements.get('application-identifier') not in expected:
    raise SystemExit('Profile must match the explicit bundle ID com.idlery.odomind.')
if team not in profile.get('TeamIdentifier', []):
    raise SystemExit('Profile belongs to a different Apple team.')
if (entitlements.get('get-task-allow', False) or profile.get('ProvisionedDevices')
        or profile.get('ProvisionsAllDevices', False)
        or not entitlements.get('beta-reports-active', False)):
    raise SystemExit('Use an App Store Connect distribution profile, not development/ad hoc/enterprise.')
if profile['ExpirationDate'] <= datetime.datetime.now(datetime.timezone.utc).replace(tzinfo=None):
    raise SystemExit('Provisioning profile has expired; generate a new one.')
uuid = profile['UUID']
if not re.fullmatch(r'[A-Fa-f0-9-]{36}', uuid):
    raise SystemExit('Invalid profile UUID.')
certificates = profile.get('DeveloperCertificates', [])
if len(certificates) != 1:
    raise SystemExit('Expected a single distribution certificate in the profile.')
fingerprint = hashlib.sha1(certificates[0]).hexdigest().upper()
(root / 'profile-uuid').write_text(uuid)
(root / 'certificate-sha1').write_text(fingerprint)
with (root / 'ExportOptions.plist').open('wb') as f:
    plistlib.dump({'method': 'app-store-connect', 'destination': 'export',
                  'teamID': team, 'signingStyle': 'manual',
                  'signingCertificate': fingerprint,
                  'provisioningProfiles': {'com.idlery.odomind': uuid},
                  'manageAppVersionAndBuildNumber': False, 'uploadSymbols': True}, f)
PY
    keychain_password="$(openssl rand -hex 32)"
    echo "::add-mask::$keychain_password"
    security create-keychain -p "$keychain_password" "$keychain_path"
    security set-keychain-settings -lut 3600 "$keychain_path"
    security unlock-keychain -p "$keychain_password" "$keychain_path"
    security import "$signing_dir/certificate.p12" -P "$P12_PASSWORD" -A -t cert -f pkcs12 -k "$keychain_path" >/dev/null
    security set-key-partition-list -S apple-tool:,apple:,codesign: -k "$keychain_password" "$keychain_path" >/dev/null
    security list-keychains -d user -s "$keychain_path" "$HOME/Library/Keychains/login.keychain-db"
    certificate_sha1="$(cat "$signing_dir/certificate-sha1")"
    security find-identity -v -p codesigning "$keychain_path" | grep -Fq "$certificate_sha1" || {
      echo 'The P12 needs the valid private key/certificate selected in this profile.' >&2
      exit 1
    }
    mkdir -p "$profile_dir"
    profile_uuid="$(cat "$signing_dir/profile-uuid")"
    cp "$signing_dir/profile.mobileprovision" "$profile_dir/$profile_uuid.mobileprovision"
    ;;

  archive)
    profile_uuid="$(cat "$signing_dir/profile-uuid")"
    certificate_sha1="$(cat "$signing_dir/certificate-sha1")"
    xcodebuild archive \
      -project Odomind.xcodeproj -scheme Odomind -configuration Release \
      -destination 'generic/platform=iOS' \
      -archivePath "$RUNNER_TEMP/Odomind.xcarchive" \
      -derivedDataPath "$RUNNER_TEMP/OdomindDerivedData" \
      DEVELOPMENT_TEAM="$APPLE_TEAM_ID" \
      PRODUCT_BUNDLE_IDENTIFIER=com.idlery.odomind \
      CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
      CODE_SIGN_STYLE=Manual \
      CODE_SIGN_IDENTITY="$certificate_sha1" \
      PROVISIONING_PROFILE_SPECIFIER="$profile_uuid" \
      OTHER_CODE_SIGN_FLAGS="--keychain $keychain_path"
    xcodebuild -exportArchive \
      -archivePath "$RUNNER_TEMP/Odomind.xcarchive" \
      -exportPath "$RUNNER_TEMP/OdomindExport" \
      -exportOptionsPlist "$signing_dir/ExportOptions.plist"
    test -f "$RUNNER_TEMP/OdomindExport/Odomind.ipa"
    ;;

  upload)
    # API authentication is separate from the distribution signing identity.
    mkdir -p "$signing_dir/private_keys"
    python3 - <<'PY'
import os, pathlib, re
root = pathlib.Path(os.environ['RUNNER_TEMP']) / 'odomind-signing/private_keys'
key = os.environ.get('ASC_KEY_ID', '')
issuer = os.environ.get('ASC_ISSUER_ID', '')
private = os.environ.get('ASC_PRIVATE_KEY', '').strip()
if not re.fullmatch(r'[A-Z0-9]{10}', key):
    raise SystemExit('ASC_KEY_ID must be the 10-character API Key ID.')
if not re.fullmatch(r'[a-fA-F0-9-]{36}', issuer):
    raise SystemExit('ASC_ISSUER_ID must be the team API issuer UUID, not the Apple Team ID.')
if not private.startswith('-----BEGIN PRIVATE KEY-----') or not private.endswith('-----END PRIVATE KEY-----'):
    raise SystemExit('ASC_PRIVATE_KEY must contain the complete .p8 text, including its header/footer.')
(root / ('AuthKey_' + key + '.p8')).write_text(private + '\n')
PY
    # altool discovers API keys in ./private_keys; keep them outside checkout.
    cd "$signing_dir"
    xcrun altool --upload-app --type ios \
      --file "$RUNNER_TEMP/OdomindExport/Odomind.ipa" \
      --apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER_ID"
    {
      echo '### Odomind uploaded to App Store Connect'
      echo "Build: $BUILD_NUMBER"
      echo "Commit: $GITHUB_SHA"
      echo 'Wait for Apple processing, then add the build to an internal TestFlight group.'
    } >> "$GITHUB_STEP_SUMMARY"
    ;;

  cleanup)
    if [ -f "$signing_dir/profile-uuid" ]; then
      profile_uuid="$(cat "$signing_dir/profile-uuid")"
      if [[ "$profile_uuid" =~ ^[A-Fa-f0-9-]{36}$ ]]; then
        rm -f "$profile_dir/$profile_uuid.mobileprovision"
      fi
    fi
    security delete-keychain "$keychain_path" >/dev/null 2>&1 || true
    rm -rf "$signing_dir"
    ;;
  *) echo 'Usage: testflight.sh prepare|archive|upload|cleanup' >&2; exit 2 ;;
esac
