import json
from itertools import pairwise

import numpy as np

from doodledex_ml.calibration import CONFIDENCE_BINS, STROKE_BUCKET_STARTS
from doodledex_ml.classes import CHAPTERS, CLASSES
from doodledex_ml.data import REPO_ROOT, SPLITS, STROKE_TEST_RANGE, _url, slug

RESOURCES = REPO_ROOT / "DoodleDex" / "Resources"


def test_there_are_a_hundred_distinct_classes() -> None:
    assert len(CLASSES) == 100
    assert len(set(CLASSES)) == 100


def test_splits_partition_the_downloaded_records_without_overlap() -> None:
    ranges = sorted(SPLITS.values())
    assert ranges[0][0] == 0
    for (_, stop), (start, _) in pairwise(ranges):
        assert stop == start


def test_stroke_test_range_sits_inside_the_test_split() -> None:
    assert SPLITS["test"][0] <= STROKE_TEST_RANGE[0]
    assert STROKE_TEST_RANGE[1] <= SPLITS["test"][1]


def test_download_urls_escape_multi_word_categories() -> None:
    url = _url("numpy_bitmap", "hot air balloon", "npy")
    assert url.endswith("/numpy_bitmap/hot%20air%20balloon.npy")
    assert slug("hot air balloon") == "hot_air_balloon"


def test_shipped_catalog_is_the_class_list() -> None:
    catalog = json.loads((RESOURCES / "catalog.json").read_text())
    assert {c["name"]: set(c["categories"]) for c in catalog["chapters"]} == {
        name: set(members) for name, members in CHAPTERS.items()
    }


def test_shipped_confidence_table_has_the_expected_shape_and_order() -> None:
    table = json.loads((RESOURCES / "confidence_table.json").read_text())
    probabilities = np.array(table["probabilities"])
    assert table["stroke_bucket_starts"] == list(STROKE_BUCKET_STARTS)
    assert probabilities.shape == (len(STROKE_BUCKET_STARTS), CONFIDENCE_BINS)
    assert np.all(np.diff(probabilities, axis=1) >= 0)
    assert 0.0 < table["sticker_threshold"] < 1.0
