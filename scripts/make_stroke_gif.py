"""Join the per-stroke simulator screenshots into the README animation.

Usage: uv run --group train python scripts/make_stroke_gif.py <frames dir> <output.gif>
"""

import re
import sys
from pathlib import Path

from PIL import Image

WIDTH = 320
FRAME_MILLISECONDS = 800
LAST_FRAME_MILLISECONDS = 3000


def main() -> None:
    frames_dir, output = Path(sys.argv[1]), Path(sys.argv[2])
    paths = sorted(
        frames_dir.glob("frame-*.png"),
        key=lambda path: int(re.search(r"\d+", path.stem).group()),
    )
    frames = []
    for path in paths:
        image = Image.open(path).convert("RGB")
        height = round(image.height * WIDTH / image.width)
        frames.append(image.resize((WIDTH, height), Image.Resampling.LANCZOS))
    durations = [FRAME_MILLISECONDS] * (len(frames) - 1) + [LAST_FRAME_MILLISECONDS]
    frames[0].save(
        output, save_all=True, append_images=frames[1:], duration=durations, loop=0, optimize=True
    )
    print(f"{len(frames)} frames, {output.stat().st_size / 1024:.0f} KB")


if __name__ == "__main__":
    main()
