from __future__ import annotations

import math
import sys
import tempfile
import unittest
from collections import Counter
from pathlib import Path
from xml.etree import ElementTree

from PIL import Image, ImageDraw

sys.path.insert(0, str(Path(__file__).resolve().parent))

import generate_launcher_icon as icon


def _px(value: float, size: int) -> int:
    return round(value / icon.ARTBOARD_DP * size)


def _mask_from_predicate(
    image: Image.Image,
    predicate: object,
) -> Image.Image:
    rgba = image.convert("RGBA")
    mask = Image.new("L", rgba.size)
    mask.putdata(
        [255 if predicate(pixel) else 0 for pixel in rgba.get_flattened_data()]
    )
    return mask


def _component_sizes(mask: Image.Image) -> list[int]:
    bounds = mask.getbbox()
    if bounds is None:
        return []
    left, top, right, bottom = bounds
    remaining = {
        (x, y)
        for y in range(top, bottom)
        for x in range(left, right)
        if mask.getpixel((x, y)) > 0
    }
    sizes: list[int] = []
    while remaining:
        stack = [remaining.pop()]
        size = 0
        while stack:
            x, y = stack.pop()
            size += 1
            for neighbor in ((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)):
                if neighbor in remaining:
                    remaining.remove(neighbor)
                    stack.append(neighbor)
        sizes.append(size)
    return sorted(sizes, reverse=True)


def _svg_number(value: float) -> str:
    return f"{value:g}"


def _svg_color(color: tuple[int, int, int]) -> str:
    return "#" + "".join(f"{channel:02X}" for channel in color)


