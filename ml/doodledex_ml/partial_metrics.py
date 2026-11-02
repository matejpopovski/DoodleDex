"""Summaries of a replayed stroke split. Rows are stroke prefixes, keyed by drawing."""

import numpy as np

INK_BINS = np.linspace(0.0, 1.0, 11)


def first_firing(split, scored, calibrated, threshold: float) -> dict:
    """What the sticker offer does: it fires at the first prefix whose probability clears the bar.

    Each drawing gets several looks and only the first one over the bar counts, so the calibrated
    per-prefix probability does not directly state how often an offered sticker is right. This
    measures that, and the threshold is chosen on it.
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


def _mean(values: np.ndarray) -> float | None:
    return round(float(values.mean()), 4) if values.size else None


def by_strokes(split, scored, limit: int = 12) -> list[dict]:
    rows = []
    for done in range(1, limit + 1):
        selected = split["done"] == done
        finished = split["done"] == split["count"]
        rows.append(
            {
                "strokes": done,
                "prefixes": int(selected.sum()),
                "top1": _mean(scored["top1"][selected]),
                "top5": _mean(scored["top5"][selected]),
                "top1_finished_drawings_with_this_many": _mean(scored["top1"][selected & finished]),
                "mean_raw_confidence": _mean(scored["confidence"][selected]),
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
                "top1": _mean(scored["top1"][selected]),
                "top5": _mean(scored["top5"][selected]),
            }
        )
    return rows
