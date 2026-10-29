#!/bin/bash
# Shared keychain lifecycle for the two distribution scripts (macOS Bash 3.2).
# Callers own EXIT/signal traps and call cleanup even when preparation fails.

keychain_path=
signing_keychain_created=false
signing_keychain_initialized=false
signing_keychain_unlocked=false
signing_keychain_persistent=false
signing_search_list_changed=false
signing_lock_acquired=false
signing_original_keychains=()
signing_metadata_path=
signing_metadata_pending=
signing_metadata_identity=
signing_p12_fingerprint=
signing_lock_path=

signing_error() {
  printf '::error::%s\n' "$*" >&2
  return 1
}

signing_require_runner() {
  if [[ "${GITHUB_ACTIONS:-}" != true || "${RUNNER_OS:-}" != macOS ]]; then
    signing_error 'This script must run on a macOS GitHub Actions runner.'
    return 1
  fi
  case "${RUNNER_ENVIRONMENT:-}" in
    github-hosted) ;;
    self-hosted)
      if [[ -z "${CI_KEYCHAIN_PASSWORD:-}" ]]; then
        signing_error 'Set CI_KEYCHAIN_PASSWORD to enable the dedicated persistent signing keychain on this self-hosted runner.'
        return 1
      fi
      ;;
    *) signing_error 'Unsupported runner environment for signing.'; return 1 ;;
  esac
}

signing_keychain_root() {
  printf '%s\n' "$HOME/Library/Keychains/pasket-ci"
}

signing_private_directory() {
  local directory="$1" component="$1"
  # Refuse redirected paths rather than touching a user's unrelated keychain.
  while [[ "$component" != / ]]; do
    if [[ -L "$component" ]]; then
      signing_error "Refusing a symlink in the managed keychain path: $component"
      return 1
    fi
    component="${component%/*}"
    [[ -n "$component" ]] || component=/
  done
  if [[ ! -e "$directory" ]]; then
    mkdir -m 700 "$directory" || return 1
  fi
  if [[ ! -d "$directory" || ! -O "$directory" || "$(stat -f '%Lp' "$directory")" != 700 ]]; then
    signing_error "The managed keychain directory must be owned by this runner user with mode 700: $directory"
    return 1
  fi
}

