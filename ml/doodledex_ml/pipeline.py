"""The canonical strokes-to-28x28 pipeline.

`Packages/DoodleCore/Sources/DoodleCore/Preprocessor.swift` is a port of this file. Both are written
as the same sequence of IEEE double operations, so the two produce identical bytes, and that claim
is tested rather than assumed: `fixtures.py` writes vectors from this module and the Swift tests
replay them.

Google's documented steps for the simplified dataset are: align to the top-left, scale the longest
side to 255, resample at 1 pixel spacing, and simplify with Ramer-Douglas-Peucker at epsilon 2. The
28x28 rendering is not documented. `verify_dataset` shows that the parameters below reproduce the
published bitmaps.
"""

import math
from dataclasses import dataclass
from itertools import pairwise

import numpy as np

Point = tuple[float, float]
Stroke = list[Point]


@dataclass(frozen=True)
class PipelineConfig:
    scaled_extent: float = 255.0
    resample_spacing: float = 1.0
    rdp_epsilon: float = 2.0
    canvas: float = 256.0
    side: int = 28
    line_diameter: float = 16.0
    padding: float = 16.0
    supersample: int = 8
    rdp_to_segment: bool = False


DEFAULT_CONFIG = PipelineConfig()


def normalize(strokes: list[Stroke], config: PipelineConfig = DEFAULT_CONFIG) -> list[Stroke]:
    """Move the drawing to the origin and scale its longest side to `scaled_extent`.

    The bounding box is the box of the strokes passed in. For a partial sketch that means the
    prefix is rescaled to fill the frame, which is what the app does after every stroke.
    """
    xs = [x for stroke in strokes for x, _ in stroke]
    ys = [y for stroke in strokes for _, y in stroke]
    min_x, min_y = min(xs), min(ys)
    extent = max(max(xs) - min_x, max(ys) - min_y)
    # A lone tap has no extent, and dividing by it would turn the dot into NaNs.
    scale = config.scaled_extent / extent if extent > 0 else 1.0
    return [[((x - min_x) * scale, (y - min_y) * scale) for x, y in stroke] for stroke in strokes]


def resample(stroke: Stroke, spacing: float) -> Stroke:
    """Walk the polyline and emit a point every `spacing` units, keeping both endpoints."""
    output = [stroke[0]]
    travelled = 0.0
    for (ax, ay), (bx, by) in pairwise(stroke):
        dx = bx - ax
        dy = by - ay
        length = math.sqrt(dx * dx + dy * dy)
        if length == 0.0:
            continue
        position = spacing - travelled
        while position <= length:
            t = position / length
            output.append((ax + t * dx, ay + t * dy))
            position += spacing
        travelled = length - (position - spacing)
    if output[-1] != stroke[-1]:
        output.append(stroke[-1])
    return output


def _squared_distance_to_line(p: Point, a: Point, b: Point) -> float:
    dx = b[0] - a[0]
    dy = b[1] - a[1]
    length_squared = dx * dx + dy * dy
    if length_squared == 0.0:
        ex = p[0] - a[0]
        ey = p[1] - a[1]
        return ex * ex + ey * ey
    cross = (p[0] - a[0]) * dy - (p[1] - a[1]) * dx
    return cross * cross / length_squared


def _squared_distance_to_segment(p: Point, a: Point, b: Point) -> float:
    dx = b[0] - a[0]
    dy = b[1] - a[1]
    length_squared = dx * dx + dy * dy
    if length_squared == 0.0:
        return _squared_distance_to_line(p, a, b)
    t = ((p[0] - a[0]) * dx + (p[1] - a[1]) * dy) / length_squared
    t = max(0.0, min(1.0, t))
    ex = p[0] - a[0] - t * dx
    ey = p[1] - a[1] - t * dy
    return ex * ex + ey * ey


