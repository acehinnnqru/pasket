#!/usr/bin/env python3
"""Validate a Mac App Store profile and prepare manual distribution options."""

from datetime import datetime, timezone
import hashlib
from pathlib import Path
import plistlib
import sys
import uuid


def validate_profile(profile, team, bundle_id, signing_identity):
    """Reject profiles that cannot distribute this app through App Store Connect."""
    if profile.get("TeamIdentifier") != [team]:
        raise ValueError("The provisioning profile must belong to APPLE_TEAM_ID.")
    if "OSX" not in profile.get("Platform", []):
        raise ValueError("Use a macOS provisioning profile.")
    expiration = profile.get("ExpirationDate")
    if not isinstance(expiration, datetime) or expiration.replace(tzinfo=timezone.utc) <= datetime.now(timezone.utc):
        raise ValueError("The provisioning profile is expired or has no expiration date.")
    entitlements = profile.get("Entitlements", {})
    app_id = entitlements.get("com.apple.application-identifier", entitlements.get("application-identifier"))
    prefixes = profile.get("ApplicationIdentifierPrefix", [])
    if app_id not in {f"{prefix}.{bundle_id}" for prefix in prefixes}:
        raise ValueError("The provisioning profile must match the explicit app bundle identifier.")
    if ("ProvisionedDevices" in profile or profile.get("ProvisionsAllDevices")
            or entitlements.get("get-task-allow") or entitlements.get("com.apple.security.get-task-allow")):
        raise ValueError("Use a Mac App Store Connect distribution profile, not a development or Developer ID profile.")
    certificates = {hashlib.sha1(cert).hexdigest().upper() for cert in profile.get("DeveloperCertificates", [])}
    if signing_identity.upper() not in certificates:
        raise ValueError("The distribution certificate must be included in the provisioning profile.")
    profile_uuid = profile.get("UUID", "")
    # The UUID becomes a filename and an Xcode build setting.
    if str(uuid.UUID(profile_uuid)).upper() != profile_uuid.upper():
        raise ValueError("Invalid provisioning profile UUID.")
    return profile_uuid


def export_options(team, bundle_id, profile_uuid, app_identity, installer_identity):
    return {
        "method": "app-store-connect",
        "destination": "upload",
        "teamID": team,
        "signingStyle": "manual",
        "signingCertificate": app_identity,
        "installerSigningCertificate": installer_identity,
        "provisioningProfiles": {bundle_id: profile_uuid},
        # Preserve the build number reserved by the repository's release tag.
        "manageAppVersionAndBuildNumber": False,
        "uploadSymbols": True,
    }


def main():
    profile_path, team, bundle_id, app_identity, installer_identity, output_path = sys.argv[1:]
    with Path(profile_path).open("rb") as source:
        profile = plistlib.load(source)
    profile_uuid = validate_profile(profile, team, bundle_id, app_identity)
    with Path(output_path).open("wb") as destination:
        plistlib.dump(export_options(team, bundle_id, profile_uuid, app_identity, installer_identity), destination)
    print(profile_uuid)


if __name__ == "__main__":
    try:
        main()
    except (ValueError, KeyError, TypeError, plistlib.InvalidFileException) as error:
        sys.exit(f"TestFlight configuration error: {error}")
