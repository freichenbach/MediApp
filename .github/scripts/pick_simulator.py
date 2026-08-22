#!/usr/bin/env python3
"""Prints the UDID of the newest available iPhone simulator.

GitHub's macOS runner images change their simulator line-up between releases,
so pinning a device name ("iPhone 16") breaks the build every time Apple ships
a new one. Resolving one at run time does not.

Reads `xcrun simctl list devices available --json` on stdin.
"""
import json
import re
import sys


def runtime_version(runtime_id: str) -> tuple[int, ...]:
    """'com.apple.CoreSimulator.SimRuntime.iOS-18-2' -> (18, 2)"""
    match = re.search(r"iOS-([\d-]+)$", runtime_id)
    if not match:
        return ()
    return tuple(int(part) for part in match.group(1).split("-") if part.isdigit())


def main() -> int:
    devices = json.load(sys.stdin)["devices"]

    best = None
    for runtime_id, entries in devices.items():
        version = runtime_version(runtime_id)
        if not version:
            continue
        for device in entries:
            if not device.get("isAvailable"):
                continue
            if not device.get("name", "").startswith("iPhone"):
                continue
            key = (version, device["name"])
            if best is None or key > best[0]:
                best = (key, device)

    if best is None:
        print("no available iPhone simulator on this runner", file=sys.stderr)
        return 1

    version, device = best[0][0], best[1]
    print(f"{device['name']} (iOS {'.'.join(map(str, version))})", file=sys.stderr)
    print(device["udid"])
    return 0


if __name__ == "__main__":
    sys.exit(main())
