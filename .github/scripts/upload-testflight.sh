#!/bin/bash
set -euo pipefail
umask 077

source "$(dirname "${BASH_SOURCE[0]}")/distribution-log.sh"
distribution_stage preflight configuration
source "$(dirname "${BASH_SOURCE[0]}")/signing-keychain.sh"
signing_require_runner

# Build distributable files with public read access without relaxing credential permissions.
distribution_build() (
  umask 022
  xcodebuild "$@"
)

for variable in APP_STORE_PROVISIONING_PROFILE_BASE64 APPLE_TEAM_ID APPLE_API_KEY_ID \
  APPLE_API_ISSUER_ID APPLE_API_PRIVATE_KEY RELEASE_TAG RUNNER_TEMP; do
  if [[ -z "${!variable:-}" ]]; then
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
  distribution_finish "$result"
  distribution_stage cleanup cleanup
  # macOS Bash 3.2 treats an empty array expansion as unset under nounset.
  if [[ ${#profile_paths[@]} -gt 0 ]]; then
    for profile_path in "${profile_paths[@]}"; do
      rm -f "$profile_path" || cleanup_failed=1
    done
  fi
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
signing_keychain_prepare app-store "$work_directory" \
  APP_STORE_CERTIFICATES_BASE64 APP_STORE_CERTIFICATES_PASSWORD
distribution_error=provisioning
printf '%s' "$APP_STORE_PROVISIONING_PROFILE_BASE64" | base64 --decode > "$work_directory/profile.provisionprofile"
distribution_error=signing
printf '%s\n' "$APPLE_API_PRIVATE_KEY" > "$key_path"

# Installer identities are not code-signing identities; query the basic policy.
distribution_error=identity
identities="$(security find-identity -v "$keychain_path")"
app_identities="$(printf '%s\n' "$identities" | awk -v team="$APPLE_TEAM_ID" \
  '/"(Apple Distribution:|3rd Party Mac Developer Application:)/ && index($0, "(" team ")\"") { print $2 }')"
installer_identities="$(printf '%s\n' "$identities" | awk -v team="$APPLE_TEAM_ID" \
  '/"(3rd Party Mac Developer Installer:|Mac Installer Distribution:)/ && index($0, "(" team ")\"") { print $2 }')"
if [[ ! "$app_identities" =~ ^[A-Fa-f0-9]{40}$ || ! "$installer_identities" =~ ^[A-Fa-f0-9]{40}$ ]]; then
  exit 1
fi
distribution_error=signing
signing_keychain_ready

distribution_stage provisioning provisioning
security cms -D -i "$work_directory/profile.provisionprofile" > "$work_directory/profile.plist"
bundle_id=com.acehinnnqru.pasket
profile_uuid="$(python3 -B .github/scripts/testflight.py "$work_directory/profile.plist" \
  "$APPLE_TEAM_ID" "$bundle_id" "$app_identities" "$installer_identities" "$work_directory/ExportOptions.plist")"
# Support both current Xcode and the legacy provisioning profile directory.
for profile_directory in "$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles" "$HOME/Library/MobileDevice/Provisioning Profiles"; do
  mkdir -p "$profile_directory"
  profile_path="$profile_directory/$profile_uuid.provisionprofile"
  if [[ -L "$profile_path" ]]; then
    exit 1
  elif [[ -f "$profile_path" ]] && cmp -s "$work_directory/profile.provisionprofile" "$profile_path"; then
    # An identical preinstalled profile belongs to the runner; leave it in place.
    continue
  elif [[ -e "$profile_path" ]]; then
    exit 1
  fi
  profile_paths+=("$profile_path")
  cp "$work_directory/profile.provisionprofile" "$profile_path"
done

distribution_stage archive archive
distribution_build -project pasket.xcodeproj -scheme pasket -configuration Release \
  -destination 'generic/platform=macOS' -derivedDataPath "$work_directory/DerivedData" \
  -archivePath "$archive_path" ARCHS='arm64 x86_64' ONLY_ACTIVE_ARCH=NO \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="$app_identities" \
  DEVELOPMENT_TEAM="$APPLE_TEAM_ID" PROVISIONING_PROFILE_SPECIFIER="$profile_uuid" \
  ENABLE_APP_SANDBOX=YES OTHER_CODE_SIGN_FLAGS="--keychain \"$keychain_path\"" archive

distribution_stage verification verification
app_path="$archive_path/Products/Applications/pasket.app"
# Copied inputs can retain private modes even when the build uses umask 022.
# Limit permission changes to the app payload; credentials stay private.
chmod -R a+rX "$app_path"
architectures="$(lipo -archs "$app_path/Contents/MacOS/pasket")"
for architecture in arm64 x86_64; do
  if [[ " $architectures " != *" $architecture "* ]]; then
    exit 1
  fi
done
codesign --verify --deep --strict "$app_path"

# Static signing assets keep provisioning changes out of this upload operation.
distribution_stage upload upload
distribution_build -exportArchive -archivePath "$archive_path" \
  -exportPath "$work_directory/export" -exportOptionsPlist "$work_directory/ExportOptions.plist" \
  -authenticationKeyPath "$key_path" -authenticationKeyID "$APPLE_API_KEY_ID" \
  -authenticationKeyIssuerID "$APPLE_API_ISSUER_ID"
