from __future__ import annotations

import math
import sys
import tempfile
import unittest
from collections import Counter
from pathlib import Path

from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))

import generate_launcher_icon as icon


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
