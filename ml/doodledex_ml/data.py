"""Fetch a capped prefix of Quick, Draw! for each class and define the splits.

Source: Google's Quick, Draw! dataset, CC BY 4.0
(https://github.com/googlecreativelab/quickdraw-dataset).

Three facts about the published files shape this module:

- Category files appear shuffled: timestamps and countries sampled at five offsets through
  `simplified/cat.ndjson` span the same range at every offset. Reading only the first records keeps
  disk use bounded, on the assumption that the other classes are shuffled the same way.
- Record i of `numpy_bitmap/<c>.npy` and line i of `raw/<c>.ndjson` are the same drawing, which lets
  a held-out bitmap be paired with the strokes that produced it. `verify_dataset` measures this.
- The `.npy` bitmaps include drawings the game's own recognizer rejected (`recognized: false`).
  Test accuracy here includes them.

Usage: python -m doodledex_ml.data [--per-class 20000] [--strokes-per-class 1000]
"""

import argparse
import json
import time
import urllib.parse
import urllib.request
from collections.abc import Iterator
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

import numpy as np

from doodledex_ml.classes import CLASSES

BASE_URL = "https://storage.googleapis.com/quickdraw_dataset/full"
RECORD_BYTES = 28 * 28
REPO_ROOT = Path(__file__).resolve().parents[2]
DATA_DIR = REPO_ROOT / "data"

# Half-open index ranges into each class's records. Calibration comes first because it needs
# strokes, and strokes are only downloaded for the head of each file.
SPLITS = {
    "calibration": (0, 500),
    "test": (500, 3000),
    "val": (3000, 4000),
    "train": (4000, 20000),
}
STROKE_TEST_RANGE = (500, 1000)


def slug(category: str) -> str:
    return category.replace(" ", "_")


def _url(kind: str, category: str, extension: str) -> str:
    return f"{BASE_URL}/{kind}/{urllib.parse.quote(category)}.{extension}"


def _with_retries(fetch, attempts: int = 5):
    for attempt in range(attempts):
        try:
            return fetch()
        except OSError:
            if attempt == attempts - 1:
                raise
            time.sleep(2**attempt)


def fetch_bitmaps(category: str, cap: int, out_dir: Path = DATA_DIR / "bitmaps") -> int:
    """Stream the first `cap` records of a class. Returns the class's published record count."""
    target = out_dir / f"{slug(category)}.bin"

    def fetch() -> int:
        with urllib.request.urlopen(_url("numpy_bitmap", category, "npy"), timeout=60) as response:
            version = np.lib.format.read_magic(response)
            shape, _, dtype = np.lib.format._read_array_header(response, version)
            if dtype != np.uint8 or shape[1] != RECORD_BYTES:
                raise ValueError(f"unexpected layout for {category}: {shape} {dtype}")
            wanted = min(cap, shape[0]) * RECORD_BYTES
            if not target.exists() or target.stat().st_size != wanted:
                blob = response.read(wanted)
                if len(blob) != wanted:
                    raise OSError(f"short read for {category}")
                target.write_bytes(blob)
            return shape[0]

    return _with_retries(fetch)


def fetch_strokes(category: str, cap: int, out_dir: Path = DATA_DIR / "raw") -> None:
    """Keep the first `cap` raw drawings, without timestamps, which the pipeline never reads."""
    target = out_dir / f"{slug(category)}.ndjson"
    if target.exists() and sum(1 for _ in target.open()) == cap:
        return

    def fetch() -> None:
        rows = []
        with urllib.request.urlopen(_url("raw", category, "ndjson"), timeout=60) as response:
            for line in response:
                record = json.loads(line)
                rows.append(
                    json.dumps(
                        {
                            "key_id": record["key_id"],
                            "recognized": record["recognized"],
                            "strokes": [stroke[:2] for stroke in record["drawing"]],
                        },
                        separators=(",", ":"),
                    )
                )
                if len(rows) == cap:
                    break
        target.write_text("\n".join(rows) + "\n")

    _with_retries(fetch)


def load_bitmaps(category: str, start: int, stop: int) -> np.ndarray:
    """Read a contiguous slice as an (n, 28, 28) uint8 array without loading the whole file."""
    data = np.memmap(DATA_DIR / "bitmaps" / f"{slug(category)}.bin", dtype=np.uint8, mode="r")
    return np.array(data[start * RECORD_BYTES : stop * RECORD_BYTES]).reshape(-1, 28, 28)


def iter_raw(category: str, start: int, stop: int) -> Iterator[dict]:
    """Yield raw drawings as {"key_id", "recognized", "strokes": [[x, y] pairs per stroke]}."""
    with (DATA_DIR / "raw" / f"{slug(category)}.ndjson").open() as handle:
        for index, line in enumerate(handle):
            if index >= stop:
                return
            if index >= start:
                record = json.loads(line)
                record["strokes"] = [list(zip(xs, ys, strict=True)) for xs, ys in record["strokes"]]
                yield record


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--per-class", type=int, default=SPLITS["train"][1])
    parser.add_argument("--strokes-per-class", type=int, default=STROKE_TEST_RANGE[1])
    parser.add_argument("--workers", type=int, default=8)
    args = parser.parse_args()

    (DATA_DIR / "bitmaps").mkdir(parents=True, exist_ok=True)
    (DATA_DIR / "raw").mkdir(parents=True, exist_ok=True)

    def fetch_class(category: str) -> tuple[str, int]:
        published = fetch_bitmaps(category, args.per_class)
        fetch_strokes(category, args.strokes_per_class)
        print(f"{category}: {published} published", flush=True)
        return category, published

    with ThreadPoolExecutor(max_workers=args.workers) as pool:
        counts = dict(pool.map(fetch_class, CLASSES))

    manifest = {
        "source": "Google Quick, Draw! dataset, CC BY 4.0",
        "url": "https://github.com/googlecreativelab/quickdraw-dataset",
        "bitmap_records_per_class": args.per_class,
        "raw_drawings_per_class": args.strokes_per_class,
        "splits": {name: list(bounds) for name, bounds in SPLITS.items()},
        "stroke_test_range": list(STROKE_TEST_RANGE),
        "published_records": counts,
    }
    out = REPO_ROOT / "results" / "dataset_manifest.json"
    out.write_text(json.dumps(manifest, indent=2) + "\n")
    print(f"{len(counts)} classes, wrote {out}")


if __name__ == "__main__":
    main()
