#!/usr/bin/env python3
"""Fallback extraction of screenshots from an .xcresult bundle.

Used only when `xcresulttool export attachments` is unavailable. Walks the
result graph with the legacy JSON API and exports every PNG payload it finds,
writing a manifest in the same shape the modern exporter produces so the
rename step works either way.
"""
import json
import os
import subprocess
import sys


def xcresult(path, object_id=None):
    command = ["xcrun", "xcresulttool", "get", "--legacy", "--format", "json", "--path", path]
    if object_id:
        command += ["--id", object_id]
    result = subprocess.run(command, capture_output=True, text=True)
    if result.returncode != 0:
        raise RuntimeError(result.stderr.strip())
    return json.loads(result.stdout)


def unwrap(node):
    """The legacy format wraps every scalar as {_value: ...}."""
    if isinstance(node, dict):
        if "_value" in node and len(node) <= 2:
            return node["_value"]
        return {key: unwrap(value) for key, value in node.items()}
    if isinstance(node, list):
        return [unwrap(value) for value in node]
    return node


def find_attachments(node, found):
    if isinstance(node, dict):
        name = node.get("name")
        ref = node.get("payloadRef")
        if isinstance(ref, dict) and "id" in ref:
            found.append((unwrap(name) if name else None, unwrap(ref["id"])))
        for value in node.values():
            find_attachments(value, found)
    elif isinstance(node, list):
        for value in node:
            find_attachments(value, found)


def main() -> int:
    if len(sys.argv) < 3:
        print("usage: export_attachments.py <result.xcresult> <output-dir>", file=sys.stderr)
        return 2
    bundle, out_dir = sys.argv[1], sys.argv[2]
    os.makedirs(out_dir, exist_ok=True)

    try:
        graph = unwrap(xcresult(bundle))
    except RuntimeError as error:
        print(f"cannot read {bundle}: {error}", file=sys.stderr)
        return 1

    # Pull in every referenced sub-object so attachments in test summaries are
    # reachable; one level of expansion is enough in practice.
    seen_ids, queue, attachments = set(), [graph], []
    while queue:
        node = queue.pop()
        find_attachments(node, attachments)
        refs = []

        def collect_refs(value):
            if isinstance(value, dict):
                if "id" in value and "targetType" in value:
                    refs.append(unwrap(value["id"]))
                for inner in value.values():
                    collect_refs(inner)
            elif isinstance(value, list):
                for inner in value:
                    collect_refs(inner)

        collect_refs(node)
        for ref in refs:
            if not isinstance(ref, str) or ref in seen_ids:
                continue
            seen_ids.add(ref)
            try:
                queue.append(unwrap(xcresult(bundle, ref)))
            except RuntimeError:
                continue

    manifest = []
    for index, (name, ref) in enumerate(attachments):
        if not isinstance(ref, str):
            continue
        filename = f"attachment_{index:02d}.png"
        target = os.path.join(out_dir, filename)
        result = subprocess.run(
            ["xcrun", "xcresulttool", "export", "--legacy", "--type", "file",
             "--path", bundle, "--id", ref, "--output-path", target],
            capture_output=True, text=True,
        )
        if result.returncode != 0 or not os.path.exists(target):
            continue
        with open(target, "rb") as handle:
            if handle.read(8) != b"\x89PNG\r\n\x1a\n":
                os.remove(target)      # attachment was not an image
                continue
        manifest.append({"exportedFileName": filename, "suggestedHumanReadableName": name or filename})

    with open(os.path.join(out_dir, "manifest.json"), "w") as handle:
        json.dump({"attachments": manifest}, handle, indent=2)

    print(f"exported {len(manifest)} attachment(s)")
    return 0 if manifest else 1


if __name__ == "__main__":
    sys.exit(main())
