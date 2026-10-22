#!/usr/bin/env python3
"""Keep every Xcode configuration's release version and build number in sync."""

import argparse
import json
import re
from pathlib import Path


PROJECT = Path("pasket.xcodeproj/project.pbxproj")
VERSION = re.compile(r"(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)")
TAG = re.compile(r"v([0-9]+\.[0-9]+\.[0-9]+)(?:-[a-zA-Z0-9]+(?:[.-][a-zA-Z0-9]+)*)?")


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


def bump_versions(source, kind):
    version, build = read_versions(source)
    components = list(map(int, version.split(".")))
    index = {"major": 0, "minor": 1, "patch": 2}[kind]
    components[index] += 1
    for following in range(index + 1, 3):
        components[following] = 0
    version = ".".join(map(str, components))
    build += 1
    for name, value in (("MARKETING_VERSION", version), ("CURRENT_PROJECT_VERSION", str(build))):
        source = setting_pattern(name).sub(lambda match: match[1] + value + match[3], source)
    return source, version, build


def check_tag(source, tag):
    version, build = read_versions(source)
    match = TAG.fullmatch(tag)
    if not match or match[1] != version:
        raise ValueError(f"Release tag {tag!r} must match the project version v{version}.")
    return version, build


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("read", "bump", "check"))
    parser.add_argument("value", nargs="?")
    parser.add_argument("--project", type=Path, default=PROJECT)
    parser.add_argument("--github-output", type=Path)
    args = parser.parse_args()
    source = args.project.read_text()
    try:
        if args.command == "bump":
            if args.value not in ("major", "minor", "patch"):
                parser.error("bump requires major, minor, or patch")
            updated, version, build = bump_versions(source, args.value)
            args.project.write_text(updated)
        elif args.command == "check":
            version, build = check_tag(source, args.value or "")
        else:
            version, build = read_versions(source)
    except ValueError as error:
        parser.error(str(error))
    result = {
        "version": version,
        "build": build,
        "tag": f"v{version}",
        "message": f"chore(release): bump version to {version}",
    }
    if args.github_output:
        with args.github_output.open("a") as output:
            for key, value in result.items():
                output.write(f"{key}={value}\n")
    print(json.dumps(result))


if __name__ == "__main__":
    main()
