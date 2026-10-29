#!/usr/bin/env python3
"""Exercise signing keychain lifecycle with synthetic files and a fake security tool."""

import base64
import json
import os
from pathlib import Path
import stat
import subprocess
import sys
import tempfile
import unittest


HELPER = Path(__file__).with_name("signing-keychain.sh").resolve()
CERTIFICATE = base64.b64encode(b"synthetic signing identity").decode()

# Every security invocation is handled here. Unknown operations fail closed;
# this fixture never delegates to the real macOS security command.
FAKE_SECURITY = r'''
import hashlib
import json
import os
from pathlib import Path
import sys

root = Path(os.environ["MOCK_DIRECTORY"])
arguments = sys.argv[1:]
with (root / "calls.jsonl").open("a") as output:
    output.write(json.dumps(arguments) + "\n")
command = arguments[0]
search_file = root / "search.json"
search = json.loads(search_file.read_text())
original = json.loads((root / "original.json").read_text())
failure = os.environ.get("MOCK_FAIL", "")

def target(value):
    path = Path(value)
    path.relative_to(root)
    assert not path.is_symlink(), "Mock refused symlink"
    return path

if command == "list-keychains":
    if arguments == ["list-keychains", "-d", "user"]:
        if failure == "list":
            sys.exit(42)
        for item in search:
            print('    "' + item + '"')
    elif arguments[1:4] == ["-d", "user", "-s"]:
        new_search = arguments[4:]
        if failure == "restore" and new_search == original:
            sys.exit(42)
        search_file.write_text(json.dumps(new_search))
    else:
        sys.exit(90)
elif command == "create-keychain":
    assert arguments[1] == "-p"
    path = target(arguments[3])
    assert not path.exists(), "Mock refused overwrite"
    path.write_text(json.dumps({"password_hash": hashlib.sha256(arguments[2].encode()).hexdigest()}))
    path.chmod(int(os.environ.get("MOCK_CREATE_MODE", "600"), 8))
    search_file.write_text(json.dumps(search + [str(path)]))
    if failure == "create":
        sys.exit(42)
elif command == "set-keychain-settings":
    assert arguments[1:3] == ["-lut", "21600"]
    assert target(arguments[-1]).is_file()
elif command == "unlock-keychain":
    assert arguments[1] == "-p"
    saved = json.loads(target(arguments[-1]).read_text())
    if failure == "unlock" or saved["password_hash"] != hashlib.sha256(arguments[2].encode()).hexdigest():
        print("Mock keychain password rejected", file=sys.stderr)
        sys.exit(42)
elif command == "import":
    source = target(arguments[1])
    assert source.stat().st_mode & 0o777 == 0o600
    assert source.read_bytes() == b"synthetic signing identity"
    assert "-A" not in arguments
    tools = [arguments[i + 1] for i, item in enumerate(arguments) if item == "-T"]
    assert tools == ["/usr/bin/codesign", "/usr/bin/productbuild", "/usr/bin/security"]
    assert target(arguments[arguments.index("-k") + 1]).is_file()
    if failure == "import":
        sys.exit(42)
elif command == "set-key-partition-list":
    assert arguments[1:4] == ["-S", "apple-tool:,apple:,codesign:", "-s"]
    assert target(arguments[-1]).is_file()
    if failure == "authorize":
        sys.exit(42)
elif command == "lock-keychain":
    assert target(arguments[-1]).is_file()
    if failure == "lock":
        sys.exit(42)
elif command == "delete-keychain":
    path = target(arguments[-1])
    if failure == "delete":
        sys.exit(42)
    path.unlink()
    search_file.write_text(json.dumps([item for item in search if item != str(path)]))
else:
    raise AssertionError("Unexpected security operation: " + command)
'''

