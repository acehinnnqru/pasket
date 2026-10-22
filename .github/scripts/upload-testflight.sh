#!/bin/bash
set -euo pipefail
umask 077

# Never import distribution credentials or change a developer's local keychain.
if [[ "${GITHUB_ACTIONS:-}" != true || "${RUNNER_ENVIRONMENT:-}" != github-hosted || "${RUNNER_OS:-}" != macOS ]]; then
  echo 'This script must run on a GitHub-hosted macOS Actions runner.' >&2
  exit 1
fi

for variable in APP_STORE_CERTIFICATES_BASE64 APP_STORE_CERTIFICATES_PASSWORD \
  APP_STORE_PROVISIONING_PROFILE_BASE64 APPLE_TEAM_ID APPLE_API_KEY_ID \
  APPLE_API_ISSUER_ID APPLE_API_PRIVATE_KEY RELEASE_TAG RUNNER_TEMP GITHUB_STEP_SUMMARY; do
  if [[ -z "${!variable:-}" ]]; then
    echo "::error::Missing required variable: $variable"
    exit 1
  fi
done
python3 .github/scripts/version.py check "$RELEASE_TAG"

work_directory="$(mktemp -d "$RUNNER_TEMP/pasket-testflight.XXXXXX")"
keychain_path="$work_directory/signing.keychain-db"
key_path="$work_directory/AuthKey.p8"
archive_path="$work_directory/pasket.xcarchive"
profile_paths=()
original_keychains=()
while IFS= read -r keychain; do
  original_keychains+=("$keychain")
done < <(security list-keychains -d user | sed 's/^[[:space:]]*"//; s/"[[:space:]]*$//')

cleanup() {
  local profile_path
  # macOS Bash 3.2 treats an empty array expansion as unset under nounset.
  if [[ ${#profile_paths[@]} -gt 0 ]]; then
    for profile_path in "${profile_paths[@]}"; do
      rm -f "$profile_path"
    done
  fi
  if [[ -f "$keychain_path" ]]; then
    if [[ ${#original_keychains[@]} -gt 0 ]]; then
      security list-keychains -d user -s "${original_keychains[@]}" || true
    fi
    security delete-keychain "$keychain_path" || true
  fi
  rm -rf "$work_directory"
}
trap cleanup EXIT

if [[ ${#original_keychains[@]} -eq 0 ]]; then
  echo '::error::Could not read the original runner keychain search list.'
  exit 1
fi

printf '%s' "$APP_STORE_CERTIFICATES_BASE64" | base64 --decode > "$work_directory/certificates.p12"
printf '%s' "$APP_STORE_PROVISIONING_PROFILE_BASE64" | base64 --decode > "$work_directory/profile.provisionprofile"
printf '%s\n' "$APPLE_API_PRIVATE_KEY" > "$key_path"
keychain_password="$(openssl rand -hex 32)"
echo "::add-mask::$keychain_password"
security create-keychain -p "$keychain_password" "$keychain_path"
security set-keychain-settings -lut 21600 "$keychain_path"
security unlock-keychain -p "$keychain_password" "$keychain_path"
security import "$work_directory/certificates.p12" -k "$keychain_path" \
  -P "$APP_STORE_CERTIFICATES_PASSWORD" -T /usr/bin/codesign -T /usr/bin/productbuild -T /usr/bin/security
security set-key-partition-list -S apple-tool:,apple:,codesign: -s \
  -k "$keychain_password" "$keychain_path" > /dev/null
security list-keychains -d user -s "$keychain_path" "${original_keychains[@]}"
rm "$work_directory/certificates.p12"

# Installer identities are not code-signing identities; query the basic policy.
identities="$(security find-identity -v "$keychain_path")"
app_identities="$(printf '%s\n' "$identities" | awk '/"(Apple Distribution:|3rd Party Mac Developer Application:)/ { print $2 }')"
installer_identities="$(printf '%s\n' "$identities" | awk '/"(3rd Party Mac Developer Installer:|Mac Installer Distribution:)/ { print $2 }')"
if [[ ! "$app_identities" =~ ^[A-Fa-f0-9]{40}$ || ! "$installer_identities" =~ ^[A-Fa-f0-9]{40}$ ]]; then
  echo '::error::The P12 must contain exactly one Apple Distribution (or Mac App Distribution) identity and one Mac Installer Distribution identity, both with private keys.'
  exit 1
fi

security cms -D -i "$work_directory/profile.provisionprofile" > "$work_directory/profile.plist"
bundle_id=com.acehinnnqru.pasket
profile_uuid="$(python3 -B .github/scripts/testflight.py "$work_directory/profile.plist" \
  "$APPLE_TEAM_ID" "$bundle_id" "$app_identities" "$installer_identities" "$work_directory/ExportOptions.plist")"
# Support both current Xcode and the legacy provisioning profile directory.
for profile_directory in "$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles" "$HOME/Library/MobileDevice/Provisioning Profiles"; do
  mkdir -p "$profile_directory"
  profile_path="$profile_directory/$profile_uuid.provisionprofile"
  if [[ -e "$profile_path" ]]; then
    echo '::error::Refusing to overwrite an existing provisioning profile on the runner.'
    exit 1
  fi
  profile_paths+=("$profile_path")
  cp "$work_directory/profile.provisionprofile" "$profile_path"
done

xcodebuild -project pasket.xcodeproj -scheme pasket -configuration Release \
  -destination 'generic/platform=macOS' -derivedDataPath "$work_directory/DerivedData" \
  -archivePath "$archive_path" ARCHS='arm64 x86_64' ONLY_ACTIVE_ARCH=NO \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="$app_identities" \
  DEVELOPMENT_TEAM="$APPLE_TEAM_ID" PROVISIONING_PROFILE_SPECIFIER="$profile_uuid" \
  ENABLE_APP_SANDBOX=YES OTHER_CODE_SIGN_FLAGS="--keychain $keychain_path" archive

app_path="$archive_path/Products/Applications/pasket.app"
architectures="$(lipo -archs "$app_path/Contents/MacOS/pasket")"
for architecture in arm64 x86_64; do
  if [[ " $architectures " != *" $architecture "* ]]; then
    echo "::error::The TestFlight binary is missing the $architecture architecture."
    exit 1
  fi
done
codesign --verify --deep --strict --verbose=2 "$app_path"

# Static signing assets keep provisioning changes out of this upload operation.
xcodebuild -exportArchive -archivePath "$archive_path" \
  -exportPath "$work_directory/export" -exportOptionsPlist "$work_directory/ExportOptions.plist" \
  -authenticationKeyPath "$key_path" -authenticationKeyID "$APPLE_API_KEY_ID" \
  -authenticationKeyIssuerID "$APPLE_API_ISSUER_ID"

{
  printf '## TestFlight upload: %s\n\n' "$RELEASE_TAG"
  printf 'App Store Connect accepted the upload request. Apple processing and beta review may still be pending.\n\n'
  printf 'Check the build under **App Store Connect → Pasket → TestFlight** before retrying an interrupted upload.\n'
} >> "$GITHUB_STEP_SUMMARY"
