import numpy as np
import pytest

from doodledex_ml.partial_metrics import by_ink, by_strokes, first_firing, stable_point


def replay() -> tuple[dict, dict]:
    """Two drawings: A settles at its second prefix, B is right, then wrong, then right."""
    split = {
        "drawing": np.array([0, 0, 0, 1, 1, 1]),
        "done": np.array([1, 2, 3, 1, 2, 3]),
        "count": np.array([3, 3, 3, 3, 3, 3]),
        "ink": np.array([0.2, 0.6, 1.0, 0.3, 0.5, 1.0]),
    }
    scored = {
        "top1": np.array([False, True, True, True, False, True]),
        "top5": np.array([True, True, True, True, True, True]),
        "confidence": np.array([0.2, 0.6, 0.9, 0.5, 0.4, 0.8]),
    }
    return split, scored


def test_first_firing_uses_only_the_first_prefix_over_the_bar() -> None:
    split, scored = replay()
    calibrated = np.array([0.1, 0.9, 0.9, 0.1, 0.1, 0.9])
    result = first_firing(split, scored, calibrated, 0.8)
    assert result["coverage"] == 1.0
    assert result["precision"] == 1.0
    assert result["mean_strokes_used"] == pytest.approx(2.5)
    assert result["mean_ink_used"] == pytest.approx(0.8)


def test_first_firing_reports_a_wrong_first_offer() -> None:
    split, scored = replay()
    calibrated = np.array([0.1, 0.1, 0.1, 0.1, 0.9, 0.9])
    result = first_firing(split, scored, calibrated, 0.8)
    assert result["coverage"] == 0.5
    assert result["precision"] == 0.0


def test_first_firing_survives_a_bar_nothing_clears() -> None:
    split, scored = replay()
    result = first_firing(split, scored, np.zeros(6), 0.8)
    assert result["coverage"] == 0.0
    assert result["precision"] is None


def test_first_firing_does_not_depend_on_row_order() -> None:
    split, scored = replay()
    calibrated = np.array([0.1, 0.9, 0.9, 0.1, 0.1, 0.9])
    order = np.array([5, 2, 0, 4, 1, 3])
    shuffled_split = {key: value[order] for key, value in split.items()}
    shuffled_scored = {key: value[order] for key, value in scored.items()}
    assert first_firing(shuffled_split, shuffled_scored, calibrated[order], 0.8) == first_firing(
        split, scored, calibrated, 0.8
    )


def test_settling_is_the_ink_after_the_last_wrong_guess() -> None:
    split, scored = replay()
    result = stable_point(split, scored)
    assert result["drawings_correct_when_finished"] == 2
    assert result["median_ink_to_settle"] == pytest.approx((0.6 + 1.0) / 2)


def test_by_strokes_counts_prefixes_at_each_length() -> None:
    split, scored = replay()
    rows = by_strokes(split, scored, limit=3)
    assert [row["prefixes"] for row in rows] == [2, 2, 2]
    assert rows[0]["top1"] == 0.5
    assert rows[2]["top1"] == 1.0


def test_by_ink_keeps_a_finished_drawing_in_the_last_bin() -> None:
    split, scored = replay()
    rows = by_ink(split, scored)
    assert rows[-1]["prefixes"] == 2
    assert sum(row["prefixes"] for row in rows) == 6
    assert rows[0]["top1"] is None