def rdp(stroke: Stroke, epsilon: float, distance=_squared_distance_to_line) -> Stroke:
    """Ramer-Douglas-Peucker with an explicit stack, because a slow stroke can be very long.

    Distance is to the infinite line through the endpoints, the textbook definition. Distance to the
    segment looks more careful, but `verify_dataset` shows it drifts from Google's output, so it
    remains here only for that comparison and has no Swift counterpart.
    """
    count = len(stroke)
    if count < 3:
        return list(stroke)
    keep = [False] * count
    keep[0] = keep[-1] = True
    limit = epsilon * epsilon
    stack = [(0, count - 1)]
    while stack:
        first, last = stack.pop()
        farthest = -1
        largest = limit
        for index in range(first + 1, last):
            measured = distance(stroke[index], stroke[first], stroke[last])
            if measured > largest:
                largest = measured
                farthest = index
        if farthest >= 0:
            keep[farthest] = True
            stack.append((first, farthest))
            stack.append((farthest, last))
    return [point for point, kept in zip(stroke, keep, strict=True) if kept]


def _round_half_up(value: float) -> float:
    return math.floor(value + 0.5)


def simplify(strokes: list[Stroke], config: PipelineConfig = DEFAULT_CONFIG) -> list[Stroke]:
    """Input strokes in any coordinate system to the integer strokes of the simplified dataset."""
    distance = _squared_distance_to_segment if config.rdp_to_segment else _squared_distance_to_line
    output = []
    for stroke in normalize(strokes, config):
        spaced = resample(stroke, config.resample_spacing) if config.resample_spacing else stroke
        reduced = rdp(spaced, config.rdp_epsilon, distance)
        output.append([(_round_half_up(x), _round_half_up(y)) for x, y in reduced])
    return output


def rasterize(strokes: list[Stroke], config: PipelineConfig = DEFAULT_CONFIG) -> np.ndarray:
    """Render simplified strokes to an (side, side) uint8 array, ink high, background zero.

    Each stroke is a capsule union over a supersampled grid, so a stroke crossing itself does not
    get darker. Strokes then composite over each other, which is the behaviour of stroking each
    path in turn on a 2D canvas and is what the published bitmaps show.
    """
    side = config.side
    grid = side * config.supersample
    total_padding = config.padding * 2.0 + config.line_diameter
    scale = side / (config.canvas + total_padding)
    radius = config.line_diameter / 2.0 * scale
    radius_squared = radius * radius
    offset_x = (config.canvas - max(x for stroke in strokes for x, _ in stroke)) / 2.0
    offset_y = (config.canvas - max(y for stroke in strokes for _, y in stroke)) / 2.0
    centers = (np.arange(grid, dtype=np.float64) + 0.5) / config.supersample

    image = np.zeros((side, side), dtype=np.float64)
    for stroke in strokes:
        scaled = [
            (
                (x + offset_x + total_padding / 2.0) * scale,
                (y + offset_y + total_padding / 2.0) * scale,
            )
            for x, y in stroke
        ]
        if len(scaled) == 1:
            scaled = scaled * 2
        mask = np.zeros((grid, grid), dtype=bool)
        for (ax, ay), (bx, by) in pairwise(scaled):
            low_x = max(math.floor((min(ax, bx) - radius) * config.supersample), 0)
            high_x = min(math.ceil((max(ax, bx) + radius) * config.supersample) + 1, grid)
            low_y = max(math.floor((min(ay, by) - radius) * config.supersample), 0)
            high_y = min(math.ceil((max(ay, by) + radius) * config.supersample) + 1, grid)
            if low_x >= high_x or low_y >= high_y:
                continue
            px = centers[low_x:high_x][np.newaxis, :]
            py = centers[low_y:high_y][:, np.newaxis]
            dx = bx - ax
            dy = by - ay
            length_squared = dx * dx + dy * dy
            if length_squared == 0.0:
                t = np.zeros((high_y - low_y, high_x - low_x))
            else:
                t = np.clip(((px - ax) * dx + (py - ay) * dy) / length_squared, 0.0, 1.0)
            ex = px - ax - t * dx
            ey = py - ay - t * dy
            mask[low_y:high_y, low_x:high_x] |= ex * ex + ey * ey <= radius_squared
        coverage = mask.reshape(side, config.supersample, side, config.supersample).sum(axis=(1, 3))
        image = 1.0 - (1.0 - image) * (1.0 - coverage / float(config.supersample**2))
    return np.floor(image * 255.0 + 0.5).astype(np.uint8)


def preprocess(strokes: list[Stroke], config: PipelineConfig = DEFAULT_CONFIG) -> np.ndarray:
    """The whole pipeline: strokes in any coordinate system to the model's 28x28 input."""
    return rasterize(simplify(strokes, config), config)