signing_save_search_list() {
  local listing line
  listing="$(security list-keychains -d user)" || return 1
  while IFS= read -r line; do
    if [[ "$line" =~ ^[[:space:]]*\"(.*)\"[[:space:]]*$ ]]; then
      signing_original_keychains+=("${BASH_REMATCH[1]}")
    elif [[ -n "$line" ]]; then
      signing_error 'Could not parse the original runner keychain search list.'
      return 1
    fi
  done <<< "$listing"
  if [[ ${#signing_original_keychains[@]} -eq 0 ]]; then
    signing_error 'Could not read the original runner keychain search list.'
    return 1
  fi
}

signing_keychain_prepare() {
  local purpose="$1" work_directory="$2" data_variable="$3" password_variable="$4"
  local root owner repository directory component metadata expected_metadata
  local p12_data p12_password keychain_password fingerprint_output original found=false
  signing_require_runner || return 1
  case "$purpose" in
    developer-id|app-store) ;;
    *) signing_error 'Unknown signing keychain purpose.'; return 1 ;;
  esac
  p12_data="${!data_variable:-}"
  p12_password="${!password_variable:-}"
  if [[ -n "$p12_data" ]]; then
    fingerprint_output="$(set -o pipefail; printf '%s' "$p12_data" | base64 --decode | shasum -a 256)" || return 1
    signing_p12_fingerprint="${fingerprint_output%% *}"
  fi

  if [[ "$RUNNER_ENVIRONMENT" == self-hosted ]]; then
    signing_keychain_persistent=true
    if [[ ! "${GITHUB_REPOSITORY:-}" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ || ! "${APPLE_TEAM_ID:-}" =~ ^[A-Z0-9]{10}$ ]]; then
      signing_error 'Persistent signing requires GITHUB_REPOSITORY (owner/repository) and a ten-character APPLE_TEAM_ID.'
      return 1
    fi
    owner="${GITHUB_REPOSITORY%/*}"
    repository="${GITHUB_REPOSITORY#*/}"
    case "$owner/$repository" in
      ./*|../*|*/.|*/..) signing_error 'Invalid repository path for the managed keychain.'; return 1 ;;
    esac
    root="$(signing_keychain_root)" || return 1
    if [[ "$root" != /* || "$root" == / || "$root" == *$'\n'* ]]; then
      signing_error 'The managed keychain root must be an absolute directory path.'
      return 1
    fi
    signing_private_directory "$root" || return 1
    signing_lock_path="$root/.signing.lock"
    if ! mkdir -m 700 "$signing_lock_path"; then
      signing_error "Another signing task is active, or a previous task stopped without cleanup. Inspect $signing_lock_path and retry after that task is finished; the script will not break its lock."
      return 1
    fi
    signing_lock_acquired=true
    directory="$root"
    for component in "$owner" "$repository" "$APPLE_TEAM_ID"; do
      directory="$directory/$component"
      signing_private_directory "$directory" || return 1
    done
    keychain_path="$directory/$purpose.keychain-db"
    signing_metadata_path="$keychain_path.ready"
    keychain_password="$CI_KEYCHAIN_PASSWORD"
    if [[ -e "$keychain_path" || -L "$keychain_path" || -e "$signing_metadata_path" || -L "$signing_metadata_path" ]]; then
      for component in "$keychain_path" "$signing_metadata_path"; do
        if [[ -L "$component" || ! -f "$component" || ! -O "$component" || "$(stat -f '%Lp' "$component")" != 600 ]]; then
          signing_error "Refusing an unknown or incomplete persistent keychain. Inspect its state before retrying: $keychain_path"
          return 1
        fi
      done
      metadata="$(cat "$signing_metadata_path")" || return 1
      expected_metadata="$(printf 'pasket-signing-keychain-v1\n%s\n%s\n%s' "$GITHUB_REPOSITORY" "$APPLE_TEAM_ID" "$purpose")"
      if [[ "${metadata%$'\n'*}" != "$expected_metadata" || ! "${metadata##*$'\n'}" =~ ^[a-f0-9]{64}$ ]]; then
        signing_error "Refusing unrecognized keychain ownership metadata: $signing_metadata_path"
        return 1
      fi
      if [[ -n "$signing_p12_fingerprint" && "$signing_p12_fingerprint" != "${metadata##*$'\n'}" ]]; then
        signing_error "The configured P12 has changed. Rotate the dedicated keychain deliberately while no signing job is running: $keychain_path"
        return 1
      fi
      signing_keychain_initialized=true
      printf 'Reusing the managed %s signing keychain.\n' "$purpose"
    fi
  else
    keychain_path="$work_directory/signing.keychain-db"
    if [[ -e "$keychain_path" || -L "$keychain_path" ]]; then
      signing_error 'Refusing to overwrite an existing temporary signing keychain.'
      return 1
    fi
    keychain_password="$(openssl rand -hex 32)" || return 1
  fi

  if [[ "$signing_keychain_initialized" != true && ( -z "$p12_data" || -z "$p12_password" ) ]]; then
    signing_error "Initial keychain setup requires $data_variable and $password_variable."
    return 1
  fi
  signing_save_search_list || return 1
  printf '::add-mask::%s\n' "$keychain_password"
  if [[ "$signing_keychain_initialized" != true ]]; then
    # Creating a keychain can itself change the search list, including on failure.
    signing_search_list_changed=true
    signing_keychain_created=true
    security create-keychain -p "$keychain_password" "$keychain_path" || return 1
    chmod 600 "$keychain_path" || return 1
    security set-keychain-settings -lut 21600 "$keychain_path" || return 1
  fi
  # Cleanup attempts to lock even if the unlock command reports a partial failure.
  signing_keychain_unlocked=true
  if ! security unlock-keychain -p "$keychain_password" "$keychain_path"; then
    signing_error 'Could not unlock the signing keychain. Check CI_KEYCHAIN_PASSWORD; the existing keychain will not be replaced.'
    return 1
  fi
  if [[ "$signing_keychain_initialized" != true ]]; then
    if [[ -e "$work_directory/signing-import.p12" || -L "$work_directory/signing-import.p12" ]]; then
      signing_error 'Refusing to overwrite a signing import file.'
      return 1
    fi
    (umask 077; printf '%s' "$p12_data" | base64 --decode > "$work_directory/signing-import.p12") || return 1
    security import "$work_directory/signing-import.p12" -k "$keychain_path" \
      -P "$p12_password" -T /usr/bin/codesign -T /usr/bin/productbuild -T /usr/bin/security || return 1
    security set-key-partition-list -S apple-tool:,apple:,codesign: -s \
      -k "$keychain_password" "$keychain_path" > /dev/null || return 1
    rm "$work_directory/signing-import.p12" || return 1
    printf 'Initialized the managed %s signing keychain; checking its identities next.\n' "$purpose"
  fi
  for original in "${signing_original_keychains[@]}"; do
    [[ "$original" != "$keychain_path" ]] || found=true
  done
  if [[ "$found" != true ]]; then
    signing_search_list_changed=true
    security list-keychains -d user -s "${signing_original_keychains[@]}" "$keychain_path" || return 1
  fi
}

signing_keychain_ready() {
  local purpose
  if [[ "$signing_keychain_persistent" == true && "$signing_keychain_initialized" != true ]]; then
    signing_metadata_pending="$(mktemp "$signing_metadata_path.XXXXXX")" || return 1
    purpose="${keychain_path##*/}"
    purpose="${purpose%.keychain-db}"
    printf 'pasket-signing-keychain-v1\n%s\n%s\n%s\n%s\n' \
      "$GITHUB_REPOSITORY" "$APPLE_TEAM_ID" "$purpose" "$signing_p12_fingerprint" > "$signing_metadata_pending" || return 1
    # Track the actual file before publishing so signal cleanup can recognize it
    # even if mv finishes but the shell has not marked initialization complete.
    signing_metadata_identity="$(stat -f '%d:%i' "$signing_metadata_pending")" || return 1
    mv "$signing_metadata_pending" "$signing_metadata_path" || return 1
    signing_metadata_pending=
  fi
  signing_keychain_initialized=true
}

signing_keychain_cleanup() {
  local failed=0
  if [[ "$signing_search_list_changed" == true && ${#signing_original_keychains[@]} -gt 0 ]]; then
    if security list-keychains -d user -s "${signing_original_keychains[@]}"; then
      signing_search_list_changed=false
    else
      signing_error 'Failed to restore the original keychain search list; inspect this runner before the next release.' || true
      failed=1
    fi
  fi
  if [[ "$signing_keychain_created" == true && ( "$signing_keychain_persistent" != true || "$signing_keychain_initialized" != true ) ]]; then
    if [[ -f "$keychain_path" ]]; then
      if ! security delete-keychain "$keychain_path"; then
        signing_error 'Failed to delete the temporary or incomplete signing keychain.' || true
        failed=1
      fi
    fi
    if [[ ! -e "$keychain_path" && -n "$signing_metadata_identity" && -f "$signing_metadata_path" && ! -L "$signing_metadata_path" ]]; then
      if [[ "$(stat -f '%d:%i' "$signing_metadata_path")" == "$signing_metadata_identity" ]]; then
        rm "$signing_metadata_path" || failed=1
      fi
    fi
  elif [[ "$signing_keychain_unlocked" == true ]]; then
    if ! security lock-keychain "$keychain_path"; then
      signing_error 'Failed to lock the persistent signing keychain; inspect this runner before the next release.' || true
      failed=1
    fi
  fi
  if [[ -n "$signing_metadata_pending" ]]; then
    rm -f "$signing_metadata_pending" || failed=1
  fi
  if [[ "$signing_lock_acquired" == true ]]; then
    if [[ "$failed" == 0 ]]; then
      if rmdir "$signing_lock_path"; then
        signing_lock_acquired=false
      else
        failed=1
      fi
    else
      signing_error "The signing lock was retained for recovery: $signing_lock_path" || true
    fi
  fi
  return "$failed"
}
