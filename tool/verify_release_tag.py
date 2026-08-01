#!/usr/bin/env python3
"""Verify that a Git release tag matches pubspec.yaml's version name."""

from __future__ import annotations

import argparse
import re
from pathlib import Path


class ReleaseTagError(ValueError):
    """Raised when release tag metadata is missing or inconsistent."""


_TAG_PATTERN = re.compile(
    r"^v(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)"
    r"(?:-[0-9A-Za-z]+(?:[.-][0-9A-Za-z]+)*)?$"
)
_VERSION_LINE = re.compile(
    r"^\s*version:\s*['\"]?([^'\"\s#]+)",
    re.MULTILINE,
)


def verify_release_tag(tag: str, pubspec: Path) -> str:
    if not _TAG_PATTERN.fullmatch(tag):
        raise ReleaseTagError(f"Invalid release tag: {tag!r}")
    try:
        contents = pubspec.read_text(encoding="utf-8")
    except OSError as error:
        raise ReleaseTagError(f"Unable to read {pubspec}: {error}") from error
    match = _VERSION_LINE.search(contents)
    if match is None:
        raise ReleaseTagError(f"No version field found in {pubspec}")
    declared = match.group(1)
    version_name = declared.split("+", maxsplit=1)[0]
    expected_tag = f"v{version_name}"
    if tag != expected_tag:
        raise ReleaseTagError(
            f"Release tag {tag!r} does not match pubspec version {version_name!r}"
        )
    return version_name


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--tag", required=True)
    parser.add_argument("--pubspec", type=Path, default=Path("pubspec.yaml"))
    arguments = parser.parse_args()
    try:
        version_name = verify_release_tag(arguments.tag, arguments.pubspec)
    except ReleaseTagError as error:
        parser.error(str(error))
    print(f"Release tag verified for version {version_name}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
