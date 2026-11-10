#!/bin/bash
set -euo pipefail
umask 077

source "$(dirname "${BASH_SOURCE[0]}")/distribution-log.sh"
distribution_stage preflight configuration
source "$(dirname "${BASH_SOURCE[0]}")/signing-keychain.sh"
signing_require_runner

for variable in APPLE_TEAM_ID APPLE_API_KEY_ID APPLE_API_ISSUER_ID APPLE_API_PRIVATE_KEY \
  RELEASE_TAG RUNNER_TEMP; do
  if [[ -z "${!variable:-}" ]]; then
    exit 1
  fi
done
python3 -B .github/scripts/version.py check "$RELEASE_TAG"

work_directory="$(mktemp -d "$RUNNER_TEMP/pasket-release.XXXXXX")"
key_path="$work_directory/AuthKey.p8"
asset_directory="$RUNNER_TEMP/pasket-assets"

cleanup() {
  local result=$?
  local cleanup_failed=0
  trap - EXIT
  distribution_finish "$result"
  distribution_stage cleanup cleanup
  signing_keychain_cleanup || cleanup_failed=1
  rm -rf "$work_directory" || cleanup_failed=1
  distribution_finish "$cleanup_failed"
  if [[ "$result" == 0 && "$cleanup_failed" != 0 ]]; then
    result=1
  fi
  exit "$result"
}
trap cleanup EXIT

distribution_stage signing signing
signing_keychain_prepare developer-id "$work_directory" \
  DEVELOPER_ID_CERTIFICATE_BASE64 DEVELOPER_ID_CERTIFICATE_PASSWORD
printf '%s\n' "$APPLE_API_PRIVATE_KEY" > "$key_path"

# Select a certificate from this keychain, never an unrelated runner identity.
distribution_error=identity
identities="$(security find-identity -v -p codesigning "$keychain_path")"
signing_identity="$(printf '%s\n' "$identities" | awk -v team="$APPLE_TEAM_ID" \
  '/"Developer ID Application:/ && index($0, "(" team ")\"") { print $2 }')"
if [[ ! "$signing_identity" =~ ^[A-Fa-f0-9]{40}$ ]]; then
  exit 1
fi
distribution_error=signing
signing_keychain_ready

distribution_stage build build
xcodebuild -project pasket.xcodeproj -scheme pasket -configuration Release \
  -destination 'generic/platform=macOS' -derivedDataPath "$work_directory/DerivedData" \
  ARCHS='arm64 x86_64' ONLY_ACTIVE_ARCH=NO \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="$signing_identity" \
  DEVELOPMENT_TEAM="$APPLE_TEAM_ID" PROVISIONING_PROFILE_SPECIFIER= \
  ENABLE_HARDENED_RUNTIME=YES CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
  OTHER_CODE_SIGN_FLAGS="--timestamp --keychain \"$keychain_path\"" build

distribution_stage verification verification
app_path="$work_directory/DerivedData/Build/Products/Release/pasket.app"
architectures="$(lipo -archs "$app_path/Contents/MacOS/pasket")"
for architecture in arm64 x86_64; do
  if [[ " $architectures " != *" $architecture "* ]]; then
    exit 1
  fi
done
codesign --verify --deep --strict "$app_path"

notarize() {
  local file_path="$1"
  local label="$2"
  local result_path="$work_directory/$label-submission.json"
  local status

  distribution_error=notarization-request
  xcrun notarytool submit "$file_path" \
    --key "$key_path" --key-id "$APPLE_API_KEY_ID" --issuer "$APPLE_API_ISSUER_ID" \
    --wait --timeout 30m --output-format json > "$result_path" || return 1
  distribution_error=notarization-result
  status="$(plutil -extract status raw -o - "$result_path")"
  [[ "$status" == Accepted ]]
}

# ZIP files cannot carry stapled tickets. Staple the app, then recreate the ZIP.
distribution_stage app-notarization packaging
ditto -c -k --sequesterRsrc --keepParent "$app_path" "$work_directory/notarization.zip"
notarize "$work_directory/notarization.zip" app
distribution_error=stapling
xcrun stapler staple "$app_path"
xcrun stapler validate "$app_path"
distribution_error=verification
spctl --assess --type execute "$app_path"

distribution_stage packaging packaging
mkdir "$asset_directory"
zip_path="$asset_directory/pasket-$RELEASE_TAG-universal.zip"
dmg_path="$asset_directory/pasket-$RELEASE_TAG-universal.dmg"
ditto -c -k --sequesterRsrc --keepParent "$app_path" "$zip_path"

mkdir "$work_directory/dmg-root"
ditto "$app_path" "$work_directory/dmg-root/pasket.app"
ln -s /Applications "$work_directory/dmg-root/Applications"
hdiutil create -volname Pasket -srcfolder "$work_directory/dmg-root" \
  -format UDZO "$dmg_path"
distribution_error=signing
codesign --force --sign "$signing_identity" --keychain "$keychain_path" \
  --timestamp "$dmg_path"
distribution_error=verification
codesign --verify --strict "$dmg_path"
distribution_stage dmg-notarization notarization-request
notarize "$dmg_path" dmg
distribution_error=stapling
xcrun stapler staple "$dmg_path"
xcrun stapler validate "$dmg_path"
distribution_error=verification
spctl --assess --type open --context context:primary-signature "$dmg_path"

# Confirm that the distributed ZIP preserves the app's signature and ticket.
distribution_stage zip-verification verification
ditto -x -k "$zip_path" "$work_directory/zip-check"
codesign --verify --deep --strict "$work_directory/zip-check/pasket.app"
xcrun stapler validate "$work_directory/zip-check/pasket.app"
