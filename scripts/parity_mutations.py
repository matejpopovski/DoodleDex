#!/usr/bin/env python3
"""Break the Swift pipeline on purpose and count how many parity fixtures notice.

A test that cannot fail proves nothing. Each mutation is a small, plausible porting mistake, applied
to a temporary copy of the package, so the working tree is never touched.

Usage: python3 scripts/parity_mutations.py
"""

import json
import re
import shutil
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = "Sources/DoodleCore/Preprocessor.swift"

MUTATIONS = {
    "line width 16 becomes 15": (
        "public var lineDiameter = 16.0",
        "public var lineDiameter = 15.0",
    ),
    "4x supersampling instead of 8x": ("public var supersample = 8", "public var supersample = 4"),
    "RDP epsilon 2.0 becomes 2.5": ("public var rdpEpsilon = 2.0", "public var rdpEpsilon = 2.5"),
    "scale to 256 instead of 255": (
        "public var scaledExtent = 255.0",
        "public var scaledExtent = 256.0",
    ),
    "no rounding to integers": ("(value + 0.5).rounded(.down)", "value"),
    "drawing not centred": ("let offsetY = (config.canvas - maxY) / 2.0", "let offsetY = 0.0"),
    "strokes union instead of composite": (
        "1.0 - (1.0 - image[pixel]) * (1.0 - Double(counts[pixel]) / subpixels)",
        "Swift.max(image[pixel], Double(counts[pixel]) / subpixels)",
    ),
}


def failures(package: Path) -> set[str]:
    """Fixture ids that failed, or a marker if the mutated code did not even run."""
    run = subprocess.run(
        ["swift", "test", "--filter", "PipelineParityTests"],
        cwd=package,
        capture_output=True,
        text=True,
    )
    output = run.stdout + run.stderr
    if "Executed" not in output:
        raise RuntimeError(f"mutated package did not run:\n{output[-2000:]}")
    return set(re.findall(r"failed: \(.*? - (\S+)$", output, re.MULTILINE))


def main() -> None:
    fixtures = ROOT / "Packages/DoodleCore/Sources/ParityFixtures/Resources/pipeline_fixtures.json"
    total = len(json.loads(fixtures.read_text())["cases"])
    report = []
    with tempfile.TemporaryDirectory() as scratch:
        package = Path(scratch) / "DoodleCore"
        shutil.copytree(
            ROOT / "Packages/DoodleCore", package, ignore=shutil.ignore_patterns(".build")
        )
        original = (package / SOURCE).read_text()
        for name, (before, after) in MUTATIONS.items():
            if before not in original:
                raise ValueError(f"mutation no longer applies: {name}")
            (package / SOURCE).write_text(original.replace(before, after))
            caught = failures(package)
            report.append({"mutation": name, "fixtures_failed": len(caught), "of": total})
            print(report[-1], flush=True)
    (ROOT / "results/parity_mutations.json").write_text(json.dumps(report, indent=2) + "\n")


if __name__ == "__main__":
    main()
