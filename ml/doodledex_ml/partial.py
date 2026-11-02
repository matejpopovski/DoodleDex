"""Measure accuracy on sketches in progress, and fit the app's confidence table.

The app predicts after every stroke, so held-out raw strokes are replayed the same way: each stroke
prefix goes through the full pipeline, including re-framing the partial drawing, exactly as on the
phone. The calibration split fits the table and picks the sticker threshold, and only the stroke
test split is reported. That split is also used to check the pipeline end to end, because a finished
drawing can be classified both from Google's bitmap and from this project's own rendering.

Usage: python -m doodledex_ml.partial [--per-class 500] [--device mps]
"""

import argparse
import json
from concurrent.futures import ProcessPoolExecutor

import numpy as np
import torch

from doodledex_ml.calibration import expected_calibration_error, fit_confidence_table
from doodledex_ml.classes import CLASSES
from doodledex_ml.data import DATA_DIR, REPO_ROOT, SPLITS, STROKE_TEST_RANGE, iter_raw, load_bitmaps
from doodledex_ml.evaluate import load_network, probabilities
from doodledex_ml.pipeline import Stroke, preprocess

PREFIX_LIMIT = 24
INK_BINS = np.linspace(0.0, 1.0, 11)
THRESHOLDS = (0.5, 0.6, 0.7, 0.75, 0.8, 0.85, 0.9, 0.95)
TARGET_STICKER_PRECISION = 0.9
APP_RESOURCES = REPO_ROOT / "DoodleDex" / "Resources"


def _ink(stroke: Stroke) -> float:
    points = np.asarray(stroke, dtype=np.float64)
    return float(np.sqrt((np.diff(points, axis=0) ** 2).sum(axis=1)).sum())


def render_class(job: tuple[int, int, int]) -> dict[str, np.ndarray]:
    """Render every stroke prefix of a class's drawings, up to PREFIX_LIMIT per drawing."""
    label, start, stop = job
    images, rows = [], []
    for drawing, record in enumerate(iter_raw(CLASSES[label], start, stop)):
        strokes = record["strokes"]
        lengths = np.array([_ink(stroke) for stroke in strokes])
        total_ink = max(lengths.sum(), 1e-9)
        count = len(strokes)
        # A very long drawing keeps its first prefixes and its finished form.
        prefixes = [*range(1, min(count, PREFIX_LIMIT) + 1)]
        if prefixes[-1] != count:
            prefixes.append(count)
        for done in prefixes:
            images.append(preprocess(strokes[:done]))
            rows.append(
                (
                    label * 100_000 + drawing,
                    label,
                    done,
                    count,
                    float(lengths[:done].sum() / total_ink),
                    record["recognized"],
                    drawing,
                )
            )
    table = np.array(rows, dtype=np.float64)
    return {
        "images": np.stack(images),
        "drawing": table[:, 0].astype(np.int64),
        "label": table[:, 1].astype(np.int64),
        "done": table[:, 2].astype(np.int64),
        "count": table[:, 3].astype(np.int64),
        "ink": table[:, 4],
        "recognized": table[:, 5].astype(bool),
        "index": table[:, 6].astype(np.int64) + start,
    }


def rendered_split(name: str, start: int, stop: int, workers: int) -> dict[str, np.ndarray]:
    cache = DATA_DIR / "cache" / f"prefixes_{name}_{start}_{stop}.npz"
    if cache.exists():
        with np.load(cache) as stored:
            return dict(stored)
    cache.parent.mkdir(exist_ok=True)
    with ProcessPoolExecutor(max_workers=workers) as pool:
        parts = list(pool.map(render_class, [(i, start, stop) for i in range(len(CLASSES))]))
    merged = {key: np.concatenate([part[key] for part in parts]) for key in parts[0]}
    np.savez(cache, **merged)
    return merged


def score(split: dict[str, np.ndarray], network, device: torch.device) -> dict[str, np.ndarray]:
    probs = probabilities(network, split["images"], device)
    ranked = np.argsort(-probs, axis=1)[:, :5]
    return {
        "confidence": np.take_along_axis(probs, ranked[:, :1], axis=1).ravel(),
        "top1": ranked[:, 0] == split["label"],
        "top5": (ranked == split["label"][:, np.newaxis]).any(axis=1),
        "prediction": ranked[:, 0],
    }


def first_firing(split, scored, calibrated, threshold: float) -> dict:
    """What the sticker offer does: it fires at the first prefix whose probability clears the bar.

    Picking the first of several looks is a selection effect, so precision here can be well under
    the per-prefix probability. That is why the threshold is chosen on this metric.
    """
    order = np.lexsort((split["done"], split["drawing"]))
    drawings = split["drawing"][order]
    above = calibrated[order] >= threshold
    fired = np.flatnonzero(above)
    first_row = fired[np.unique(drawings[fired], return_index=True)[1]]
    picks = order[first_row]
    drawing_count = np.unique(split["drawing"]).size
    return {
        "threshold": threshold,
        "coverage": round(first_row.size / drawing_count, 4),
        "precision": round(float(scored["top1"][picks].mean()), 4) if picks.size else None,
        "mean_ink_used": round(float(split["ink"][picks].mean()), 4) if picks.size else None,
        "mean_strokes_used": round(float(split["done"][picks].mean()), 3) if picks.size else None,
    }


def stable_point(split, scored) -> dict:
    """Fraction of ink at which the guess turns correct and stays correct to the end."""
    order = np.lexsort((split["done"], split["drawing"]))
    drawings = split["drawing"][order]
    correct = scored["top1"][order]
    ink = split["ink"][order]
    results = []
    for rows in np.split(np.arange(order.size), np.flatnonzero(np.diff(drawings)) + 1):
        if not correct[rows[-1]]:
            continue
        wrong = rows[~correct[rows]]
        settled = rows[0] if wrong.size == 0 else wrong[-1] + 1
        results.append(ink[settled])
    return {
        "drawings_correct_when_finished": len(results),
        "median_ink_to_settle": round(float(np.median(results)), 4),
        "p90_ink_to_settle": round(float(np.percentile(results, 90)), 4),
    }


