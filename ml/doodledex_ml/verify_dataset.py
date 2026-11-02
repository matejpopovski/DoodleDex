"""Measure how closely `pipeline.preprocess` reproduces Google's published bitmaps.

Google documents the stroke simplification but not the 28x28 rendering, so the rendering parameters
are an inference. This module tests that inference: it runs raw human strokes through the pipeline
and compares each result with the bitmap published for the same drawing, over a grid of parameters.

Usage: python -m doodledex_ml.verify_dataset [--per-class 30]
"""

import argparse
import itertools
import json
from concurrent.futures import ProcessPoolExecutor
from dataclasses import asdict, replace

import numpy as np

from doodledex_ml.classes import CLASSES
from doodledex_ml.data import REPO_ROOT, STROKE_TEST_RANGE, iter_raw, load_bitmaps
from doodledex_ml.pipeline import DEFAULT_CONFIG, PipelineConfig, preprocess

GRID = {
    "line_diameter": [14.0, 16.0, 18.0],
    "padding": [12.0, 16.0, 20.0],
    "supersample": [4, 8, 16],
}


def _errors(job: tuple[str, int, PipelineConfig]) -> tuple[np.ndarray, np.ndarray]:
    category, count, config = job
    start = STROKE_TEST_RANGE[0]
    bitmaps = load_bitmaps(category, start, start + count).astype(np.int16)
    rendered = [
        preprocess(record["strokes"], config).astype(np.int16)
        for record in iter_raw(category, start, start + count)
    ]
    difference = np.abs(np.stack(rendered) - bitmaps)
    # A misaligned pair would show up as a same-class mismatch far larger than rendering noise.
    shuffled = np.abs(np.stack(rendered) - np.roll(bitmaps, 1, axis=0))
    return difference.mean(axis=(1, 2)), shuffled.mean(axis=(1, 2))


def score(config: PipelineConfig, per_class: int, pool: ProcessPoolExecutor) -> dict:
    jobs = [(category, per_class, config) for category in CLASSES]
    results = list(pool.map(_errors, jobs))
    matched = np.concatenate([r[0] for r in results])
    misaligned = np.concatenate([r[1] for r in results])
    return {
        "drawings": int(matched.size),
        "mean_abs_error": round(float(matched.mean()), 3),
        "p50_abs_error": round(float(np.percentile(matched, 50)), 3),
        "p99_abs_error": round(float(np.percentile(matched, 99)), 3),
        "max_abs_error": round(float(matched.max()), 3),
        "misaligned_mean_abs_error": round(float(misaligned.mean()), 3),
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--per-class", type=int, default=30)
    parser.add_argument("--workers", type=int, default=6)
    args = parser.parse_args()

    with ProcessPoolExecutor(max_workers=args.workers) as pool:
        grid = []
        for line_diameter, padding, supersample in itertools.product(*GRID.values()):
            config = replace(
                DEFAULT_CONFIG,
                line_diameter=line_diameter,
                padding=padding,
                supersample=supersample,
            )
            row = {
                "line_diameter": line_diameter,
                "padding": padding,
                "supersample": supersample,
                **score(config, args.per_class, pool),
            }
            print(row, flush=True)
            grid.append(row)

        variants = {
            "as_shipped": score(DEFAULT_CONFIG, args.per_class, pool),
            "rdp_distance_to_segment": score(
                replace(DEFAULT_CONFIG, rdp_to_segment=True), args.per_class, pool
            ),
            "no_resampling": score(
                replace(DEFAULT_CONFIG, resample_spacing=0.0), args.per_class, pool
            ),
        }

    best = min(grid, key=lambda row: row["mean_abs_error"])
    report = {
        "units": "mean absolute difference per pixel on the 0-255 scale, per drawing",
        "pipeline": asdict(DEFAULT_CONFIG),
        "best_in_grid": best,
        "variants": variants,
        "grid": grid,
    }
    out = REPO_ROOT / "results" / "dataset_parity.json"
    out.write_text(json.dumps(report, indent=2) + "\n")
    print(f"best: {best}\nwrote {out}")


if __name__ == "__main__":
    main()
