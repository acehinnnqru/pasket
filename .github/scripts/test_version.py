#!/usr/bin/env python3
"""Regression tests for release version consistency and bump boundaries."""

import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

sys.dont_write_bytecode = True
from version import bump_versions, check_tag, read_versions


SOURCE = """// Project metadata must stay unchanged.
Debug = {
    MARKETING_VERSION = 1.9.9;
    CURRENT_PROJECT_VERSION = 42;
    DEVELOPMENT_TEAM = EXAMPLE;
};
Release = {
    MARKETING_VERSION = 1.9.9;
    CURRENT_PROJECT_VERSION = 42;
    DEVELOPMENT_TEAM = EXAMPLE;
};
"""


class VersionTests(unittest.TestCase):
    def test_bump_resets_lower_components_and_increments_build(self):
        for kind, expected in (("patch", "1.9.10"), ("minor", "1.10.0"), ("major", "2.0.0")):
            with self.subTest(kind=kind):
                updated, version, build = bump_versions(SOURCE, kind)
                self.assertEqual((version, build), (expected, 43))
                self.assertEqual(read_versions(updated), (expected, 43))
                self.assertEqual(updated.count(f"MARKETING_VERSION = {expected};"), 2)
                self.assertEqual(updated.count("CURRENT_PROJECT_VERSION = 43;"), 2)

    def test_only_version_settings_change(self):
        updated, _, _ = bump_versions(SOURCE, "patch")
        self.assertEqual(updated.replace("1.9.10", "1.9.9").replace("= 43;", "= 42;"), SOURCE)

    def test_divergent_versions_fail_before_writing(self):
        for setting, replacement in (("1.9.9", "1.9.8"), ("= 42;", "= 41;")):
            with self.subTest(setting=setting):
                with self.assertRaises(ValueError):
                    bump_versions(SOURCE.replace(setting, replacement, 1), "patch")

    def test_missing_settings_are_rejected(self):
        for name in ("MARKETING_VERSION", "CURRENT_PROJECT_VERSION"):
            with self.subTest(name=name):
                source = "\n".join(line for line in SOURCE.splitlines() if name not in line)
                with self.assertRaises(ValueError):
                    read_versions(source)

    def test_noncanonical_versions_and_builds_are_rejected(self):
        for invalid in ("01.9.9", "1.9", "1.9.9-beta", '"1.9.9"'):
            with self.subTest(version=invalid):
                with self.assertRaises(ValueError):
                    read_versions(SOURCE.replace("1.9.9", invalid))
        for invalid in ("0", "-1", "1.2", "01"):
            with self.subTest(build=invalid):
                with self.assertRaises(ValueError):
                    read_versions(SOURCE.replace("= 42;", f"= {invalid};"))

    def test_release_and_prerelease_tags_match_repository_version(self):
        for tag in ("v1.9.9", "v1.9.9-rc.1", "v1.9.9-beta"):
            with self.subTest(tag=tag):
                self.assertEqual(check_tag(SOURCE, tag), ("1.9.9", 42))

    def test_mismatched_or_malformed_tags_are_rejected(self):
        for tag in ("v2.0.0", "1.9.9", "v1.9.9-", "v1.9.9-rc..1", "v1.9.9/foo", "v01.9.9", "v1.9.9;echo bad"):
            with self.subTest(tag=tag):
                with self.assertRaises(ValueError):
                    check_tag(SOURCE, tag)

    def test_cli_updates_project_and_publishes_matching_outputs(self):
        script = Path(__file__).with_name("version.py")
        with tempfile.TemporaryDirectory(prefix="pasket-version-test-") as directory:
            project = Path(directory) / "project.pbxproj"
            output = Path(directory) / "github-output"
            project.write_text(SOURCE)
            result = subprocess.run(
                [sys.executable, str(script), "bump", "minor", "--project", str(project),
                 "--github-output", str(output)],
                capture_output=True, text=True, check=True,
            )
            self.assertEqual(read_versions(project.read_text()), ("1.10.0", 43))
            self.assertEqual(json.loads(result.stdout)["tag"], "v1.10.0")
            outputs = dict(line.split("=", 1) for line in output.read_text().splitlines())
            self.assertEqual(outputs["message"], "chore(release): bump version to 1.10.0")
            self.assertEqual(outputs["tag"], "v1.10.0")
            self.assertEqual(outputs["build"], "43")
            rejected = subprocess.run(
                [sys.executable, str(script), "check", "v1.9.9", "--project", str(project)],
                capture_output=True, text=True,
            )
            self.assertNotEqual(rejected.returncode, 0)
            self.assertEqual(read_versions(project.read_text()), ("1.10.0", 43))


if __name__ == "__main__":
    unittest.main()