def by_strokes(split, scored) -> list[dict]:
    rows = []
    for done in range(1, 13):
        selected = split["done"] == done
        finished = split["done"] == split["count"]
        rows.append(
            {
                "strokes": done,
                "prefixes": int(selected.sum()),
                "top1": round(float(scored["top1"][selected].mean()), 4),
                "top5": round(float(scored["top5"][selected].mean()), 4),
                "top1_finished_drawings_with_this_many": round(
                    float(scored["top1"][selected & finished].mean()), 4
                ),
                "mean_raw_confidence": round(float(scored["confidence"][selected].mean()), 4),
            }
        )
    return rows


def by_ink(split, scored) -> list[dict]:
    rows = []
    bins = np.minimum(np.digitize(split["ink"], INK_BINS) - 1, len(INK_BINS) - 2)
    for index in range(len(INK_BINS) - 1):
        selected = bins == index
        rows.append(
            {
                "ink_from": round(float(INK_BINS[index]), 1),
                "ink_to": round(float(INK_BINS[index + 1]), 1),
                "prefixes": int(selected.sum()),
                "top1": round(float(scored["top1"][selected].mean()), 4),
                "top5": round(float(scored["top5"][selected].mean()), 4),
            }
        )
    return rows


def pipeline_gap(split, scored, network, device: torch.device) -> dict:
    """Same drawings, same network: Google's bitmaps against this project's rendering of them."""
    finished = split["done"] == split["count"]
    images = split["images"][finished]
    labels = split["label"][finished]
    indices = split["index"][finished]
    published = np.stack(
        [
            load_bitmaps(CLASSES[label], index, index + 1)[0]
            for label, index in zip(labels, indices, strict=True)
        ]
    )
    published_top1 = probabilities(network, published, device).argmax(1) == labels
    ours_top1 = scored["top1"][finished]
    recognized = split["recognized"][finished]
    error = np.abs(images.astype(np.int16) - published.astype(np.int16)).mean(axis=(1, 2))
    return {
        "drawings": int(labels.size),
        "top1_on_published_bitmaps": round(float(published_top1.mean()), 4),
        "top1_on_pipeline_rendering": round(float(ours_top1.mean()), 4),
        "top1_on_published_bitmaps_recognized_only": round(
            float(published_top1[recognized].mean()), 4
        ),
        "share_recognized_by_the_game": round(float(recognized.mean()), 4),
        "guesses_that_changed": round(float((published_top1 != ours_top1).mean()), 4),
        "mean_abs_pixel_error": round(float(error.mean()), 3),
        "p99_abs_pixel_error": round(float(np.percentile(error, 99)), 3),
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--workers", type=int, default=6)
    parser.add_argument("--device", default="mps" if torch.backends.mps.is_available() else "cpu")
    args = parser.parse_args()
    device = torch.device(args.device)
    network = load_network(device)

    calibration = rendered_split("calibration", *SPLITS["calibration"], args.workers)
    test = rendered_split("test", *STROKE_TEST_RANGE, args.workers)
    calibration_scored = score(calibration, network, device)
    test_scored = score(test, network, device)

    table = fit_confidence_table(
        calibration_scored["confidence"], calibration_scored["top1"], calibration["done"]
    )
    calibrated = table.lookup(test_scored["confidence"], test["done"])
    calibrated_fit = table.lookup(calibration_scored["confidence"], calibration["done"])

    fitted_policy = [
        first_firing(calibration, calibration_scored, calibrated_fit, threshold)
        for threshold in THRESHOLDS
    ]
    threshold = next(
        row["threshold"]
        for row in fitted_policy
        if row["precision"] is not None and row["precision"] >= TARGET_STICKER_PRECISION
    )

    report = {
        "split": "stroke test",
        "index_range_per_class": list(STROKE_TEST_RANGE),
        "drawings": int(np.unique(test["drawing"]).size),
        "prefixes": int(test["done"].size),
        "pipeline_gap": pipeline_gap(test, test_scored, network, device),
        "accuracy_by_strokes_drawn": by_strokes(test, test_scored),
        "accuracy_by_share_of_ink": by_ink(test, test_scored),
        "settling": stable_point(test, test_scored),
        "calibration": {
            "ece_raw_softmax": round(
                expected_calibration_error(test_scored["confidence"], test_scored["top1"]), 4
            ),
            "ece_table": round(expected_calibration_error(calibrated, test_scored["top1"]), 4),
        },
        "sticker_threshold": threshold,
        "sticker_policy_on_test": [
            first_firing(test, test_scored, calibrated, value) for value in THRESHOLDS
        ],
        "sticker_policy_on_calibration": fitted_policy,
    }
    out = REPO_ROOT / "results" / "partial_sketch.json"
    out.write_text(json.dumps(report, indent=2) + "\n")

    APP_RESOURCES.mkdir(parents=True, exist_ok=True)
    expected = [row["top1"] for row in report["accuracy_by_strokes_drawn"]]
    shipped = {
        **table.to_json(),
        "sticker_threshold": threshold,
        "typical_accuracy_by_strokes": expected,
    }
    (APP_RESOURCES / "confidence_table.json").write_text(json.dumps(shipped, indent=2) + "\n")
    print(json.dumps({k: report[k] for k in ("pipeline_gap", "settling", "calibration")}, indent=2))
    print(f"threshold {threshold}, wrote {out}")


if __name__ == "__main__":
    main()
