import numpy as np
import pytest

from doodledex_ml.calibration import (
    CONFIDENCE_BINS,
    STROKE_BUCKET_STARTS,
    confidence_bin,
    expected_calibration_error,
    fit_confidence_table,
    monotone,
    stroke_bucket,
)


def test_stroke_buckets_follow_their_starts() -> None:
    strokes = np.array([1, 2, 5, 6, 7, 8, 10, 11, 60])
    assert stroke_bucket(strokes).tolist() == [0, 1, 4, 5, 5, 6, 6, 7, 7]


def test_a_score_of_one_stays_in_the_last_bin() -> None:
    assert confidence_bin(np.array([0.0, 0.099, 0.1, 1.0])).tolist() == [0, 0, 1, 9]


def test_monotone_pools_violators_by_weight() -> None:
    result = monotone(np.array([0.1, 0.5, 0.3]), np.array([1.0, 1.0, 3.0]))
    assert result.tolist() == pytest.approx([0.1, 0.35, 0.35])


def test_monotone_leaves_a_sorted_row_alone() -> None:
    values = np.array([0.1, 0.2, 0.9])
    assert monotone(values, np.ones(3)).tolist() == pytest.approx(values.tolist())


def test_table_learns_that_early_scores_are_worth_less() -> None:
    generator = np.random.default_rng(3)
    count = 40_000
    confidence = generator.uniform(0.0, 1.0, count)
    strokes = generator.integers(1, 12, count)
    # One-stroke scores are right half as often as they claim. Later strokes are honest.
    truth = np.where(strokes == 1, confidence * 0.5, confidence)
    correct = generator.uniform(0.0, 1.0, count) < truth
    table = fit_confidence_table(confidence, correct, strokes)

    assert table.probabilities.shape == (len(STROKE_BUCKET_STARTS), CONFIDENCE_BINS)
    assert np.all(np.diff(table.probabilities, axis=1) >= 0)
    high = np.array([0.95])
    assert table.lookup(high, np.array([1]))[0] == pytest.approx(0.475, abs=0.05)
    assert table.lookup(high, np.array([6]))[0] == pytest.approx(0.95, abs=0.05)


def test_table_lowers_calibration_error_on_new_data() -> None:
    generator = np.random.default_rng(4)

    def sample(count: int) -> tuple[np.ndarray, np.ndarray]:
        confidence = generator.uniform(0.0, 1.0, count)
        return confidence, generator.uniform(0.0, 1.0, count) < confidence**3

    strokes = np.ones(20_000, dtype=int)
    table = fit_confidence_table(*sample(20_000), strokes)
    confidence, correct = sample(20_000)
    raw = expected_calibration_error(confidence, correct)
    calibrated = expected_calibration_error(table.lookup(confidence, strokes), correct)
    assert calibrated < raw / 5


def test_a_perfectly_stated_probability_has_no_error() -> None:
    probability = np.array([0.25] * 4)
    correct = np.array([True, False, False, False])
    assert expected_calibration_error(probability, correct) == pytest.approx(0.0)