SHELL = r'''
set -euo pipefail
umask 077
security() { "$MOCK_PYTHON" "$MOCK_SECURITY" "$@"; }
openssl() {
  [[ "$*" == 'rand -hex 32' ]] || return 99
  printf '%064d\n' 1
}
mv() {
  command mv "$@" || return
  if [[ "${MOCK_ACTION:-}" == metadata-terminate ]]; then
    kill -TERM $$
  fi
}
source "$1"
signing_keychain_root() { printf '%s\n' "$MOCK_DIRECTORY/managed"; }
cleanup() {
  local result=$?
  trap - EXIT
  if ! signing_keychain_cleanup; then
    [[ "$result" != 0 ]] || result=1
  fi
  rm -rf "$MOCK_WORK"
  exit "$result"
}
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM
signing_keychain_prepare "${MOCK_PURPOSE:-developer-id}" "$MOCK_WORK" P12_DATA P12_PASSWORD
if [[ "${MOCK_ACTION:-}" == invalid-identity ]]; then
  exit 47
fi
signing_keychain_ready
if [[ "${MOCK_ACTION:-}" == terminate ]]; then
  kill -TERM $$
fi
if [[ "${MOCK_ACTION:-}" == build-failure ]]; then
  exit 48
fi
'''


class TestSigningKeychain(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="pasket-signing-test-")
        self.addCleanup(self.temporary.cleanup)
        self.directory = Path(self.temporary.name).resolve()
        self.managed = self.directory / "managed"
        self.keychain = self.managed / "owner" / "repository" / "TESTTEAM01" / "developer-id.keychain-db"
        self.metadata = Path(str(self.keychain) + ".ready")
        self.lock = self.managed / ".signing.lock"
        self.original = [str(self.directory / "login.keychain-db"), str(self.directory / "another keychain.keychain-db")]
        (self.directory / "original.json").write_text(json.dumps(self.original))
        (self.directory / "search.json").write_text(json.dumps(self.original))
        self.fake = self.directory / "security.py"
        self.fake.write_text(FAKE_SECURITY)
        self.calls_path = self.directory / "calls.jsonl"

    def run_helper(self, **overrides):
        work = self.directory / "work"
        work.mkdir(mode=0o700, exist_ok=True)
        environment = {
            **os.environ,
            "GITHUB_ACTIONS": "true",
            "RUNNER_OS": "macOS",
            "RUNNER_ENVIRONMENT": "self-hosted",
            "GITHUB_REPOSITORY": "owner/repository",
            "APPLE_TEAM_ID": "TESTTEAM01",
            "CI_KEYCHAIN_PASSWORD": "synthetic-keychain-password",
            "P12_DATA": CERTIFICATE,
            "P12_PASSWORD": "synthetic-p12-password",
            "MOCK_DIRECTORY": str(self.directory),
            "MOCK_WORK": str(work),
            "MOCK_PYTHON": sys.executable,
            "MOCK_SECURITY": str(self.fake),
        }
        environment.update(overrides)
        return subprocess.run(
            ["/bin/bash", "-c", SHELL, "keychain-test", str(HELPER)],
            env=environment, text=True, capture_output=True,
        )

    def calls(self):
        if not self.calls_path.exists():
            return []
        return [json.loads(line) for line in self.calls_path.read_text().splitlines()]

    def commands(self):
        return [call[0] for call in self.calls()]

    def assert_restored(self):
        self.assertEqual(json.loads((self.directory / "search.json").read_text()), self.original)
        self.assertFalse(self.lock.exists())
        self.assertFalse((self.directory / "work").exists())

    def test_first_setup_imports_and_authorizes_then_locks_private_keychain(self):
        result = self.run_helper()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(self.keychain.is_file())
        self.assertTrue(self.metadata.is_file())
        self.assertEqual(self.commands().count("import"), 1)
        self.assertEqual(self.commands().count("set-key-partition-list"), 1)
        self.assertIn("lock-keychain", self.commands())
        self.assertNotIn("delete-keychain", self.commands())
        for path in (self.keychain, self.metadata):
            self.assertEqual(stat.S_IMODE(path.stat().st_mode), 0o600)
        for path in (self.managed, self.keychain.parent, self.keychain.parent.parent):
            self.assertEqual(stat.S_IMODE(path.stat().st_mode), 0o700)
        self.assert_restored()

    def test_existing_keychain_reuses_identity_without_p12_or_reauthorization(self):
        self.assertEqual(self.run_helper().returncode, 0)
        original_contents = self.keychain.read_bytes()
        self.calls_path.unlink()
        result = self.run_helper(P12_DATA="", P12_PASSWORD="")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.keychain.read_bytes(), original_contents)
        self.assertNotIn("create-keychain", self.commands())
        self.assertNotIn("import", self.commands())
        self.assertNotIn("set-key-partition-list", self.commands())
        self.assertIn("unlock-keychain", self.commands())
        self.assertIn("lock-keychain", self.commands())
        self.assert_restored()

    def test_new_keychain_permissions_are_restricted_before_import(self):
        result = self.run_helper(MOCK_CREATE_MODE="644")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(stat.S_IMODE(self.keychain.stat().st_mode), 0o600)
        self.assert_restored()

    def test_changed_p12_fails_without_touching_cached_identity(self):
        self.assertEqual(self.run_helper().returncode, 0)
        self.calls_path.unlink()
        result = self.run_helper(P12_DATA=base64.b64encode(b"replacement identity").decode())
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("configured P12 has changed", result.stderr)
        self.assertEqual(self.calls(), [])
        self.assertTrue(self.keychain.is_file())
        self.assert_restored()

    def test_wrong_password_preserves_cached_keychain_and_restores_state(self):
        self.assertEqual(self.run_helper().returncode, 0)
        original_contents = self.keychain.read_bytes()
        self.calls_path.unlink()
        result = self.run_helper(CI_KEYCHAIN_PASSWORD="different-synthetic-password")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Could not unlock", result.stderr)
        self.assertEqual(self.keychain.read_bytes(), original_contents)
        self.assertNotIn("delete-keychain", self.commands())
        self.assertIn("lock-keychain", self.commands())
        self.assert_restored()

    def test_initialization_failures_delete_only_new_keychain(self):
        for failure in ("create", "import", "authorize"):
            with self.subTest(failure=failure):
                result = self.run_helper(MOCK_FAIL=failure)
                self.assertNotEqual(result.returncode, 0)
                self.assertFalse(self.keychain.exists())
                self.assertFalse(self.metadata.exists())
                self.assert_restored()

    def test_invalid_identity_rejects_new_setup_but_keeps_existing_keychain(self):
        result = self.run_helper(MOCK_ACTION="invalid-identity")
        self.assertEqual(result.returncode, 47, result.stderr)
        self.assertFalse(self.keychain.exists())
        self.assertFalse(self.metadata.exists())
        self.assert_restored()
        self.assertEqual(self.run_helper().returncode, 0)
        result = self.run_helper(MOCK_ACTION="invalid-identity")
        self.assertEqual(result.returncode, 47, result.stderr)
        self.assertTrue(self.keychain.is_file())
        self.assertTrue(self.metadata.is_file())
        self.assert_restored()

    def test_job_failure_and_sigterm_lock_persistent_keychain(self):
        for action, expected in (("build-failure", 48), ("terminate", 143)):
            with self.subTest(action=action):
                result = self.run_helper(MOCK_ACTION=action)
                self.assertEqual(result.returncode, expected, result.stderr)
                self.assertTrue(self.keychain.is_file())
                self.assertIn("lock-keychain", self.commands())
                self.assert_restored()

    def test_sigterm_after_metadata_publish_removes_only_new_incomplete_state(self):
        result = self.run_helper(MOCK_ACTION="metadata-terminate")
        self.assertEqual(result.returncode, 143, result.stderr)
        self.assertFalse(self.keychain.exists())
        self.assertFalse(self.metadata.exists())
        self.assertEqual(list(self.keychain.parent.iterdir()), [])
        self.assert_restored()
        self.assertEqual(self.run_helper().returncode, 0)
        original_metadata = self.metadata.read_bytes()
        result = self.run_helper(MOCK_ACTION="invalid-identity")
        self.assertEqual(result.returncode, 47, result.stderr)
        self.assertTrue(self.keychain.is_file())
        self.assertEqual(self.metadata.read_bytes(), original_metadata)
        self.assert_restored()

    def test_hosted_runner_keeps_temporary_lifecycle(self):
        result = self.run_helper(RUNNER_ENVIRONMENT="github-hosted", CI_KEYCHAIN_PASSWORD="")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("delete-keychain", self.commands())
        self.assertNotIn("lock-keychain", self.commands())
        self.assertFalse(self.managed.exists())
        self.assert_restored()

    def test_guards_fail_before_keychain_operations(self):
        for overrides in (
            {"GITHUB_ACTIONS": "false"}, {"RUNNER_OS": "Linux"},
            {"RUNNER_ENVIRONMENT": "unknown"}, {"CI_KEYCHAIN_PASSWORD": ""},
            {"GITHUB_REPOSITORY": "../repository"}, {"APPLE_TEAM_ID": "invalid"},
        ):
            with self.subTest(overrides=overrides):
                result = self.run_helper(**overrides)
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(self.calls(), [])
        self.assertFalse(self.managed.exists())

    def test_initial_setup_requires_p12_but_does_not_touch_keychains(self):
        result = self.run_helper(P12_DATA="", P12_PASSWORD="")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Initial keychain setup requires", result.stderr)
        self.assertEqual(self.calls(), [])
        self.assert_restored()

    def test_concurrent_job_refuses_existing_shared_lock(self):
        self.managed.mkdir(mode=0o700)
        self.lock.mkdir(mode=0o700)
        result = self.run_helper(MOCK_PURPOSE="app-store")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Another signing task is active", result.stderr)
        self.assertTrue(self.lock.is_dir())
        self.assertEqual(self.calls(), [])

    def test_unsafe_directory_and_unknown_keychain_are_not_adopted(self):
        self.managed.mkdir(mode=0o755)
        result = self.run_helper()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("mode 700", result.stderr)
        self.managed.chmod(0o700)
        self.keychain.parent.mkdir(mode=0o700, parents=True)
        for directory in (self.keychain.parent.parent, self.keychain.parent.parent.parent):
            directory.chmod(0o700)
        self.keychain.write_text("unrelated existing keychain")
        self.keychain.chmod(0o600)
        result = self.run_helper()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("unknown or incomplete", result.stderr)
        self.assertEqual(self.keychain.read_text(), "unrelated existing keychain")
        self.assertEqual(self.calls(), [])
        self.assert_restored()

    def test_symlink_root_is_rejected_without_touching_target(self):
        target = self.directory / "unrelated"
        target.mkdir(mode=0o700)
        self.managed.symlink_to(target, target_is_directory=True)
        result = self.run_helper()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Refusing a symlink", result.stderr)
        self.assertEqual(list(target.iterdir()), [])
        self.assertEqual(self.calls(), [])

    def test_cleanup_failure_fails_job_and_retains_recovery_lock(self):
        for failure in ("restore", "lock"):
            with self.subTest(failure=failure):
                result = self.run_helper(MOCK_FAIL=failure)
                self.assertNotEqual(result.returncode, 0)
                self.assertTrue(self.keychain.is_file())
                self.assertTrue(self.lock.is_dir())
                self.assertIn("lock was retained", result.stderr)
                # Restore synthetic state between cases; no real keychain is used.
                self.lock.rmdir()
                (self.directory / "search.json").write_text(json.dumps(self.original))


if __name__ == "__main__":
    unittest.main()
