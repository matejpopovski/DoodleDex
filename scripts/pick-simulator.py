#!/usr/bin/env python3
"""Print '<device type id> <runtime id>' for the newest iPhone on the newest usable iOS runtime.

Reads `simctl` rather than hard-coding a device, because the devices on a GitHub macos-latest runner
and on a developer's Mac are different and change with each image. Set DOODLEDEX_RUNTIME to a
substring such as iOS-17-5 to test on a specific runtime.
"""

import json
import os
import subprocess
import sys

MINIMUM = (17, 0)


def version(text: str) -> tuple[int, ...]:
    return tuple(int(part) for part in text.split("."))


def main() -> None:
    listing = json.loads(
        subprocess.run(
            ["xcrun", "simctl", "list", "--json", "runtimes"],
            check=True,
            capture_output=True,
            text=True,
        ).stdout
    )
    wanted = os.environ.get("DOODLEDEX_RUNTIME", "")
    runtimes = [
        runtime
        for runtime in listing["runtimes"]
        if runtime.get("platform") == "iOS"
        and runtime["isAvailable"]
        and version(runtime["version"]) >= MINIMUM
        and wanted in runtime["identifier"]
    ]
    if not runtimes:
        sys.exit(f"no available iOS runtime at or above {MINIMUM} matching '{wanted}'")
    runtime = max(runtimes, key=lambda item: version(item["version"]))
    iphones = [
        device
        for device in runtime["supportedDeviceTypes"]
        if device["productFamily"] == "iPhone" and "SE" not in device["name"]
    ]
    # simctl lists supported device types newest first.
    print(iphones[0]["identifier"], runtime["identifier"])


if __name__ == "__main__":
    main()
