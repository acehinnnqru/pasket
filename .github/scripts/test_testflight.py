#!/usr/bin/env python3
"""Exercise distribution configuration without credentials or Apple services."""

from copy import deepcopy
from datetime import datetime, timedelta
import hashlib
import os
from pathlib import Path
import stat
import subprocess
import tempfile
import unittest

from testflight import export_options, validate_profile


TEAM = "TESTTEAM01"
BUNDLE = "com.acehinnnqru.pasket"
CERTIFICATE = b"synthetic distribution certificate"
IDENTITY = hashlib.sha1(CERTIFICATE).hexdigest().upper()
PROFILE_UUID = "EBCB02F9-424B-4D99-A923-F05EC6BAA707"


class TestDistributionProfile(unittest.TestCase):
    def setUp(self):
        self.profile = {
            "UUID": PROFILE_UUID,
            "TeamIdentifier": [TEAM],
            "ApplicationIdentifierPrefix": ["LEGACYPREFIX"],
            "Platform": ["OSX"],
            "ExpirationDate": datetime.now() + timedelta(days=30),
            "DeveloperCertificates": [CERTIFICATE],
            "Entitlements": {"com.apple.application-identifier": f"LEGACYPREFIX.{BUNDLE}"},
        }

    def validate(self, profile=None):
        return validate_profile(self.profile if profile is None else profile, TEAM, BUNDLE, IDENTITY)

    def test_accepts_matching_mac_profile_with_legacy_prefix(self):
        self.assertEqual(self.validate(), PROFILE_UUID)

    def test_rejects_wrong_team_platform_expiration_and_certificate(self):
        for key, value in (
            ("TeamIdentifier", ["OTHERTEAM"]),
            ("Platform", ["iOS"]),
            ("ExpirationDate", datetime.now() - timedelta(days=1)),
            ("ExpirationDate", None),
            ("DeveloperCertificates", [b"another certificate"]),
            ("UUID", "../../profile"),
        ):
            with self.subTest(key=key, value=value), self.assertRaises(ValueError):
                self.validate({**self.profile, key: value})

    def test_rejects_development_and_developer_id_profiles(self):
        for key, value in (("ProvisionedDevices", []), ("ProvisionsAllDevices", True)):
            with self.subTest(key=key), self.assertRaises(ValueError):
                self.validate({**self.profile, key: value})
        for key in ("get-task-allow", "com.apple.security.get-task-allow"):
            profile = deepcopy(self.profile)
            profile["Entitlements"][key] = True
            with self.subTest(key=key), self.assertRaises(ValueError):
                self.validate(profile)

    def test_rejects_wrong_bundle_and_wildcard_profiles(self):
        for app_id in ("LEGACYPREFIX.*", "LEGACYPREFIX.another.app", f"OTHERPREFIX.{BUNDLE}"):
            profile = deepcopy(self.profile)
            profile["Entitlements"]["com.apple.application-identifier"] = app_id
            with self.subTest(app_id=app_id), self.assertRaises(ValueError):
                self.validate(profile)

    def test_preserves_tagged_build_number_and_both_signing_identities(self):
        options = export_options(TEAM, BUNDLE, PROFILE_UUID, IDENTITY, "INSTALLER_HASH")
        self.assertFalse(options["manageAppVersionAndBuildNumber"])
        self.assertEqual(options["method"], "app-store-connect")
        self.assertEqual(options["destination"], "upload")
        self.assertEqual(options["signingStyle"], "manual")
        self.assertEqual(options["signingCertificate"], IDENTITY)
        self.assertEqual(options["installerSigningCertificate"], "INSTALLER_HASH")
        self.assertEqual(options["provisioningProfiles"], {BUNDLE: PROFILE_UUID})
        self.assertEqual(options["teamID"], TEAM)


