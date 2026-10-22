#!/usr/bin/env python3
"""Regression tests for release progression, tag history, and version consistency."""

from contextlib import redirect_stderr, redirect_stdout
import io
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.dont_write_bytecode = True
import version
from version import ReleaseRecord, bump_versions, check_tag, next_base, parse_tag, read_versions, validate_history


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


def record(tag, build):
    return ReleaseRecord(parse_tag(tag), build)


def source_for(release):
    return SOURCE.replace("1.9.9", release.release.version).replace("= 42;", f"= {release.build};")


class VersionTests(unittest.TestCase):
    def test_numeric_bumps_reset_lower_components(self):
        for kind, expected in (("patch", (1, 9, 10)), ("minor", (1, 10, 0)), ("major", (2, 0, 0))):
            with self.subTest(kind=kind):
                self.assertEqual(next_base((1, 9, 9), kind), expected)

    def test_first_release_uses_existing_project_version(self):
        for channel in version.CHANNELS:
            with self.subTest(channel=channel):
                updated, result = bump_versions(SOURCE, "major", channel, [])
                expected = "v1.9.9" + ("" if channel == "stable" else f"-{channel}.1")
                self.assertEqual(result.release.tag, expected)
                self.assertEqual(read_versions(updated), ("1.9.9", 43))

    def test_stable_release_opens_next_cycle(self):
        for kind, expected in (("patch", "1.9.10"), ("minor", "1.10.0"), ("major", "2.0.0")):
            for channel in version.CHANNELS:
                with self.subTest(kind=kind, channel=channel):
                    updated, result = bump_versions(SOURCE, kind, channel, [record("v1.9.9", 42)])
                    self.assertEqual(read_versions(updated), (expected, 43))
                    suffix = "" if channel == "stable" else f"-{channel}.1"
                    self.assertEqual(result.release.tag, "v" + expected + suffix)

    def test_complete_prerelease_cycle_keeps_base_and_increments_build(self):
        source = SOURCE
        history = [record("v1.9.9", 42)]
        steps = [
            ("alpha", "v1.9.10-alpha.1"), ("alpha", "v1.9.10-alpha.2"),
            ("beta", "v1.9.10-beta.1"), ("beta", "v1.9.10-beta.2"),
            ("rc", "v1.9.10-rc.1"), ("rc", "v1.9.10-rc.2"), ("stable", "v1.9.10"),
        ]
        for build, (channel, tag) in enumerate(steps, 43):
            # Even a major selection must not change an already open prerelease cycle.
            source, result = bump_versions(source, "patch" if build == 43 else "major", channel, history)
            self.assertEqual(result.release.tag, tag)
            self.assertEqual(read_versions(source), ("1.9.10", build))
            self.assertEqual(check_tag(source, tag, history), result)
            history.append(result)

    def test_stages_can_be_skipped(self):
        for before, after in (("alpha", "rc"), ("alpha", "stable"), ("beta", "stable")):
            with self.subTest(before=before, after=after):
                prior = record(f"v1.9.9-{before}.1", 42)
                _, result = bump_versions(SOURCE, "minor", after, [prior])
                expected = "v1.9.9" + ("" if after == "stable" else f"-{after}.1")
                self.assertEqual(result.release.tag, expected)

    def test_backward_stages_are_rejected(self):
        for before, after in (("beta", "alpha"), ("rc", "beta"), ("rc", "alpha")):
            with self.subTest(before=before, after=after):
                with self.assertRaisesRegex(ValueError, "Cannot move"):
                    bump_versions(SOURCE, "patch", after, [record(f"v1.9.9-{before}.1", 42)])

    def test_numeric_sequence_ordering(self):
        tags = ["v1.0.0-alpha.10", "v1.0.0-rc.1", "v1.0.0", "v1.0.0-alpha.9", "v1.0.0-beta.1"]
        self.assertEqual([item.tag for item in sorted(map(parse_tag, tags))], [
            "v1.0.0-alpha.9", "v1.0.0-alpha.10", "v1.0.0-beta.1", "v1.0.0-rc.1", "v1.0.0",
        ])

    def test_only_version_settings_change_in_all_configurations(self):
        updated, _ = bump_versions(SOURCE, "patch", "alpha", [record("v1.9.9", 42)])
        self.assertEqual(updated.replace("1.9.10", "1.9.9").replace("= 43;", "= 42;"), SOURCE)
        self.assertEqual(updated.count("MARKETING_VERSION = 1.9.10;"), 2)
        self.assertEqual(updated.count("CURRENT_PROJECT_VERSION = 43;"), 2)

    def test_repository_drift_is_rejected(self):
        for altered in (SOURCE.replace("1.9.9", "1.9.10"), SOURCE.replace("= 42;", "= 43;")):
            with self.subTest(source=altered):
                with self.assertRaisesRegex(ValueError, "latest release tag"):
                    bump_versions(altered, "patch", "alpha", [record("v1.9.9", 42)])

    def test_inconsistent_configurations_are_rejected(self):
        for setting, replacement in (("1.9.9", "1.9.8"), ("= 42;", "= 41;")):
            with self.subTest(setting=setting):
                with self.assertRaises(ValueError):
                    read_versions(SOURCE.replace(setting, replacement, 1))

    def test_missing_or_noncanonical_settings_are_rejected(self):
        for name in ("MARKETING_VERSION", "CURRENT_PROJECT_VERSION"):
            with self.subTest(name=name):
                with self.assertRaises(ValueError):
                    read_versions("\n".join(line for line in SOURCE.splitlines() if name not in line))
        for old, new in (("1.9.9", "01.9.9"), ("1.9.9", "1.9.9-beta.1"), ("= 42;", "= 0;"), ("= 42;", "= 1.2;")):
            with self.subTest(new=new):
                with self.assertRaises(ValueError):
                    read_versions(SOURCE.replace(old, new))

    def test_malformed_or_unsupported_tags_are_rejected(self):
        for tag in ("1.0.0", "v01.0.0", "v1.0.0-alpha", "v1.0.0-alpha.0", "v1.0.0-beta.01",
                    "v1.0.0-preview.1", "v1.0.0-rc.1.2", "v1.0.0-rc..1", "v1.0.0/foo", "v1.0.0;echo bad"):
            with self.subTest(tag=tag):
                with self.assertRaises(ValueError):
                    parse_tag(tag)

    def test_invalid_history_is_rejected(self):
        histories = [
            [record("v1.9.9-alpha.2", 42)],
            [record("v1.9.9-alpha.1", 42), record("v1.9.9-alpha.3", 43)],
            [record("v1.9.9-alpha.1", 42), record("v1.9.9-beta.2", 43)],
            [record("v1.9.9-alpha.1", 42), record("v1.9.9-beta.1", 44)],
            [record("v1.9.9-alpha.1", 42), record("v1.9.10-beta.1", 43)],
            [record("v1.9.9", 42), record("v1.9.11", 43)],
            [record("v1.9.9", 42), record("v1.9.10-alpha.2", 43)],
            [record("v1.9.9-alpha.1", 42), record("v1.9.9-alpha.1", 43)],
        ]
        for history in histories:
            with self.subTest(history=history):
                with self.assertRaises(ValueError):
                    validate_history(history)

    def test_manually_created_tags_must_be_next_in_sequence(self):
        prior = record("v1.9.9-alpha.1", 41)
        self.assertEqual(check_tag(SOURCE, "v1.9.9-alpha.2", [prior]).build, 42)
        for tag in ("v1.9.9-alpha.3", "v1.9.9-beta.2"):
            with self.subTest(tag=tag):
                with self.assertRaises(ValueError):
                    check_tag(SOURCE, tag, [prior])
        with self.assertRaises(ValueError):
            check_tag(SOURCE, "v2.0.0", [])
        with self.assertRaises(ValueError):
            check_tag(SOURCE, "v1.9.9-beta.1", [record("v1.9.9-alpha.1", 42)])

    def test_old_existing_tag_can_be_retried_after_new_release(self):
        older = record("v1.9.9-alpha.1", 41)
        newer = record("v1.9.9-beta.1", 42)
        self.assertEqual(check_tag(source_for(older), older.release.tag, [older, newer]), older)
        with self.assertRaises(ValueError):
            check_tag(SOURCE, older.release.tag, [older, newer])
        with self.assertRaises(ValueError):
            check_tag(SOURCE, "v1.9.9-alpha.2", [newer])

    def test_tag_history_loads_committed_versions_in_numeric_order(self):
        first = record("v1.9.9-alpha.1", 41)
        second = record("v1.9.9-beta.1", 42)
        def fake_git(*arguments):
            if arguments[0] == "tag":
                return "v1.9.9-beta.1\nv1.9.9-alpha.1"
            return source_for(first if "alpha" in arguments[1] else second)
        with patch("version.git", side_effect=fake_git):
            self.assertEqual(version.load_history(version.PROJECT), [first, second])
        with patch("version.git", side_effect=["v2.0.0", SOURCE]):
            with self.assertRaisesRegex(ValueError, "committed project version"):
                version.load_history(version.PROJECT)

    def test_release_history_must_follow_git_ancestry(self):
        history = [record("v1.9.9-alpha.1", 41), record("v1.9.9-beta.1", 42)]
        with patch("version.git") as git:
            version.verify_ancestry(history)
            self.assertEqual(git.call_args_list[0].args, (
                "merge-base", "--is-ancestor", "refs/tags/v1.9.9-alpha.1", "refs/tags/v1.9.9-beta.1",
            ))
            self.assertEqual(git.call_args_list[1].args, (
                "merge-base", "--is-ancestor", "refs/tags/v1.9.9-beta.1", "HEAD",
            ))
        with patch("version.git", side_effect=subprocess.CalledProcessError(1, ["git", "merge-base"])):
            with self.assertRaises(subprocess.CalledProcessError):
                version.verify_ancestry(history)

    def test_cli_emits_exact_tag_and_message_without_touching_other_settings(self):
        with tempfile.TemporaryDirectory(prefix="pasket-version-test-") as directory:
            project = Path(directory) / "project.pbxproj"
            output = Path(directory) / "github-output"
            project.write_text(SOURCE)
            arguments = ["version.py", "bump", "minor", "--channel", "beta", "--project", str(project), "--github-output", str(output)]
            with patch.object(sys, "argv", arguments), patch("version.load_history", return_value=[record("v1.9.9", 42)]), patch("version.verify_ancestry"), redirect_stdout(io.StringIO()) as printed:
                version.main()
            self.assertEqual(read_versions(project.read_text()), ("1.10.0", 43))
            self.assertEqual(json.loads(printed.getvalue())["tag"], "v1.10.0-beta.1")
            outputs = dict(line.split("=", 1) for line in output.read_text().splitlines())
            self.assertEqual(outputs["message"], "chore(release): bump version to 1.10.0-beta.1")
            self.assertEqual(outputs["build"], "43")

    def test_rejected_cli_request_does_not_write_project_or_outputs(self):
        with tempfile.TemporaryDirectory(prefix="pasket-version-test-") as directory:
            project = Path(directory) / "project.pbxproj"
            output = Path(directory) / "github-output"
            project.write_text(SOURCE)
            arguments = ["version.py", "bump", "patch", "--channel", "alpha", "--project", str(project), "--github-output", str(output)]
            with patch.object(sys, "argv", arguments), patch("version.load_history", return_value=[record("v1.9.9-rc.1", 42)]), patch("version.verify_ancestry"), redirect_stderr(io.StringIO()):
                with self.assertRaises(SystemExit) as error:
                    version.main()
                self.assertEqual(error.exception.code, 2)
            self.assertEqual(project.read_text(), SOURCE)
            self.assertFalse(output.exists())

    def test_read_cli_does_not_need_tag_history(self):
        result = subprocess.run([sys.executable, str(Path(__file__).with_name("version.py")), "read"], capture_output=True, text=True, check=True)
        self.assertEqual(json.loads(result.stdout)["version"], read_versions(version.PROJECT.read_text())[0])


if __name__ == "__main__":
    unittest.main()
