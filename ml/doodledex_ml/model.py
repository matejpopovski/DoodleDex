"""The classifier and the wrapper that fixes its on-device contract."""

import torch
from torch import nn


def _conv_block(in_channels: int, out_channels: int) -> nn.Sequential:
    return nn.Sequential(
        nn.Conv2d(in_channels, out_channels, 3, padding=1, bias=False),
        nn.BatchNorm2d(out_channels),
        nn.ReLU(inplace=True),
        nn.Conv2d(out_channels, out_channels, 3, padding=1, bias=False),
        nn.BatchNorm2d(out_channels),
        nn.ReLU(inplace=True),
        nn.MaxPool2d(2),
    )


class DoodleNet(nn.Module):
    """Three VGG-style blocks and global average pooling, about 300k parameters.

    Doodles are thin line art at 28x28, so wide receptive fields matter more than depth, and the
    three poolings bring the 28x28 input down to 3x3 before the pool.
    """

    def __init__(self, classes: int, widths: tuple[int, int, int] = (32, 64, 128)) -> None:
        super().__init__()
        self.features = nn.Sequential(
            _conv_block(1, widths[0]),
            _conv_block(widths[0], widths[1]),
            _conv_block(widths[1], widths[2]),
        )
        self.pool = nn.AdaptiveAvgPool2d(1)
        self.dropout = nn.Dropout(0.2)
        self.classifier = nn.Linear(widths[2], classes)

    def forward(self, images: torch.Tensor) -> torch.Tensor:
        """Map (n, 1, 28, 28) images in [0, 1] to logits."""
        pooled = self.pool(self.features(images)).flatten(1)
        return self.classifier(self.dropout(pooled))


class DeployedDoodleNet(nn.Module):
    """Takes raw 0-255 pixels and returns probabilities.

    Keeping the scaling inside the model means the app and the training code cannot disagree about
    it: the only thing the app must get right is the pixel bytes, and those are fixture-tested.
    """

    def __init__(self, network: DoodleNet) -> None:
        super().__init__()
        self.network = network

    def forward(self, pixels: torch.Tensor) -> torch.Tensor:
        return torch.softmax(self.network(pixels / 255.0), dim=1)