class TestUploadGuard(unittest.TestCase):
    def test_distribution_files_are_readable_without_exposing_credentials(self):
        script = Path(__file__).with_name("upload-testflight.sh").read_text()
        build = script[script.index("distribution_build() ("):script.index("\nfor variable in")]
        permissions = script[script.index("# Copied inputs can retain private modes"):
                             script.index('\narchitectures="')]
        with tempfile.TemporaryDirectory(prefix="pasket-testflight-permissions-") as directory:
            result = subprocess.run(
                ["/bin/bash", "-euc", build + '''
umask 077
work_directory="$1"
app_path="$work_directory/pasket.app"
printf 'synthetic private key' > "$work_directory/AuthKey.p8"
xcodebuild() {
  mkdir -p "$app_path/Contents/MacOS"
  printf 'synthetic resource' > "$app_path/Contents/Info.plist"
  printf 'synthetic executable' > "$app_path/Contents/MacOS/pasket"
  chmod u+x "$app_path/Contents/MacOS/pasket"
}
distribution_build -archivePath "$work_directory/pasket.xcarchive" archive
# Model a copied input whose original private mode survives the build.
printf 'synthetic profile' > "$app_path/Contents/embedded.provisionprofile"
''' + permissions + '''
xcodebuild() {
  mkdir "$work_directory/export"
  printf 'synthetic package' > "$work_directory/export/pasket.pkg"
}
distribution_build -exportArchive
printf 'synthetic credential' > "$work_directory/credential-after-build"
''', "permissions-test", directory],
                capture_output=True, text=True,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            root = Path(directory)
            for name in ("AuthKey.p8", "credential-after-build"):
                self.assertEqual(stat.S_IMODE((root / name).stat().st_mode), 0o600)
            for name in ("pasket.app", "pasket.app/Contents", "pasket.app/Contents/MacOS",
                         "pasket.app/Contents/MacOS/pasket", "export"):
                self.assertEqual(stat.S_IMODE((root / name).stat().st_mode), 0o755, name)
            for name in ("pasket.app/Contents/Info.plist", "pasket.app/Contents/embedded.provisionprofile",
                         "export/pasket.pkg"):
                self.assertEqual(stat.S_IMODE((root / name).stat().st_mode), 0o644, name)

    def run_script(self, env):
        script = Path(__file__).with_name("upload-testflight.sh")
        return subprocess.run(["/bin/bash", str(script)], env=env, capture_output=True, text=True)

    def test_refuses_local_and_self_hosted_credential_import(self):
        for env in ({}, {"GITHUB_ACTIONS": "true", "RUNNER_OS": "macOS", "RUNNER_ENVIRONMENT": "self-hosted"}):
            with self.subTest(env=env):
                result = self.run_script(env)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("GitHub-hosted macOS", result.stderr)

    def test_missing_credentials_fail_before_any_keychain_changes(self):
        result = self.run_script({"GITHUB_ACTIONS": "true", "RUNNER_OS": "macOS", "RUNNER_ENVIRONMENT": "github-hosted"})
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Missing required variable: APP_STORE_CERTIFICATES_BASE64", result.stdout)

    def test_identity_validation_reports_missing_and_duplicate_identity_types(self):
        script = Path(__file__).with_name("upload-testflight.sh").read_text()
        validation = script[script.index("# Installer identities are not code-signing identities;"):
                            script.index("\nsecurity cms -D")]
        app = f'  1) {"A" * 40} "Apple Distribution: Example (TESTTEAM01)"'
        legacy_app = f'  1) {"B" * 40} "3rd Party Mac Developer Application: Example (TESTTEAM01)"'
        installer = f'  2) {"C" * 40} "3rd Party Mac Developer Installer: Example (TESTTEAM01)"'
        alternate_installer = f'  2) {"D" * 40} "Mac Installer Distribution: Example (TESTTEAM01)"'
        unrelated = f'  3) {"E" * 40} "Developer ID Application: Example (TESTTEAM01)"'
        for identities, expected_errors in (
            (f"{app}\n{installer}\n{unrelated}", ()),
            (f"{legacy_app}\n{alternate_installer}", ()),
            (installer, (("Apple Distribution", 0),)),
            (app, (("Mac Installer Distribution", 0),)),
            ("0 valid identities found", (("Apple Distribution", 0), ("Mac Installer Distribution", 0))),
            (unrelated, (("Apple Distribution", 0), ("Mac Installer Distribution", 0))),
            (f"{app}\n{legacy_app}\n{installer}", (("Apple Distribution", 2),)),
            (f"{app}\n{installer}\n{alternate_installer}", (("Mac Installer Distribution", 2),)),
        ):
            with self.subTest(identities=identities):
                # Exercise selection without importing credentials or accessing a keychain.
                result = subprocess.run(
                    ["/bin/bash", "-euc", 'security() { printf "%s\\n" "$TEST_IDENTITIES"; }\n'
                     'keychain_path=synthetic-keychain\n' + validation],
                    env={**os.environ, "TEST_IDENTITIES": identities}, capture_output=True, text=True,
                )
                self.assertEqual(result.returncode, 1 if expected_errors else 0, result.stderr)
                errors = [line for line in result.stdout.splitlines() if "Expected exactly one" in line]
                self.assertEqual(len(errors), len(expected_errors))
                for line, (identity_type, count) in zip(errors, expected_errors):
                    self.assertIn(identity_type, line)
                    self.assertIn(f"found {count} signing identities", line)
                if expected_errors:
                    self.assertIn("Zero matches can mean", result.stdout)
                self.assertEqual("Detected Developer ID signing identities" in result.stdout,
                                 bool(expected_errors) and unrelated in identities)

    def test_cleanup_before_profile_installation_works_in_macos_bash(self):
        script = Path(__file__).with_name("upload-testflight.sh").read_text()
        cleanup = script[script.index("cleanup() {\n"):script.index("\ntrap cleanup EXIT")]
        with tempfile.TemporaryDirectory(prefix="pasket-testflight-test-") as directory:
            work = Path(directory) / "credentials"
            work.mkdir()
            (work / "AuthKey.p8").write_text("synthetic private key")
            result = subprocess.run(
                ["/bin/bash", "-uc", cleanup + '\nwork_directory="$1"\n'
                 'keychain_path="$1/signing.keychain-db"\nprofile_paths=()\n'
                 'original_keychains=()\ncleanup', "cleanup-test", str(work)],
                capture_output=True, text=True,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertFalse(work.exists(), "Decoded credentials must be deleted on early failures.")


if __name__ == "__main__":
    unittest.main()
