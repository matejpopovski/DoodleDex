"""Train DoodleNet on the capped Quick, Draw! bitmaps.

Usage: python -m doodledex_ml.train [--epochs 10] [--device mps]

Each epoch writes a checkpoint, and rerunning resumes from the last one, so an interrupted run loses
at most one epoch. The best epoch by validation accuracy is kept separately. The test split is not
touched here.
"""

import argparse
import json
import time
from pathlib import Path

import numpy as np
import torch
from torch.nn import functional

from doodledex_ml.classes import CLASSES
from doodledex_ml.data import REPO_ROOT, SPLITS, load_bitmaps
from doodledex_ml.model import DoodleNet

CHECKPOINTS = REPO_ROOT / "checkpoints"


def load_split(name: str) -> tuple[torch.Tensor, torch.Tensor]:
    start, stop = SPLITS[name]
    images = np.concatenate([load_bitmaps(category, start, stop) for category in CLASSES])
    labels = np.repeat(np.arange(len(CLASSES)), stop - start)
    return torch.from_numpy(images), torch.from_numpy(labels)


def augment(images: torch.Tensor, generator: torch.Generator) -> torch.Tensor:
    """Small random affine warps, run on the training device so the GPU is not left waiting.

    The drawing is centred and scaled to fill its frame before rendering, so large shifts would
    describe images the app can never produce. Rotation and slight anisotropic scale model a
    player's hand, and a sub-2-pixel shift covers the rendering's rounding of the bounding box.
    """
    count = images.shape[0]
    device = images.device

    def uniform(limit: float) -> torch.Tensor:
        noise = torch.rand(count, generator=generator)
        return ((noise * 2.0 - 1.0) * limit).to(device)

    angle = uniform(0.17)
    scale_x = 1.0 + uniform(0.1)
    scale_y = 1.0 + uniform(0.1)
    cosine, sine = torch.cos(angle), torch.sin(angle)
    matrix = torch.stack(
        [
            torch.stack([cosine * scale_x, -sine * scale_y, uniform(0.1)], dim=1),
            torch.stack([sine * scale_x, cosine * scale_y, uniform(0.1)], dim=1),
        ],
        dim=1,
    )
    grid = functional.affine_grid(matrix, list(images.shape), align_corners=False)
    return functional.grid_sample(images, grid, mode="bilinear", align_corners=False)


@torch.no_grad()
def accuracy(
    network: DoodleNet, images: torch.Tensor, labels: torch.Tensor, batch: int = 4096
) -> float:
    network.eval()
    correct = 0
    for start in range(0, images.shape[0], batch):
        chunk = images[start : start + batch].unsqueeze(1).float() / 255.0
        correct += (network(chunk).argmax(1) == labels[start : start + batch]).sum().item()
    return correct / images.shape[0]


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--epochs", type=int, default=10)
    parser.add_argument("--batch-size", type=int, default=1024)
    parser.add_argument("--learning-rate", type=float, default=2e-3)
    parser.add_argument("--weight-decay", type=float, default=1e-4)
    parser.add_argument("--seed", type=int, default=7)
    parser.add_argument("--device", default="mps" if torch.backends.mps.is_available() else "cpu")
    parser.add_argument("--checkpoints", type=Path, default=CHECKPOINTS)
    parser.add_argument("--max-steps", type=int, default=None, help="stop early, for timing")
    args = parser.parse_args()

    args.checkpoints.mkdir(exist_ok=True)
    torch.manual_seed(args.seed)
    device = torch.device(args.device)
    train_images, train_labels = load_split("train")
    val_images, val_labels = load_split("val")
    train_images, train_labels = train_images.to(device), train_labels.to(device)
    val_images, val_labels = val_images.to(device), val_labels.to(device)

    network = DoodleNet(len(CLASSES)).to(device)
    optimizer = torch.optim.AdamW(
        network.parameters(), lr=args.learning_rate, weight_decay=args.weight_decay
    )
    steps_per_epoch = train_images.shape[0] // args.batch_size
    scheduler = torch.optim.lr_scheduler.OneCycleLR(
        optimizer, args.learning_rate, total_steps=steps_per_epoch * args.epochs
    )

    first_epoch, best, history = 0, 0.0, []
    resume = args.checkpoints / "last.pt"
    if resume.exists():
        state = torch.load(resume, map_location=device, weights_only=False)
        network.load_state_dict(state["network"])
        optimizer.load_state_dict(state["optimizer"])
        scheduler.load_state_dict(state["scheduler"])
        first_epoch, best, history = state["epoch"] + 1, state["best"], state["history"]
        torch.set_rng_state(state["rng"])

    shuffle_generator = torch.Generator().manual_seed(args.seed)
    augment_generator = torch.Generator().manual_seed(args.seed + 1)
    for epoch in range(first_epoch, args.epochs):
        network.train()
        started = time.perf_counter()
        order = torch.randperm(train_images.shape[0], generator=shuffle_generator).to(device)
        running_loss = 0.0
        for step in range(steps_per_epoch):
            picks = order[step * args.batch_size : (step + 1) * args.batch_size]
            images = train_images[picks].unsqueeze(1).float() / 255.0
            loss = functional.cross_entropy(
                network(augment(images, augment_generator)),
                train_labels[picks],
                label_smoothing=0.05,
            )
            optimizer.zero_grad(set_to_none=True)
            loss.backward()
            optimizer.step()
            scheduler.step()
            running_loss += loss.item()
            if args.max_steps and step + 1 == args.max_steps:
                seconds = time.perf_counter() - started
                print(f"{args.max_steps} steps in {seconds:.1f}s on {device}")
                return

        val_accuracy = accuracy(network, val_images, val_labels)
        seconds = time.perf_counter() - started
        history.append(
            {
                "epoch": epoch + 1,
                "train_loss": round(running_loss / steps_per_epoch, 4),
                "val_top1": round(val_accuracy, 4),
                "seconds": round(seconds, 1),
            }
        )
        print(history[-1], flush=True)
        state = {
            "network": network.state_dict(),
            "optimizer": optimizer.state_dict(),
            "scheduler": scheduler.state_dict(),
            "epoch": epoch,
            "best": max(best, val_accuracy),
            "history": history,
            "rng": torch.get_rng_state(),
        }
        torch.save(state, resume)
        if val_accuracy > best:
            best = val_accuracy
            torch.save(network.state_dict(), args.checkpoints / "best.pt")

    log = {
        "device": args.device,
        "batch_size": args.batch_size,
        "learning_rate": args.learning_rate,
        "weight_decay": args.weight_decay,
        "seed": args.seed,
        "train_records": int(train_images.shape[0]),
        "epochs": history,
    }
    (REPO_ROOT / "results" / "training_log.json").write_text(json.dumps(log, indent=2) + "\n")


if __name__ == "__main__":
    main()
