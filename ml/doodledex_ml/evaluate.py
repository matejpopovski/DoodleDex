"""Score the best checkpoint on the held-out test bitmaps.

Usage: python -m doodledex_ml.evaluate [--device mps]
"""

import argparse
import json

import numpy as np
import torch

from doodledex_ml.classes import CLASSES
from doodledex_ml.data import REPO_ROOT, SPLITS
from doodledex_ml.model import DoodleNet
from doodledex_ml.train import CHECKPOINTS, load_split


def load_network(device: torch.device) -> DoodleNet:
    network = DoodleNet(len(CLASSES))
    state = torch.load(CHECKPOINTS / "best.pt", map_location="cpu", weights_only=True)
    network.load_state_dict(state)
    return network.to(device).eval()


@torch.no_grad()
def probabilities(
    network: DoodleNet, images: np.ndarray, device: torch.device, batch: int = 4096
) -> np.ndarray:
    """Softmax outputs for (n, 28, 28) uint8 images, returned on the CPU."""
    outputs = []
    for start in range(0, images.shape[0], batch):
        chunk = torch.from_numpy(images[start : start + batch]).to(device)
        logits = network(chunk.unsqueeze(1).float() / 255.0)
        outputs.append(torch.softmax(logits, dim=1).cpu().numpy())
    return np.concatenate(outputs)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--device", default="mps" if torch.backends.mps.is_available() else "cpu")
    args = parser.parse_args()
    device = torch.device(args.device)

    network = load_network(device)
    images, labels = load_split("test")
    labels = labels.numpy()
    scores = probabilities(network, images.numpy(), device)

    ranked = np.argsort(-scores, axis=1)[:, :5]
    top1 = ranked[:, 0] == labels
    top5 = (ranked == labels[:, np.newaxis]).any(axis=1)

    per_class = [
        {"category": name, "top1": round(float(top1[labels == index].mean()), 4)}
        for index, name in enumerate(CLASSES)
    ]
    per_class.sort(key=lambda row: row["top1"])

    confusion = np.zeros((len(CLASSES), len(CLASSES)), dtype=np.int64)
    np.add.at(confusion, (labels, ranked[:, 0]), 1)
    np.fill_diagonal(confusion, 0)
    worst = np.argsort(-confusion, axis=None)[:15]
    pairs = [
        {
            "true": CLASSES[row],
            "predicted": CLASSES[column],
            "rate": round(float(confusion[row, column] / (labels == row).sum()), 4),
        }
        for row, column in zip(*np.unravel_index(worst, confusion.shape), strict=True)
    ]

    report = {
        "split": "test",
        "index_range_per_class": list(SPLITS["test"]),
        "images": int(labels.size),
        "classes": len(CLASSES),
        "parameters": sum(parameter.numel() for parameter in network.parameters()),
        "top1": round(float(top1.mean()), 4),
        "top5": round(float(top5.mean()), 4),
        "hardest_classes": per_class[:10],
        "easiest_classes": per_class[-10:],
        "top_confusions": pairs,
    }
    out = REPO_ROOT / "results" / "test_metrics.json"
    out.write_text(json.dumps(report, indent=2) + "\n")
    print(f"top-1 {report['top1']} top-5 {report['top5']} on {report['images']} images")


if __name__ == "__main__":
    main()
