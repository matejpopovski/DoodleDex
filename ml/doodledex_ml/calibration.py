"""Turn a raw softmax score into the probability the app actually shows.

Softmax scores from a network trained on finished drawings mean little on a half-finished one, and
the app has one more signal than the score: how many strokes it has seen. The table here gives the
empirical P(top guess is right | strokes so far, raw score bin), fitted on a split the network never
trained on. It is a lookup rather than a parametric fit so that the Swift side can reproduce it
exactly with a few lines of code.
"""

from dataclasses import dataclass

import numpy as np

STROKE_BUCKET_STARTS = (1, 2, 3, 4, 5, 6, 8, 11)
CONFIDENCE_BINS = 10


def stroke_bucket(strokes: np.ndarray) -> np.ndarray:
    return np.searchsorted(np.array(STROKE_BUCKET_STARTS), strokes, side="right") - 1


def confidence_bin(confidence: np.ndarray) -> np.ndarray:
    return np.minimum((confidence * CONFIDENCE_BINS).astype(int), CONFIDENCE_BINS - 1)


def monotone(values: np.ndarray, weights: np.ndarray) -> np.ndarray:
    """Pool-adjacent-violators: the closest non-decreasing fit, weighted by bin population.

    A higher raw score should never display as a lower chance, even where a sparse bin says so.
    """
    blocks: list[list[float]] = []
    for value, weight in zip(values, weights, strict=True):
        blocks.append([float(value), float(weight), 1.0])
        while len(blocks) > 1 and blocks[-2][0] > blocks[-1][0]:
            value_b, weight_b, width_b = blocks.pop()
            value_a, weight_a, width_a = blocks.pop()
            total = weight_a + weight_b
            blocks.append(
                [(value_a * weight_a + value_b * weight_b) / total, total, width_a + width_b]
            )
    return np.concatenate([np.full(int(block[2]), block[0]) for block in blocks])


@dataclass(frozen=True)
class ConfidenceTable:
    probabilities: np.ndarray  # shape (stroke buckets, confidence bins)

    def lookup(self, confidence: np.ndarray, strokes: np.ndarray) -> np.ndarray:
        return self.probabilities[stroke_bucket(strokes), confidence_bin(confidence)]

    def to_json(self) -> dict:
        return {
            "stroke_bucket_starts": list(STROKE_BUCKET_STARTS),
            "confidence_bins": CONFIDENCE_BINS,
            "probabilities": [[round(float(v), 4) for v in row] for row in self.probabilities],
        }


def fit_confidence_table(
    confidence: np.ndarray, correct: np.ndarray, strokes: np.ndarray
) -> ConfidenceTable:
    table = np.zeros((len(STROKE_BUCKET_STARTS), CONFIDENCE_BINS))
    buckets = stroke_bucket(strokes)
    bins = confidence_bin(confidence)
    for bucket in range(table.shape[0]):
        hits = np.zeros(CONFIDENCE_BINS)
        totals = np.zeros(CONFIDENCE_BINS)
        selected = buckets == bucket
        np.add.at(hits, bins[selected], correct[selected].astype(float))
        np.add.at(totals, bins[selected], 1.0)
        # One pseudo-observation at the bin centre keeps empty bins defined and sparse ones modest.
        centres = (np.arange(CONFIDENCE_BINS) + 0.5) / CONFIDENCE_BINS
        table[bucket] = monotone((hits + centres) / (totals + 1.0), totals + 1.0)
    return ConfidenceTable(table)


def expected_calibration_error(
    probability: np.ndarray, correct: np.ndarray, bins: int = 10
) -> float:
    """Population-weighted gap between stated probability and observed accuracy."""
    index = np.minimum((probability * bins).astype(int), bins - 1)
    error = 0.0
    for value in range(bins):
        selected = index == value
        if selected.any():
            gap = abs(probability[selected].mean() - correct[selected].mean())
            error += selected.mean() * gap
    return float(error)
