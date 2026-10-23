#!/usr/bin/env python3
"""Reject duplicate or out-of-order stable releases before changing the latest feed."""
import json
import re
import sys


def version(tag):
    match = re.fullmatch(r"v(\d+)\.(\d+)\.(\d+)", tag)
    return tuple(map(int, match.groups())) if match else None


def validate(releases, tag):
    current = version(tag)
    if current is None:
        raise ValueError("Invalid stable release tag")
    for release in releases:
        other = version(release["tag_name"])
        if release["tag_name"] == tag:
            raise ValueError("Release already exists; inspect it before retrying")
        if not release["draft"] and not release["prerelease"] and other and other >= current:
            raise ValueError("A newer stable release already exists; refusing to replace latest")


if __name__ == "__main__":
    with open(sys.argv[1]) as source:
        data = json.load(source)
        releases = [item for page in data for item in page] if data and isinstance(data[0], list) else data
        validate(releases, sys.argv[2])
