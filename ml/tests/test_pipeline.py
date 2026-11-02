import base64
import json

import numpy as np
import pytest

from doodledex_ml.fixtures import PIPELINE_FIXTURES, decode_strokes, edge_cases, encode_strokes
from doodledex_ml.pipeline import (
    DEFAULT_CONFIG,
    normalize,
    preprocess,
    rasterize,
    rdp,
    resample,
    simplify,
)


def test_normalize_scales_longest_side_and_keeps_aspect() -> None:
    result = normalize([[(10.0, 20.0), (110.0, 70.0)]])
    assert result[0][1] == pytest.approx((255.0, 127.5))


def test_normalize_uses_the_box_of_every_stroke() -> None:
    result = normalize([[(0.0, 0.0), (10.0, 0.0)], [(0.0, 20.0), (5.0, 20.0)]])
    assert result[0][1] == pytest.approx((127.5, 0.0))
    assert result[1][0] == pytest.approx((0.0, 255.0))


def test_normalize_leaves_a_tap_finite() -> None:
    assert normalize([[(7.0, 9.0)]]) == [[(0.0, 0.0)]]


def test_resample_spacing_and_endpoints() -> None:
    points = resample([(0.0, 0.0), (0.0, 2.5)], 1.0)
    assert points == [(0.0, 0.0), (0.0, 1.0), (0.0, 2.0), (0.0, 2.5)]


def test_resample_carries_distance_across_a_corner() -> None:
    points = resample([(0.0, 0.0), (1.5, 0.0), (1.5, 1.5)], 1.0)
    assert points == [(0.0, 0.0), (1.0, 0.0), (1.5, 0.5), (1.5, 1.5)]


def test_resample_skips_repeated_points() -> None:
    assert resample([(3.0, 3.0), (3.0, 3.0)], 1.0) == [(3.0, 3.0)]


def test_rdp_removes_collinear_points_and_keeps_corners() -> None:
    line = [(float(i), 0.0) for i in range(11)]
    assert rdp(line, 2.0) == [(0.0, 0.0), (10.0, 0.0)]
    corner = [(0.0, 0.0), (5.0, 0.1), (10.0, 0.0), (10.0, 10.0)]
    assert rdp(corner, 2.0) == [(0.0, 0.0), (10.0, 0.0), (10.0, 10.0)]


def test_rdp_keeps_a_closed_loop_open() -> None:
    loop = [(0.0, 0.0), (50.0, 0.0), (50.0, 50.0), (0.0, 50.0), (0.0, 0.0)]
    assert len(rdp(loop, 2.0)) >= 4


def test_rdp_measures_to_the_line_not_the_segment() -> None:
    # The middle point overshoots the chord but sits on its line, so the textbook distance is zero.
    assert rdp([(0.0, 0.0), (30.0, 0.0), (10.0, 0.0)], 2.0) == [(0.0, 0.0), (10.0, 0.0)]


def test_simplify_produces_integer_coordinates_inside_the_canvas() -> None:
    strokes = simplify([[(0.1, 0.2), (33.3, 80.8), (91.7, 44.4)]])
    values = [value for stroke in strokes for point in stroke for value in point]
    assert all(float(value).is_integer() and 0 <= value <= 255 for value in values)


def test_rasterize_centres_a_tap() -> None:
    image = rasterize([[(0.0, 0.0)]])
    rows, columns = np.nonzero(image)
    assert rows.mean() == pytest.approx(13.5, abs=0.01)
    assert columns.mean() == pytest.approx(13.5, abs=0.01)


def test_rasterize_keeps_ink_inside_the_frame_at_full_extent() -> None:
    image = rasterize(simplify([[(0.0, 0.0), (255.0, 255.0)], [(0.0, 255.0), (255.0, 0.0)]]))
    assert image[0].max() < 10
    assert image[-1].max() < 10
    assert image.max() == 255


def test_rasterize_does_not_double_count_a_retraced_stroke() -> None:
    once = rasterize([[(20.0, 128.0), (235.0, 128.0)]])
    twice = rasterize([[(20.0, 128.0), (235.0, 128.0), (20.0, 128.0)]])
    np.testing.assert_array_equal(once, twice)


def test_separate_strokes_composite_over_each_other() -> None:
    separate = rasterize([[(20.0, 128.0), (235.0, 128.0)], [(20.0, 128.0), (235.0, 128.0)]])
    single = rasterize([[(20.0, 128.0), (235.0, 128.0)]])
    assert separate.sum() > single.sum()


def test_preprocess_ignores_position_and_scale_up_to_rounding() -> None:
    strokes = [[(12.0, 40.0), (60.0, 90.0), (130.0, 25.0)], [(70.0, 10.0), (75.0, 140.0)]]
    moved = [[(x * 2.5 - 90.0, y * 2.5 + 15.0) for x, y in stroke] for stroke in strokes]
    difference = np.abs(preprocess(strokes).astype(int) - preprocess(moved).astype(int))
    assert difference.mean() < 2.0


@pytest.mark.parametrize("name", sorted(edge_cases()))
def test_edge_cases_produce_ink(name: str) -> None:
    assert preprocess(edge_cases()[name]).max() > 0


def test_stroke_encoding_round_trips_exact_doubles() -> None:
    strokes = [[(0.1, 1.0 / 3.0)], [(-2.5, 1e-9), (414.48199462890625, 7.0)]]
    assert decode_strokes(*encode_strokes(strokes)) == strokes


def test_committed_fixtures_match_the_current_pipeline() -> None:
    """Fails when pipeline.py changes without regenerating the vectors the Swift tests replay."""
    payload = json.loads(PIPELINE_FIXTURES.read_text())
    assert payload["config"]["supersample"] == DEFAULT_CONFIG.supersample
    assert payload["config"]["line_diameter"] == DEFAULT_CONFIG.line_diameter
    assert len(payload["cases"]) > 100
    for case in payload["cases"]:
        strokes = decode_strokes(case["point_counts"], case["coordinates"])
        expected = base64.b64decode(case["pixels"])
        assert preprocess(strokes).tobytes() == expected, case["id"]
        expected_simplified = decode_strokes(
            case["simplified_point_counts"], case["simplified_coordinates"]
        )
        assert simplify(strokes) == expected_simplified, case["id"]
