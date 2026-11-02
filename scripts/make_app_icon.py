"""Draw the app icon: a hand-wobbled star as a die-cut sticker on dotted paper.

The artwork is generated here, from nothing but coordinates, so the repo has no third-party art.

Usage: uv run --group train python scripts/make_app_icon.py
"""

import math
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

SIZE = 1024
SCALE = 3
OUT = (
    Path(__file__).resolve().parents[1] / "DoodleDex/Assets.xcassets/AppIcon.appiconset/AppIcon.png"
)
PAPER = (251, 244, 230)
DOT = (225, 214, 196)
INK = (37, 42, 51)
MUSTARD = (232, 166, 28)


def wobbly_star(cx: float, cy: float, outer: float, inner: float) -> list[tuple[float, float]]:
    """A five-pointed star with hand-drawn wobble and a slight overshoot where the pen closes."""
    points = []
    for index in range(11):
        angle = math.radians(-90 + index * 36 + 4)
        radius = outer if index % 2 == 0 else inner
        wobble = 1 + 0.035 * math.sin(index * 2.7)
        points.append(
            (cx + radius * wobble * math.cos(angle), cy + radius * wobble * math.sin(angle))
        )
    return points


def polyline(draw: ImageDraw.ImageDraw, points, color, width: float) -> None:
    draw.line(points, fill=color, width=int(width), joint="curve")
    radius = width / 2
    for x, y in points:
        draw.ellipse((x - radius, y - radius, x + radius, y + radius), fill=color)


def main() -> None:
    size = SIZE * SCALE
    image = Image.new("RGB", (size, size), PAPER)
    draw = ImageDraw.Draw(image)
    for row in range(40, size, 96 * SCALE // 2):
        for column in range(40, size, 96 * SCALE // 2):
            draw.ellipse((column, row, column + 16, row + 16), fill=DOT)

    star = [(x * SCALE, y * SCALE) for x, y in wobbly_star(512, 540, 400, 170)]

    shadow = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    polyline(ImageDraw.Draw(shadow), [(x + 24, y + 42) for x, y in star], (37, 42, 51, 90), 330)
    image.paste(
        shadow.filter(ImageFilter.GaussianBlur(36)),
        (0, 0),
        shadow.filter(ImageFilter.GaussianBlur(36)),
    )

    polyline(draw, star, (255, 255, 255), 330)
    draw.polygon(star, fill=(255, 255, 255))
    polyline(draw, star, MUSTARD, 200)
    draw.polygon(star, fill=MUSTARD)
    polyline(draw, star, INK, 62)

    image.resize((SIZE, SIZE), Image.Resampling.LANCZOS).save(OUT)
    print(f"wrote {OUT}")


if __name__ == "__main__":
    main()
