#!/usr/bin/env python3
"""Gives exported xcresult attachments their test-assigned names.

`xcresulttool export attachments` writes files named by attachment id and a
manifest describing them. Without this step the repository fills up with names
like `1_2_A1B2C3.png`, which say nothing about what they show.

Deliberately forgiving: the manifest schema has changed between Xcode
releases, so anything that cannot be matched keeps its original name rather
than being dropped.
"""
import json
import os
import re
import shutil
import sys

SAFE = re.compile(r"[^A-Za-z0-9._-]+")


def sanitize(name: str) -> str:
    name = SAFE.sub("-", name.strip()).strip("-")
    return name or "screenshot"


EXPORT_SUFFIX = re.compile(r"_\d+_[0-9A-Fa-f-]{36}(?=\.png$)")


def strip_export_suffix(name: str) -> str | None:
    """`01-Heute_0_E7FD6CDA-….png` -> `01-Heute.png`.

    The modern exporter already puts the attachment's name in the file name and
    appends an index and a uuid. Without this the repository fills up with
    unreadable names even though the information is right there.
    """
    stripped = EXPORT_SUFFIX.sub("", name)
    return stripped if stripped != name else None


def collect_renames(node, out):
    """Walks any JSON shape looking for {exported file name, readable name}."""
    if isinstance(node, dict):
        exported = None
        readable = None
        for key, value in node.items():
            if not isinstance(value, str):
                continue
            lowered = key.lower()
            if "exportedfilename" in lowered or lowered in {"filename", "file"}:
                exported = value
            elif "suggestedhumanreadablename" in lowered or lowered in {"name", "attachmentname"}:
                readable = value
        if exported and readable:
            out[exported] = readable
        for value in node.values():
            collect_renames(value, out)
    elif isinstance(node, list):
        for value in node:
            collect_renames(value, out)


def main() -> int:
    directory = sys.argv[1] if len(sys.argv) > 1 else "Screenshots"
    if not os.path.isdir(directory):
        print(f"{directory} does not exist", file=sys.stderr)
        return 1

    renames = {}
    manifests = []
    for root, _dirs, files in os.walk(directory):
        for name in files:
            if name.lower().endswith(".json"):
                path = os.path.join(root, name)
                manifests.append(path)
                try:
                    with open(path) as handle:
                        collect_renames(json.load(handle), renames)
                except (json.JSONDecodeError, OSError) as error:
                    print(f"ignoring {path}: {error}", file=sys.stderr)

    # Flatten: attachments may sit in per-test subdirectories.
    for root, _dirs, files in os.walk(directory, topdown=False):
        if root == directory:
            continue
        for name in files:
            source = os.path.join(root, name)
            target = os.path.join(directory, name)
            if not os.path.exists(target):
                shutil.move(source, target)
        try:
            os.rmdir(root)
        except OSError:
            pass

    kept = 0
    for name in sorted(os.listdir(directory)):
        path = os.path.join(directory, name)
        if not os.path.isfile(path):
            continue
        if not name.lower().endswith(".png"):
            os.remove(path)          # manifests and non-image attachments
            continue
        readable = renames.get(name) or strip_export_suffix(name)
        if readable:
            new_name = sanitize(readable)
            if not new_name.lower().endswith(".png"):
                new_name += ".png"
            new_path = os.path.join(directory, new_name)
            if new_path != path:
                os.replace(path, new_path)
            print(f"{name} -> {new_name}")
        else:
            print(f"{name} (no manifest entry, keeping name)")
        kept += 1

    print(f"{kept} screenshot(s) in {directory}")
    return 0 if kept else 1


if __name__ == "__main__":
    sys.exit(main())
