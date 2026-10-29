#!/bin/bash
set -euo pipefail
umask 077

source "$(dirname "${BASH_SOURCE[0]}")/signing-keychain.sh"
signing_require_runner

# Build distributable files with public read access without relaxing credential permissions.
distribution_build() (
  umask 022
  xcodebuild "$@"
)

for variable in APP_STORE_PROVISIONING_PROFILE_BASE64 APPLE_TEAM_ID APPLE_API_KEY_ID \
  APPLE_API_ISSUER_ID APPLE_API_PRIVATE_KEY RELEASE_TAG RUNNER_TEMP GITHUB_STEP_SUMMARY; do
  if [[ -z "${!variable:-}" ]]; then
    echo "::error::Missing required variable: $variable"
    exit 1
  fi
done
python3 .github/scripts/version.py check "$RELEASE_TAG"

work_directory="$(mktemp -d "$RUNNER_TEMP/pasket-testflight.XXXXXX")"
key_path="$work_directory/AuthKey.p8"
archive_path="$work_directory/pasket.xcarchive"
profile_paths=()
cleanup() {
  local result=$?
  local cleanup_failed=0
  local profile_path
  trap - EXIT
  # macOS Bash 3.2 treats an empty array expansion as unset under nounset.
  if [[ ${#profile_paths[@]} -gt 0 ]]; then
    for profile_path in "${profile_paths[@]}"; do
      rm -f "$profile_path" || cleanup_failed=1
    done
  fi
  signing_keychain_cleanup || cleanup_failed=1
  rm -rf "$work_directory" || cleanup_failed=1
  if [[ "$result" == 0 && "$cleanup_failed" != 0 ]]; then
    result=1
  fi
  exit "$result"
}
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

signing_keychain_prepare app-store "$work_directory" \
  APP_STORE_CERTIFICATES_BASE64 APP_STORE_CERTIFICATES_PASSWORD
printf '%s' "$APP_STORE_PROVISIONING_PROFILE_BASE64" | base64 --decode > "$work_directory/profile.provisionprofile"
printf '%s\n' "$APPLE_API_PRIVATE_KEY" > "$key_path"

# Installer identities are not code-signing identities; query the basic policy.
identities="$(security find-identity -v "$keychain_path")"
app_identities="$(printf '%s\n' "$identities" | awk -v team="$APPLE_TEAM_ID" \
  '/"(Apple Distribution:|3rd Party Mac Developer Application:)/ && index($0, "(" team ")\"") { print $2 }')"
installer_identities="$(printf '%s\n' "$identities" | awk -v team="$APPLE_TEAM_ID" \
  '/"(3rd Party Mac Developer Installer:|Mac Installer Distribution:)/ && index($0, "(" team ")\"") { print $2 }')"
app_identity_count="$(printf '%s\n' "$app_identities" | awk 'NF { count++ } END { print count+0 }')"
installer_identity_count="$(printf '%s\n' "$installer_identities" | awk 'NF { count++ } END { print count+0 }')"
if [[ ! "$app_identities" =~ ^[A-Fa-f0-9]{40}$ || ! "$installer_identities" =~ ^[A-Fa-f0-9]{40}$ ]]; then
  if [[ ! "$app_identities" =~ ^[A-Fa-f0-9]{40}$ ]]; then
    echo "::error::Expected exactly one valid Apple Distribution (or Mac App Distribution) certificate with its matching private key for APPLE_TEAM_ID; found $app_identity_count signing identities."
  fi
  if [[ ! "$installer_identities" =~ ^[A-Fa-f0-9]{40}$ ]]; then
    echo "::error::Expected exactly one valid Mac Installer Distribution certificate with its matching private key for APPLE_TEAM_ID; found $installer_identity_count signing identities."
  fi
  if printf '%s\n' "$identities" | awk '/"Developer ID (Application|Installer):/ { found=1 } END { exit !found }'; then
    echo '::error::Detected Developer ID signing identities. These sign downloads distributed outside the Mac App Store and cannot replace the App Store distribution identities required for TestFlight. Update APP_STORE_CERTIFICATES_BASE64 with the App Store app and installer identities.'
  fi
  echo '::error::Zero matches can mean a missing certificate or private key, an invalid certificate, the wrong team, or the wrong certificate type. Multiple matches mean the keychain contains too many identities of that type. Check the credentials or deliberately rotate the cached keychain. See docs/RELEASING.md, Certificates and provisioning profile.'
  exit 1
fi
signing_keychain_ready

security cms -D -i "$work_directory/profile.provisionprofile" > "$work_directory/profile.plist"
bundle_id=com.acehinnnqru.pasket
profile_uuid="$(python3 -B .github/scripts/testflight.py "$work_directory/profile.plist" \
  "$APPLE_TEAM_ID" "$bundle_id" "$app_identities" "$installer_identities" "$work_directory/ExportOptions.plist")"
# Support both current Xcode and the legacy provisioning profile directory.
for profile_directory in "$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles" "$HOME/Library/MobileDevice/Provisioning Profiles"; do
  mkdir -p "$profile_directory"
  profile_path="$profile_directory/$profile_uuid.provisionprofile"
  if [[ -L "$profile_path" ]]; then
    echo '::error::Refusing to use a symbolic link as a provisioning profile on the runner.'
    exit 1
  elif [[ -f "$profile_path" ]] && cmp -s "$work_directory/profile.provisionprofile" "$profile_path"; then
    # An identical preinstalled profile belongs to the runner; leave it in place.
    continue
  elif [[ -e "$profile_path" ]]; then
    echo '::error::Refusing to overwrite an existing provisioning profile on the runner.'
    exit 1
  fi
  profile_paths+=("$profile_path")
  cp "$work_directory/profile.provisionprofile" "$profile_path"
done

distribution_build -project pasket.xcodeproj -scheme pasket -configuration Release \
  -destination 'generic/platform=macOS' -derivedDataPath "$work_directory/DerivedData" \
  -archivePath "$archive_path" ARCHS='arm64 x86_64' ONLY_ACTIVE_ARCH=NO \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="$app_identities" \
  DEVELOPMENT_TEAM="$APPLE_TEAM_ID" PROVISIONING_PROFILE_SPECIFIER="$profile_uuid" \
  ENABLE_APP_SANDBOX=YES OTHER_CODE_SIGN_FLAGS="--keychain \"$keychain_path\"" archive

app_path="$archive_path/Products/Applications/pasket.app"
# Copied inputs can retain private modes even when the build uses umask 022.
# Limit permission changes to the app payload; credentials stay private.
chmod -R a+rX "$app_path"
architectures="$(lipo -archs "$app_path/Contents/MacOS/pasket")"
for architecture in arm64 x86_64; do
  if [[ " $architectures " != *" $architecture "* ]]; then
    echo "::error::The TestFlight binary is missing the $architecture architecture."
    exit 1
  fi
done
codesign --verify --deep --strict --verbose=2 "$app_path"

# Static signing assets keep provisioning changes out of this upload operation.
distribution_build -exportArchive -archivePath "$archive_path" \
  -exportPath "$work_directory/export" -exportOptionsPlist "$work_directory/ExportOptions.plist" \
  -authenticationKeyPath "$key_path" -authenticationKeyID "$APPLE_API_KEY_ID" \
  -authenticationKeyIssuerID "$APPLE_API_ISSUER_ID"

{
  printf '## TestFlight upload: %s\n\n' "$RELEASE_TAG"
  printf 'App Store Connect accepted the upload request. Apple processing and beta review may still be pending.\n\n'
  printf 'Check the build under **App Store Connect → Pasket → TestFlight** before retrying an interrupted upload.\n'
} >> "$GITHUB_STEP_SUMMARY"
