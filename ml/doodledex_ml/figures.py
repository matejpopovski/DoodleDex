"""Draw the README figures from the JSON in results/.

Usage: python -m doodledex_ml.figures
"""

import json

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt

from doodledex_ml.data import REPO_ROOT

RESULTS = REPO_ROOT / "results"
SURFACE = "#fcfcfb"
INK = "#0b0b0b"
MUTED = "#52514e"
GRID = "#e6e5e0"
TOP1 = "#2a78d6"
TOP5 = "#eb6834"


def style(axes, title: str, xlabel: str, ylabel: str) -> None:
    axes.set_facecolor(SURFACE)
    axes.set_title(title, loc="left", fontsize=12, fontweight="semibold", color=INK, pad=12)
    axes.set_xlabel(xlabel, color=MUTED, fontsize=10)
    axes.set_ylabel(ylabel, color=MUTED, fontsize=10)
    axes.grid(axis="y", color=GRID, linewidth=0.8)
    axes.set_axisbelow(True)
    axes.tick_params(colors=MUTED, length=0, labelsize=9)
    for side in ("top", "right", "left"):
        axes.spines[side].set_visible(False)
    axes.spines["bottom"].set_color(GRID)


def partial_figure() -> None:
    report = json.loads((RESULTS / "partial_sketch.json").read_text())
    rows = report["accuracy_by_share_of_ink"]
    centres = [(row["ink_from"] + row["ink_to"]) * 50 for row in rows]
    top1 = [row["top1"] * 100 for row in rows]
    top5 = [row["top5"] * 100 for row in rows]

    figure, axes = plt.subplots(figsize=(7.4, 3.8), dpi=200, facecolor=SURFACE)
    style(
        axes,
        "Accuracy of a sketch in progress, by share of its final ink",
        "Share of the finished drawing's ink laid down (%)",
        "Accuracy on held-out drawings (%)",
    )
    axes.plot(centres, top5, color=TOP5, linewidth=2, marker="o", markersize=5, label="Top-5")
    axes.plot(centres, top1, color=TOP1, linewidth=2, marker="o", markersize=5, label="Top-1")
    axes.annotate(
        f"Top-5 {top5[-1]:.1f}",
        (centres[-1], top5[-1]),
        xytext=(-4, 8),
        textcoords="offset points",
        ha="right",
        color=INK,
        fontsize=9,
    )
    axes.annotate(
        f"Top-1 {top1[-1]:.1f}",
        (centres[-1], top1[-1]),
        xytext=(4, -26),
        textcoords="offset points",
        ha="center",
        color=INK,
        fontsize=9,
    )
    axes.set_xlim(0, 100)
    axes.set_ylim(0, 100)
    axes.legend(frameon=False, loc="lower right", fontsize=9, labelcolor=INK)
    figure.tight_layout()
    figure.savefig(RESULTS / "partial_accuracy.png", facecolor=SURFACE)
    plt.close(figure)


def main() -> None:
    partial_figure()
    print(f"wrote {RESULTS / 'partial_accuracy.png'}")


if __name__ == "__main__":
    main()
