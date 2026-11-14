#!/usr/bin/env python3
"""Prepare a pinned Play! checkout for the experimental PS2 Games Lab IPA."""

import argparse
import json
import plistlib
import shutil
import subprocess
from pathlib import Path


def git(source, *args):
    return subprocess.check_output(["git", "-C", str(source), *args]).decode().rstrip("\n")


def prepare(source, project):
    revision = (project / "ios/play-revision.txt").read_text().strip()
    if git(source, "rev-parse", "HEAD") != revision:
        raise ValueError("Play! revision does not match ios/play-revision.txt")
    submodules = git(source, "submodule", "status", "--recursive")
    if any(line[0] != " " for line in submodules.splitlines()):
        raise ValueError("Play! submodules must be initialized at their pinned revisions")

    template = source / "Source/ui_ios/Info.plist.in"
    with template.open("rb") as stream:
        info = plistlib.load(stream)
    info.update({
        "CFBundleIdentifier": "com.luisgsilva950.ps2gameslab",
        "CFBundleName": "PS2 Games Lab",
        "CFBundleDisplayName": "PS2 Lab (Play!)",
        "CFBundleShortVersionString": "0.1.0",
        "CFBundleVersion": "1",
        "UIRequiredDeviceCapabilities": ["arm64", "opengles-3"],
    })
    with template.open("wb") as stream:
        plistlib.dump(info, stream, sort_keys=False)

    # Preserve upstream and dependency notices both inside the app and next to the IPA.
    notices = source / "PS2GamesLabNotices"
    notices.mkdir(exist_ok=True)
    tracked = subprocess.check_output([
        "git", "-C", str(source), "ls-files", "--recurse-submodules", "-z"
    ]).decode().split("\0")
    count = 0
    for relative in filter(None, tracked):
        path = Path(relative)
        if path.name.lower().startswith(("license", "licence", "copying", "copyright", "notice")):
            destination = notices / "licenses" / path
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(source / path, destination)
            count += 1
    if count == 0 or not (notices / "licenses/License.txt").is_file():
        raise ValueError("Missing upstream license notices")

    shutil.copyfile(project / "docs/ipad.md", notices / "README.md")
    provenance = {
        "project": "PS2 Games Lab experimental native companion",
        "upstream": "https://github.com/jpd002/Play-",
        "revision": revision,
        "submodules": submodules,
        "renderer": "OpenGL ES (no Vulkan SDK bundled)",
        "signing": "ad-hoc only; re-signing and provisioning required for installation",
        "device_validation": "not performed by this build",
        "changes": "app identity and bundled notices only; upstream emulation and JIT unchanged",
    }
    (notices / "build-info.json").write_text(json.dumps(provenance, indent=2) + "\n")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("project", type=Path)
    args = parser.parse_args()
    prepare(args.source.resolve(), args.project.resolve())
