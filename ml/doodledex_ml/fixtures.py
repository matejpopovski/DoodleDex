"""Write the vectors that hold the Swift pipeline to the Python one.

Cases are real raw human strokes from the held-out stroke range, partial sketches cut from them, the
same strokes moved into a phone-sized coordinate system, and hand-built edge cases. Every case
records the expected output of each stage, so a failure names the stage that diverged.

Usage: python -m doodledex_ml.fixtures
"""

import base64
import json
import struct
from dataclasses import asdict

from doodledex_ml.classes import CLASSES
from doodledex_ml.data import REPO_ROOT, STROKE_TEST_RANGE, iter_raw
from doodledex_ml.pipeline import DEFAULT_CONFIG, Stroke, preprocess, simplify

PIPELINE_FIXTURES = (
    REPO_ROOT / "Packages/DoodleCore/Sources/ParityFixtures/Resources/pipeline_fixtures.json"
)


def encode_strokes(strokes: list[Stroke]) -> tuple[list[int], str]:
    flat = [value for stroke in strokes for point in stroke for value in point]
    blob = struct.pack(f"<{len(flat)}d", *flat)
    return [len(stroke) for stroke in strokes], base64.b64encode(blob).decode()


def decode_strokes(counts: list[int], encoded: str) -> list[Stroke]:
    blob = base64.b64decode(encoded)
    flat = struct.unpack(f"<{len(blob) // 8}d", blob)
    strokes, cursor = [], 0
    for count in counts:
        pairs = flat[cursor : cursor + count * 2]
        strokes.append(list(zip(pairs[::2], pairs[1::2], strict=True)))
        cursor += count * 2
    return strokes


def build_case(case_id: str, kind: str, strokes: list[Stroke]) -> dict:
    counts, coordinates = encode_strokes(strokes)
    simplified_counts, simplified_coordinates = encode_strokes(simplify(strokes))
    return {
        "id": case_id,
        "kind": kind,
        "point_counts": counts,
        "coordinates": coordinates,
        "simplified_point_counts": simplified_counts,
        "simplified_coordinates": simplified_coordinates,
        "pixels": base64.b64encode(preprocess(strokes).tobytes()).decode(),
    }


def edge_cases() -> dict[str, list[Stroke]]:
    circle_like = [(10.0, 0.0), (20.0, 10.0), (10.0, 20.0), (0.0, 10.0), (10.0, 0.0)]
    return {
        "tap": [[(120.5, 87.25)]],
        "two_taps": [[(0.0, 0.0)], [(300.0, 400.0)]],
        "repeated_point": [[(5.0, 5.0), (5.0, 5.0), (5.0, 5.0)]],
        "horizontal_line": [[(10.0, 50.0), (390.0, 50.0)]],
        "vertical_line": [[(50.0, 10.0), (50.0, 390.0)]],
        "tiny_scribble": [[(1.0, 1.0), (1.5, 1.25), (1.25, 1.75)]],
        "closed_loop": [circle_like],
        "negative_coordinates": [[(-300.0, -20.0), (-100.5, 75.25), (40.0, -60.0)]],
        "crossing_strokes": [[(0.0, 0.0), (100.0, 100.0)], [(0.0, 100.0), (100.0, 0.0)]],
        "retraced_line": [[(0.0, 0.0), (100.0, 0.0), (0.0, 0.0), (100.0, 0.0)]],
    }


def main() -> None:
    cases = [build_case(name, "edge", strokes) for name, strokes in edge_cases().items()]
    start = STROKE_TEST_RANGE[0]
    for class_index, category in enumerate(CLASSES):
        slug = category.replace(" ", "_")
        record = next(iter_raw(category, start + 7, start + 8))
        strokes = record["strokes"]
        cases.append(build_case(f"{slug}_full", "dataset", strokes))
        if class_index % 2 == 0:
            prefix = strokes[: (len(strokes) + 1) // 2]
            cases.append(build_case(f"{slug}_partial", "partial", prefix))
        if class_index % 3 == 0:
            # A phone reports points in view coordinates: a different scale, origin and sign.
            moved = [[(x * 1.37 - 40.0, y * 1.37 + 73.0) for x, y in stroke] for stroke in strokes]
            cases.append(build_case(f"{slug}_canvas", "canvas", moved))

    PIPELINE_FIXTURES.parent.mkdir(parents=True, exist_ok=True)
    payload = {"schema": 1, "config": asdict(DEFAULT_CONFIG), "cases": cases}
    PIPELINE_FIXTURES.write_text(json.dumps(payload, separators=(",", ":")) + "\n")
    size = PIPELINE_FIXTURES.stat().st_size / 1024
    print(f"{len(cases)} cases, {size:.0f} KB, wrote {PIPELINE_FIXTURES}")


if __name__ == "__main__":
    main()
