#!/usr/bin/env python3
"""Plan sequential alpha, beta, rc, and stable releases from repository tags."""

import argparse
from dataclasses import dataclass
import json
from pathlib import Path
import re
import subprocess


PROJECT = Path("pasket.xcodeproj/project.pbxproj")
CHANNELS = ("alpha", "beta", "rc", "stable")
NUMBER = r"(0|[1-9][0-9]*)"
VERSION = re.compile(rf"{NUMBER}\.{NUMBER}\.{NUMBER}")
TAG = re.compile(rf"v{NUMBER}\.{NUMBER}\.{NUMBER}(?:-(alpha|beta|rc)\.([1-9][0-9]*))?")


@dataclass(frozen=True, order=True)
class ReleaseVersion:
    base: tuple[int, int, int]
    stage: int = 3
    number: int = 0

    @property
    def version(self):
        return ".".join(map(str, self.base))

    @property
    def label(self):
        suffix = "" if self.stage == 3 else f"-{CHANNELS[self.stage]}.{self.number}"
        return self.version + suffix

    @property
    def tag(self):
        return "v" + self.label


@dataclass(frozen=True)
class ReleaseRecord:
    release: ReleaseVersion
    build: int


def parse_tag(tag):
    match = TAG.fullmatch(tag)
    if not match:
        raise ValueError(f"Invalid release tag {tag!r}. Use v1.0.0 or v1.0.0-alpha.1/beta.1/rc.1.")
    base = tuple(map(int, match.group(1, 2, 3)))
    return ReleaseVersion(base, CHANNELS.index(match[4]) if match[4] else 3, int(match[5] or 0))


def setting_pattern(name):
    return re.compile(rf"(?m)^(\s*{name}\s*=\s*)([^;\n]+)(;)")


def read_versions(source):
    values = []
    for name in ("MARKETING_VERSION", "CURRENT_PROJECT_VERSION"):
        settings = {match[1].strip() for match in setting_pattern(name).findall(source)}
        if len(settings) != 1:
            raise ValueError(f"All Xcode configurations must have the same {name}.")
        values.append(settings.pop())
    version, build = values
    if not VERSION.fullmatch(version):
        raise ValueError("MARKETING_VERSION must be a version such as 1.0.0.")
    if not re.fullmatch(r"[1-9][0-9]*", build):
        raise ValueError("CURRENT_PROJECT_VERSION must be a positive integer.")
    return version, int(build)


def next_base(base, kind):
    components = list(base)
    index = {"major": 0, "minor": 1, "patch": 2}[kind]
    components[index] += 1
    for following in range(index + 1, 3):
        components[following] = 0
    return tuple(components)


def validate_history(history):
    previous = None
    for record in history:
        current = record.release
        if previous is None:
            if current.stage != 3 and current.number != 1:
                raise ValueError("The first prerelease must start at sequence 1.")
        else:
            before = previous.release
            if record.build != previous.build + 1:
                raise ValueError(f"Build number for {current.tag} must follow {previous.build} by one.")
            if before.stage == 3:
                if current.base not in {next_base(before.base, kind) for kind in ("patch", "minor", "major")}:
                    raise ValueError(f"{current.tag} must start the next patch, minor, or major version after {before.tag}.")
                if current.stage != 3 and current.number != 1:
                    raise ValueError("A new prerelease cycle must start at sequence 1.")
            else:
                if current.base != before.base or current.stage < before.stage:
                    raise ValueError(f"Finish {before.version} in stage order before starting another version.")
                expected = before.number + 1 if current.stage == before.stage else (0 if current.stage == 3 else 1)
                if current.number != expected:
                    raise ValueError(f"Unexpected prerelease sequence for {current.tag}; expected {expected}.")
        previous = record