class LauncherIconGeneratorTest(unittest.TestCase):
    def test_geometry_is_centered_safe_and_non_overlapping(self) -> None:
        self.assertEqual(icon.LENS_CENTER_DP, (54.0, 54.0))
        left, top, right, bottom = icon.SAFE_ZONE_DP
        camera_left, camera_top, camera_right, camera_bottom = icon.CAMERA_BOUNDS_DP
        self.assertGreaterEqual(camera_left, left)
        self.assertGreaterEqual(camera_top, top)
        self.assertLessEqual(camera_right, right)
        self.assertLessEqual(camera_bottom, bottom)
        distance = math.dist(icon.LENS_CENTER_DP, icon.RED_DOT_CENTER_DP)
        self.assertGreater(distance, icon.LENS_RADIUS_DP + icon.RED_DOT_RADIUS_DP)

    def test_generated_assets_have_required_sizes_modes_and_safe_bounds(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            paths = icon.write_assets(root)

            with Image.open(paths["legacy"]) as image:
                self.assertEqual(image.size, (1024, 1024))
                self.assertEqual(image.mode, "RGB")
            with Image.open(paths["background"]) as image:
                self.assertEqual(image.size, (432, 432))
                self.assertEqual(image.mode, "RGB")
            with Image.open(paths["play"]) as image:
                self.assertEqual(image.size, (512, 512))
                self.assertEqual(image.mode, "RGBA")
                self.assertEqual(image.getchannel("A").getextrema(), (255, 255))
                self.assertEqual(image.info.get("srgb"), 0)

            with Image.open(paths["foreground"]).convert("RGBA") as image:
                self.assertEqual(image.size, (432, 432))
                alpha_bounds = image.getchannel("A").getbbox()
                self.assertIsNotNone(alpha_bounds)
                safe = tuple(round(value * 4) for value in icon.SAFE_ZONE_DP)
                self.assertGreaterEqual(alpha_bounds[0], safe[0] - 1)
                self.assertGreaterEqual(alpha_bounds[1], safe[1] - 1)
                self.assertLessEqual(alpha_bounds[2], safe[2] + 1)
                self.assertLessEqual(alpha_bounds[3], safe[3] + 1)

            with Image.open(paths["monochrome"]).convert("RGBA") as image:
                self.assertEqual(image.size, (432, 432))
                opaque_rgb = {
                    (red, green, blue)
                    for red, green, blue, alpha in image.get_flattened_data()
                    if alpha > 0
                }
                self.assertEqual(opaque_rgb, {(255, 255, 255)})

            svg = paths["master_svg"].read_text(encoding="utf-8")
            self.assertIn('cx="54" cy="54"', svg)
            self.assertIn('#FF4D4F', svg)
            self.assertNotIn('rx="22"', svg)

    def test_color_output_contains_centered_lens_continuous_m_and_separate_red_dot(self) -> None:
        size = 432
        image = icon.render_foreground(size).convert("RGBA")
        center_x = _px(icon.LENS_CENTER_DP[0], size)
        center_y = _px(icon.LENS_CENTER_DP[1], size)
        lens_radius = _px(icon.LENS_RADIUS_DP, size)

        dark_lens = _mask_from_predicate(
            image,
            lambda pixel: pixel[3] >= 150
            and pixel[0] < 80
            and pixel[1] < 130
            and pixel[2] < 120,
        )
        lens_window = Image.new("L", image.size)
        ImageDraw.Draw(lens_window).ellipse(
            (
                center_x - lens_radius - 2,
                center_y - lens_radius - 2,
                center_x + lens_radius + 2,
                center_y + lens_radius + 2,
            ),
            fill=255,
        )
        dark_lens = Image.composite(dark_lens, Image.new("L", image.size), lens_window)
        lens_bounds = dark_lens.getbbox()
        self.assertIsNotNone(lens_bounds)
        assert lens_bounds is not None
        self.assertAlmostEqual((lens_bounds[0] + lens_bounds[2] - 1) / 2, center_x, delta=2)
        self.assertAlmostEqual((lens_bounds[1] + lens_bounds[3] - 1) / 2, center_y, delta=2)
        self.assertGreater(lens_bounds[2] - lens_bounds[0], lens_radius * 1.75)
        self.assertGreater(lens_bounds[3] - lens_bounds[1], lens_radius * 1.75)

        m_mask = _mask_from_predicate(
            image,
            lambda pixel: pixel[3] >= 180
            and pixel[0] >= 120
            and pixel[1] >= 160
            and pixel[2] >= 140,
        )
        lens_interior = Image.new("L", image.size)
        ImageDraw.Draw(lens_interior).ellipse(
            (
                center_x - lens_radius + 3,
                center_y - lens_radius + 3,
                center_x + lens_radius - 3,
                center_y + lens_radius - 3,
            ),
            fill=255,
        )
        m_mask = Image.composite(m_mask, Image.new("L", image.size), lens_interior)
        component_sizes = _component_sizes(m_mask)
        self.assertTrue(component_sizes)
        self.assertGreater(component_sizes[0], 1_500)
        self.assertGreater(component_sizes[0] / sum(component_sizes), 0.98)
        m_bounds = m_mask.getbbox()
        self.assertIsNotNone(m_bounds)
        assert m_bounds is not None
        self.assertLessEqual(m_bounds[0], _px(45.5, size))
        self.assertGreaterEqual(m_bounds[2], _px(62.5, size))
        self.assertLessEqual(m_bounds[1], _px(46.5, size))
        self.assertGreaterEqual(m_bounds[3], _px(61.5, size))

        red_mask = _mask_from_predicate(
            image,
            lambda pixel: pixel[3] >= 180
            and pixel[0] >= 200
            and pixel[0] > pixel[1] * 1.25
            and pixel[0] > pixel[2] * 1.25,
        )
        red_bounds = red_mask.getbbox()
        self.assertIsNotNone(red_bounds)
        assert red_bounds is not None
        expected_red_x = _px(icon.RED_DOT_CENTER_DP[0], size)
        expected_red_y = _px(icon.RED_DOT_CENTER_DP[1], size)
        self.assertAlmostEqual((red_bounds[0] + red_bounds[2] - 1) / 2, expected_red_x, delta=2)
        self.assertAlmostEqual((red_bounds[1] + red_bounds[3] - 1) / 2, expected_red_y, delta=2)
        self.assertGreater(sum(red_mask.get_flattened_data()) / 255, 350)
        red_pixels = [
            (x, y)
            for y in range(red_bounds[1], red_bounds[3])
            for x in range(red_bounds[0], red_bounds[2])
            if red_mask.getpixel((x, y))
        ]
        gap = min(math.dist((x, y), (center_x, center_y)) for x, y in red_pixels) - lens_radius
        self.assertGreater(gap, _px(2.0, size))

    def test_monochrome_output_preserves_camera_and_m_with_lens_and_dot_cutouts(self) -> None:
        size = 432
        image = icon.render_foreground(size, monochrome=True).convert("RGBA")
        alpha = image.getchannel("A")
        opaque_colors = {
            pixel[:3]
            for pixel in image.get_flattened_data()
            if pixel[3] > 0
        }
        self.assertEqual(opaque_colors, {(255, 255, 255)})
        self.assertGreater(alpha.getpixel((_px(30, size), _px(55, size))), 240)
        self.assertGreater(alpha.getpixel((_px(54, size), _px(28, size))), 240)
        self.assertEqual(alpha.getpixel((_px(54, size), _px(40, size))), 0)
        self.assertEqual(
            alpha.getpixel((_px(icon.RED_DOT_CENTER_DP[0], size), _px(icon.RED_DOT_CENTER_DP[1], size))),
            0,
        )

        center_x = _px(icon.LENS_CENTER_DP[0], size)
        center_y = _px(icon.LENS_CENTER_DP[1], size)
        lens_radius = _px(icon.LENS_RADIUS_DP, size)
        lens_crop_mask = Image.new("L", image.size)
        ImageDraw.Draw(lens_crop_mask).ellipse(
            (
                center_x - lens_radius + 2,
                center_y - lens_radius + 2,
                center_x + lens_radius - 2,
                center_y + lens_radius - 2,
            ),
            fill=255,
        )
        positive_m = Image.composite(
            alpha.point(lambda value: 255 if value >= 128 else 0),
            Image.new("L", image.size),
            lens_crop_mask,
        )
        components = _component_sizes(positive_m)
        self.assertEqual(len(components), 1)
        self.assertGreater(components[0], 1_500)
        m_bounds = positive_m.getbbox()
        self.assertIsNotNone(m_bounds)
        assert m_bounds is not None
        self.assertLessEqual(m_bounds[0], _px(45.5, size))
        self.assertGreaterEqual(m_bounds[2], _px(62.5, size))

    def test_background_has_brand_distribution_without_flutter_triangle_or_outer_white_ring(self) -> None:
        size = 432
        background = icon.render_background(size).convert("RGB")
        pixels = list(background.get_flattened_data())
        self.assertGreater(len(set(pixels)), 100)
        self.assertFalse(any(blue > green + 18 for red, green, blue in pixels))
        self.assertFalse(any(min(red, green, blue) > 220 for red, green, blue in pixels))

        full = icon.render_full_icon(size).convert("RGB")
        perimeter = []
        for offset in range(size):
            perimeter.extend(
                (
                    full.getpixel((offset, 0)),
                    full.getpixel((offset, size - 1)),
                    full.getpixel((0, offset)),
                    full.getpixel((size - 1, offset)),
                )
            )
        self.assertFalse(any(min(pixel) > 220 for pixel in perimeter))

    def test_scene_drives_svg_camera_lens_letter_red_dot_and_palette(self) -> None:
        scene = icon.SCENE
        svg = ElementTree.fromstring(icon.build_master_svg())

        def by_id(identifier: str) -> ElementTree.Element:
            element = svg.find(f".//*[@id='{identifier}']")
            self.assertIsNotNone(element, identifier)
            assert element is not None
            return element

        for identifier, primitive in (
            ("camera-body", scene.camera_body),
            ("camera-bump", scene.camera_bump),
        ):
            element = by_id(identifier)
            left, top, right, bottom = primitive.bounds
            self.assertEqual(element.attrib["x"], _svg_number(left))
            self.assertEqual(element.attrib["y"], _svg_number(top))
            self.assertEqual(element.attrib["width"], _svg_number(right - left))
            self.assertEqual(element.attrib["height"], _svg_number(bottom - top))
            self.assertEqual(element.attrib["rx"], _svg_number(primitive.radius))

        lens = by_id("lens")
        self.assertEqual(lens.attrib["cx"], _svg_number(scene.lens.center[0]))
        self.assertEqual(lens.attrib["cy"], _svg_number(scene.lens.center[1]))
        self.assertEqual(lens.attrib["r"], _svg_number(scene.lens.radius))
        self.assertEqual(lens.attrib["fill"], _svg_color(scene.lens.color))

        letter = by_id("letter-m")
        self.assertEqual(
            letter.attrib["points"],
            " ".join(f"{_svg_number(x)},{_svg_number(y)}" for x, y in scene.letter.points),
        )
        self.assertEqual(letter.attrib["stroke-width"], _svg_number(scene.letter.width))

        red_dot = by_id("red-dot")
        self.assertEqual(red_dot.attrib["cx"], _svg_number(scene.red_dot.center[0]))
        self.assertEqual(red_dot.attrib["cy"], _svg_number(scene.red_dot.center[1]))
        self.assertEqual(red_dot.attrib["r"], _svg_number(scene.red_dot.radius))
        self.assertEqual(red_dot.attrib["fill"], _svg_color(scene.red_dot.color))

        for gradient_id, stops in (
            ("background", scene.background_stops),
            ("glass", scene.glass_stops),
            ("letter", scene.letter_stops),
        ):
            colors = [stop.attrib["stop-color"] for stop in by_id(gradient_id)]
            self.assertEqual(colors, [_svg_color(color) for color in stops])

    def test_all_six_outputs_are_byte_deterministic_across_independent_directories(self) -> None:
        with tempfile.TemporaryDirectory() as first, tempfile.TemporaryDirectory() as second:
            first_paths = icon.write_assets(Path(first))
            second_paths = icon.write_assets(Path(second))
            self.assertEqual(first_paths.keys(), second_paths.keys())
            for name in first_paths:
                with self.subTest(asset=name):
                    self.assertEqual(first_paths[name].read_bytes(), second_paths[name].read_bytes())

    def test_background_gradient_reaches_every_corner_without_flat_fill(self) -> None:
        image = icon.render_background(432).convert("RGB")
        corner_size = 72
        corner_boxes = {
            "top_left": (0, 0, corner_size, corner_size),
            "top_right": (432 - corner_size, 0, 432, corner_size),
            "bottom_left": (0, 432 - corner_size, corner_size, 432),
            "bottom_right": (432 - corner_size, 432 - corner_size, 432, 432),
        }

        for name, box in corner_boxes.items():
            with self.subTest(corner=name):
                pixels = image.crop(box).get_flattened_data()
                most_common_count = Counter(pixels).most_common(1)[0][1]
                self.assertLess(most_common_count / len(pixels), 0.20)

    def test_camera_highlight_is_local_instead_of_a_continuous_white_outline(self) -> None:
        image = icon.render_foreground(432).convert("RGBA")

        def pixel_at_dp(x: float, y: float) -> tuple[int, int, int, int]:
            return image.getpixel((round(x * 4), round(y * 4)))

        def is_soft_highlight(pixel: tuple[int, int, int, int]) -> bool:
            red, green, blue, alpha = pixel
            return alpha >= 180 and min(red, green, blue) >= 220

        def is_near_white_outline(pixel: tuple[int, int, int, int]) -> bool:
            red, green, blue, alpha = pixel
            return alpha >= 240 and min(red, green, blue) >= 245

        local_highlight_points = ((30.0, 32.0), (46.0, 25.0), (54.0, 25.0))
        nonlocal_outline_points = ((21.0, 56.0), (54.0, 80.0), (87.0, 56.0))

        self.assertTrue(any(is_soft_highlight(pixel_at_dp(*point)) for point in local_highlight_points))
        for point in nonlocal_outline_points:
            with self.subTest(point=point):
                self.assertFalse(is_near_white_outline(pixel_at_dp(*point)))

        sampled_outline = local_highlight_points + nonlocal_outline_points
        self.assertFalse(any(pixel_at_dp(*point) == (255, 255, 255, 255) for point in sampled_outline))


if __name__ == "__main__":
    unittest.main()
