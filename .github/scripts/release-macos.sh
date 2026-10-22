#!/bin/bash
set -euo pipefail
umask 077

# Signing credentials and keychain changes belong only on an ephemeral hosted runner.
if [[ "${GITHUB_ACTIONS:-}" != true || "${RUNNER_ENVIRONMENT:-}" != github-hosted || "${RUNNER_OS:-}" != macOS ]]; then
  echo 'This script must run on a GitHub-hosted macOS Actions runner.' >&2
  exit 1
fi

for variable in DEVELOPER_ID_CERTIFICATE_BASE64 DEVELOPER_ID_CERTIFICATE_PASSWORD \
  APPLE_TEAM_ID APPLE_API_KEY_ID APPLE_API_ISSUER_ID APPLE_API_PRIVATE_KEY \
  RELEASE_TAG RUNNER_TEMP GITHUB_OUTPUT; do
  if [[ -z "${!variable:-}" ]]; then
    echo "::error::Missing required variable: $variable"
    exit 1
  fi
done

work_directory="$(mktemp -d "$RUNNER_TEMP/pasket-release.XXXXXX")"
keychain_path="$work_directory/signing.keychain-db"
key_path="$work_directory/AuthKey.p8"
asset_directory="$RUNNER_TEMP/pasket-assets"

cleanup() {
  if [[ -f "$keychain_path" ]]; then
    security delete-keychain "$keychain_path" || true
  fi
  rm -rf "$work_directory"
}
trap cleanup EXIT

printf '%s' "$DEVELOPER_ID_CERTIFICATE_BASE64" | base64 --decode > "$work_directory/certificate.p12"
printf '%s\n' "$APPLE_API_PRIVATE_KEY" > "$key_path"
keychain_password="$(openssl rand -hex 32)"
echo "::add-mask::$keychain_password"
security create-keychain -p "$keychain_password" "$keychain_path"
security set-keychain-settings -lut 21600 "$keychain_path"
security unlock-keychain -p "$keychain_password" "$keychain_path"
security import "$work_directory/certificate.p12" -k "$keychain_path" \
  -P "$DEVELOPER_ID_CERTIFICATE_PASSWORD" -T /usr/bin/codesign -T /usr/bin/security
security set-key-partition-list -S apple-tool:,apple:,codesign: -s \
  -k "$keychain_password" "$keychain_path" > /dev/null
security list-keychains -d user -s "$keychain_path" login.keychain-db
rm "$work_directory/certificate.p12"

# Select a certificate from this keychain, never an unrelated runner identity.
identities="$(security find-identity -v -p codesigning "$keychain_path")"
identity_count="$(printf '%s\n' "$identities" | awk '/"Developer ID Application:/ { count++ } END { print count+0 }')"
if [[ "$identity_count" != 1 ]]; then
  echo '::error::The P12 must contain exactly one valid Developer ID Application identity and its private key.'
  exit 1
fi
signing_identity="$(printf '%s\n' "$identities" | awk '/"Developer ID Application:/ { print $2 }')"
python3 .github/scripts/version.py check "$RELEASE_TAG"

xcodebuild -project pasket.xcodeproj -scheme pasket -configuration Release \
  -destination 'generic/platform=macOS' -derivedDataPath "$work_directory/DerivedData" \
  ARCHS='arm64 x86_64' ONLY_ACTIVE_ARCH=NO \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="$signing_identity" \
  DEVELOPMENT_TEAM="$APPLE_TEAM_ID" PROVISIONING_PROFILE_SPECIFIER= \
  ENABLE_HARDENED_RUNTIME=YES CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
  OTHER_CODE_SIGN_FLAGS="--timestamp --keychain $keychain_path" build

app_path="$work_directory/DerivedData/Build/Products/Release/pasket.app"
architectures="$(lipo -archs "$app_path/Contents/MacOS/pasket")"
for architecture in arm64 x86_64; do
  if [[ " $architectures " != *" $architecture "* ]]; then
    echo "::error::The release binary is missing the $architecture architecture."
    exit 1
  fi
done
codesign --verify --deep --strict --verbose=2 "$app_path"

notarize() {
  local file_path="$1"
  local label="$2"
  local result_path="$work_directory/$label-submission.json"
  local submission_exit=0
  local status
  local submission_id

  xcrun notarytool submit "$file_path" \
    --key "$key_path" --key-id "$APPLE_API_KEY_ID" --issuer "$APPLE_API_ISSUER_ID" \
    --wait --timeout 30m --output-format json > "$result_path" || submission_exit=$?
  cat "$result_path"
  status="$(plutil -extract status raw -o - "$result_path" 2>/dev/null || true)"

  if [[ "$submission_exit" != 0 || "$status" != Accepted ]]; then
    submission_id="$(plutil -extract id raw -o - "$result_path" 2>/dev/null || true)"
    if [[ -n "$submission_id" ]]; then
      echo "Notarization submission: $submission_id"
      if xcrun notarytool log "$submission_id" \
        --key "$key_path" --key-id "$APPLE_API_KEY_ID" --issuer "$APPLE_API_ISSUER_ID" \
        "$work_directory/$label-log.json"; then
        cat "$work_directory/$label-log.json"
      fi
    fi
    echo "::error::Notarization did not complete with Accepted status for $label. No release will be published."
    return 1
  fi
}

# ZIP files cannot carry stapled tickets. Staple the app, then recreate the ZIP.
ditto -c -k --sequesterRsrc --keepParent "$app_path" "$work_directory/notarization.zip"
notarize "$work_directory/notarization.zip" app
xcrun stapler staple "$app_path"
xcrun stapler validate "$app_path"
spctl --assess --type execute --verbose=2 "$app_path"

mkdir "$asset_directory"
zip_path="$asset_directory/pasket-$RELEASE_TAG-universal.zip"
dmg_path="$asset_directory/pasket-$RELEASE_TAG-universal.dmg"
ditto -c -k --sequesterRsrc --keepParent "$app_path" "$zip_path"

mkdir "$work_directory/dmg-root"
ditto "$app_path" "$work_directory/dmg-root/pasket.app"
ln -s /Applications "$work_directory/dmg-root/Applications"
hdiutil create -volname Pasket -srcfolder "$work_directory/dmg-root" \
  -format UDZO "$dmg_path"
codesign --force --sign "$signing_identity" --keychain "$keychain_path" \
  --timestamp "$dmg_path"
codesign --verify --strict --verbose=2 "$dmg_path"
notarize "$dmg_path" dmg
xcrun stapler staple "$dmg_path"
xcrun stapler validate "$dmg_path"
spctl --assess --type open --context context:primary-signature --verbose=2 "$dmg_path"

# Confirm that the distributed ZIP preserves the app's signature and ticket.
ditto -x -k "$zip_path" "$work_directory/zip-check"
codesign --verify --deep --strict --verbose=2 "$work_directory/zip-check/pasket.app"
xcrun stapler validate "$work_directory/zip-check/pasket.app"

echo "asset-directory=$asset_directory" >> "$GITHUB_OUTPUT"