def bump_versions(source, kind, channel, history):
    validate_history(history)
    version, build = read_versions(source)
    base = tuple(map(int, version.split(".")))
    stage = CHANNELS.index(channel)
    number = 0 if stage == 3 else 1
    if history:
        previous = history[-1]
        if (version, build) != (previous.release.version, previous.build):
            raise ValueError("Project version/build must match the latest release tag before bumping.")
        if previous.release.stage == 3:
            base = next_base(base, kind)
        elif stage < previous.release.stage:
            raise ValueError(f"Cannot move from {CHANNELS[previous.release.stage]} back to {channel}.")
        elif stage == previous.release.stage:
            number = previous.release.number + 1
    release = ReleaseVersion(base, stage, number)
    record = ReleaseRecord(release, build + 1)
    validate_history([*history, record])
    for name, value in (("MARKETING_VERSION", release.version), ("CURRENT_PROJECT_VERSION", str(record.build))):
        source = setting_pattern(name).sub(lambda match: match[1] + value + match[3], source)
    return source, record


def check_tag(source, tag, history):
    release = parse_tag(tag)
    version, build = read_versions(source)
    if release.version != version:
        raise ValueError(f"Release tag {tag!r} must match the project version v{version}.")
    existing = next((record for record in history if record.release == release), None)
    if existing is not None and existing.build != build:
        raise ValueError("Project build number does not match the tagged release.")
    if existing is None and any(record.release > release for record in history):
        raise ValueError("A new release tag cannot precede an existing release.")
    # Old tags remain retryable even after newer versions have been released.
    preceding = [record for record in history if record.release < release]
    record = ReleaseRecord(release, build)
    validate_history([*preceding, record])
    return record


def git(*arguments):
    return subprocess.run(["git", *arguments], text=True, capture_output=True, check=True).stdout.strip()


def load_history(project):
    project_path = project.resolve().relative_to(Path.cwd().resolve()).as_posix()
    history = []
    for tag in git("tag", "--list", "v*").splitlines():
        release = parse_tag(tag)
        version, build = read_versions(git("show", f"refs/tags/{tag}:{project_path}"))
        if version != release.version:
            raise ValueError(f"Tag {tag} does not match its committed project version.")
        history.append(ReleaseRecord(release, build))
    return sorted(history, key=lambda record: record.release)


def verify_ancestry(history):
    for before, after in zip(history, history[1:]):
        git("merge-base", "--is-ancestor", f"refs/tags/{before.release.tag}", f"refs/tags/{after.release.tag}")
    if history:
        git("merge-base", "--is-ancestor", f"refs/tags/{history[-1].release.tag}", "HEAD")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("read", "bump", "check"))
    parser.add_argument("value", nargs="?")
    parser.add_argument("--channel", choices=CHANNELS, default="stable")
    parser.add_argument("--project", type=Path, default=PROJECT)
    parser.add_argument("--github-output", type=Path)
    args = parser.parse_args()
    try:
        source = args.project.read_text()
        if args.command == "read":
            version, build = read_versions(source)
            record = ReleaseRecord(parse_tag("v" + version), build)
        else:
            history = load_history(args.project)
            if args.command == "bump":
                if args.value not in ("major", "minor", "patch"):
                    parser.error("bump requires major, minor, or patch")
                verify_ancestry(history)
                updated, record = bump_versions(source, args.value, args.channel, history)
                args.project.write_text(updated)
            else:
                record = check_tag(source, args.value or "", history)
                verify_ancestry([item for item in history if item.release < record.release])
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        detail = error.stderr if isinstance(error, subprocess.CalledProcessError) else str(error)
        parser.error(detail or str(error))
    release = record.release
    result = {
        "version": release.version,
        "build": record.build,
        "tag": release.tag,
        "message": f"chore(release): bump version to {release.label}",
    }
    if args.github_output:
        with args.github_output.open("a") as output:
            for key, value in result.items():
                output.write(f"{key}={value}\n")
    print(json.dumps(result))


if __name__ == "__main__":
    main()
