from __future__ import annotations

import argparse
import math
import sys
from pathlib import Path
from xml.etree import ElementTree

from PIL import Image, UnidentifiedImageError

DEFAULT_ROOT = Path(__file__).resolve().parents[1]
LEGACY = {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}
ADAPTIVE = {"mdpi": 108, "hdpi": 162, "xhdpi": 216, "xxhdpi": 324, "xxxhdpi": 432}
ARTBOARD_DP = 108.0
SAFE_ZONE_DP = (21.0, 21.0, 87.0, 87.0)
LENS_CENTER_DP = (54.0, 54.0)
LENS_RADIUS_DP = 16.0
RED_DOT_CENTER_DP = (74.0, 42.0)
RED_DOT_RADIUS_DP = 3.5
ANDROID_NAMESPACE = "http://schemas.android.com/apk/res/android"


class VerificationError(RuntimeError):
    pass


def _require(condition: bool, message: str) -> None:
    if not condition:
        raise VerificationError(message)


def _relative(path: Path, root: Path) -> str:
    try:
        return path.relative_to(root).as_posix()
    except ValueError:
        return str(path)


def _px(value: float, size: int) -> int:
    return round(value / ARTBOARD_DP * size)


def _read_png(path: Path, size: int, mode: str, root: Path) -> Image.Image:
    label = _relative(path, root)
    _require(path.is_file(), f"Missing {label}")
    try:
        with Image.open(path) as opened:
            opened.load()
            _require(opened.format == "PNG", f"{label} is not a PNG")
            _require(opened.size == (size, size), f"{label} is {opened.size}, expected {(size, size)}")
            _require(opened.mode == mode, f"{label} mode is {opened.mode}, expected {mode}")
            image = opened.copy()
            image.info.update(opened.info)
            return image
    except (OSError, UnidentifiedImageError) as error:
        raise VerificationError(f"Cannot decode {label}: {error}") from error


def _component_sizes(points: set[tuple[int, int]]) -> list[int]:
    remaining = set(points)
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


def _require_brand_background(image: Image.Image, label: str) -> None:
    pixels = list(image.convert("RGB").get_flattened_data())
    _require(len(set(pixels)) >= 40, f"{label} background is blank or flat")
    blue_pixels = sum(blue > green + 18 for _, green, blue in pixels)
    near_white = sum(min(red, green, blue) > 220 for red, green, blue in pixels)
    _require(blue_pixels / len(pixels) < 0.002, f"{label} contains Flutter-blue artwork")
    _require(near_white / len(pixels) < 0.002, f"{label} background contains white artwork")
    greens = [green for _, green, _ in pixels]
    _require(max(greens) - min(greens) >= 55, f"{label} is missing the full brand gradient")


def _require_color_mark(image: Image.Image, label: str, transparent: bool) -> None:
    rgba = image.convert("RGBA")
    size = rgba.width
    pixels = rgba.load()
    center = (_px(LENS_CENTER_DP[0], size), _px(LENS_CENTER_DP[1], size))
    lens_radius = _px(LENS_RADIUS_DP, size)

    dark_lens: set[tuple[int, int]] = set()
    mint_m: set[tuple[int, int]] = set()
    red_dot: set[tuple[int, int]] = set()
    visible_colors: set[tuple[int, int, int]] = set()
    for y in range(size):
        for x in range(size):
            red, green, blue, alpha = pixels[x, y]
            if alpha > 0:
                visible_colors.add((red, green, blue))
            distance = math.dist((x, y), center)
            if distance <= _px(18.0, size) and alpha >= 140 and red < 90 and green < 150 and blue < 130:
                dark_lens.add((x, y))
            if distance <= _px(15.0, size) and alpha >= 160 and red >= 110 and green >= 155 and blue >= 130:
                mint_m.add((x, y))
            if alpha >= 180 and red >= 200 and red > green * 1.25 and red > blue * 1.25:
                red_dot.add((x, y))

    _require(len(visible_colors) >= 25, f"{label} has an empty or degenerate color distribution")
    _require(dark_lens, f"{label} is missing the dark center lens")
    lens_x = [point[0] for point in dark_lens]
    lens_y = [point[1] for point in dark_lens]
    lens_midpoint = ((min(lens_x) + max(lens_x)) / 2, (min(lens_y) + max(lens_y)) / 2)
    tolerance = max(2.0, _px(0.75, size))
    _require(
        abs(lens_midpoint[0] - center[0]) <= tolerance
        and abs(lens_midpoint[1] - center[1]) <= tolerance,
        f"{label} lens is not centered at {LENS_CENTER_DP}",
    )
    _require(max(lens_x) - min(lens_x) >= lens_radius * 1.7, f"{label} lens is too small or incomplete")
    _require(max(lens_y) - min(lens_y) >= lens_radius * 1.7, f"{label} lens is too small or incomplete")

    m_components = _component_sizes(mint_m)
    minimum_m_area = max(10, round(size * size * 0.006))
    _require(m_components and m_components[0] >= minimum_m_area, f"{label} is missing the thick M")
    _require(m_components[0] / sum(m_components) >= 0.94, f"{label} M is disconnected")
    m_x = [point[0] for point in mint_m]
    m_y = [point[1] for point in mint_m]
    _require(min(m_x) <= _px(47.0, size), f"{label} M is missing its left stroke")
    _require(max(m_x) >= _px(61.0, size), f"{label} M is missing its right stroke")
    _require(min(m_y) <= _px(48.0, size), f"{label} M is missing its upper strokes")
    _require(max(m_y) >= _px(60.0, size), f"{label} M is missing its lower strokes")

    minimum_red_area = max(3, round(size * size * 0.0015))
    _require(len(red_dot) >= minimum_red_area, f"{label} is missing the red recording dot")
    red_x = [point[0] for point in red_dot]
    red_y = [point[1] for point in red_dot]
    expected_red = (_px(RED_DOT_CENTER_DP[0], size), _px(RED_DOT_CENTER_DP[1], size))
    red_midpoint = ((min(red_x) + max(red_x)) / 2, (min(red_y) + max(red_y)) / 2)
    _require(
        math.dist(red_midpoint, expected_red) <= max(2.0, _px(0.75, size)),
        f"{label} red dot is misplaced",
    )
    gap = min(math.dist(point, center) for point in red_dot) - lens_radius
    _require(gap > _px(1.5, size), f"{label} red dot touches the lens")

    if transparent:
        alpha = rgba.getchannel("A")
        _require(alpha.getextrema() == (0, 255), f"{label} must contain transparent and opaque pixels")
        bounds = alpha.getbbox()
        _require(bounds is not None, f"{label} is fully transparent")
        if bounds is not None:
            safe = tuple(_px(value, size) for value in SAFE_ZONE_DP)
            allowance = max(2, _px(0.75, size))
            _require(bounds[0] >= safe[0] - allowance, f"{label} exceeds the left safe boundary")
            _require(bounds[1] >= safe[1] - allowance, f"{label} exceeds the top safe boundary")
            _require(bounds[2] <= safe[2] + allowance, f"{label} exceeds the right safe boundary")
            _require(bounds[3] <= safe[3] + allowance, f"{label} exceeds the bottom safe boundary")
    else:
        perimeter = []
        for offset in range(size):
            perimeter.extend(
                (
                    pixels[offset, 0],
                    pixels[offset, size - 1],
                    pixels[0, offset],
                    pixels[size - 1, offset],
                )
            )
        _require(
            not any(min(pixel[:3]) > 220 for pixel in perimeter),
            f"{label} has a pre-rendered outer white border",
        )
        rgb = list(image.convert("RGB").get_flattened_data())
        _require(
            sum(blue > green + 18 for _, green, blue in rgb) / len(rgb) < 0.002,
            f"{label} contains old Flutter-blue artwork",
        )


def _require_monochrome(image: Image.Image, label: str) -> None:
    rgba = image.convert("RGBA")
    size = rgba.width
    alpha = rgba.getchannel("A")
    _require(alpha.getextrema() == (0, 255), f"{label} must contain positive and negative shapes")
    visible_colors = {pixel[:3] for pixel in rgba.get_flattened_data() if pixel[3] > 0}
    _require(visible_colors == {(255, 255, 255)}, f"{label} may only contain a white positive shape")

    bounds = alpha.getbbox()
    _require(bounds is not None, f"{label} is empty")
    if bounds is not None:
        safe = tuple(_px(value, size) for value in SAFE_ZONE_DP)
        allowance = max(2, _px(0.75, size))
        _require(bounds[0] >= safe[0] - allowance, f"{label} exceeds the left safe boundary")
        _require(bounds[1] >= safe[1] - allowance, f"{label} exceeds the top safe boundary")
        _require(bounds[2] <= safe[2] + allowance, f"{label} exceeds the right safe boundary")
        _require(bounds[3] <= safe[3] + allowance, f"{label} exceeds the bottom safe boundary")

    center = (_px(LENS_CENTER_DP[0], size), _px(LENS_CENTER_DP[1], size))
    lens_radius = _px(LENS_RADIUS_DP, size)
    m_points: set[tuple[int, int]] = set()
    hole_samples = 0
    hole_negative = 0
    for y in range(max(0, center[1] - lens_radius), min(size, center[1] + lens_radius + 1)):
        for x in range(max(0, center[0] - lens_radius), min(size, center[0] + lens_radius + 1)):
            distance = math.dist((x, y), center)
            value = alpha.getpixel((x, y))
            if distance <= _px(15.0, size) and value >= 128:
                m_points.add((x, y))
            if _px(7.0, size) <= distance <= _px(13.5, size):
                hole_samples += 1
                hole_negative += value <= 32
    _require(hole_samples > 0 and hole_negative / hole_samples >= 0.45, f"{label} lens is not a negative shape")

    m_components = _component_sizes(m_points)
    minimum_m_area = max(10, round(size * size * 0.006))
    _require(m_components and m_components[0] >= minimum_m_area, f"{label} is missing the positive M")
    substantial = [component for component in m_components if component >= max(2, minimum_m_area // 10)]
    _require(len(substantial) == 1, f"{label} M is disconnected")
    m_x = [point[0] for point in m_points]
    _require(min(m_x) <= _px(47.0, size), f"{label} M is missing its left stroke")
    _require(max(m_x) >= _px(61.0, size), f"{label} M is missing its right stroke")

    red_center = (_px(RED_DOT_CENTER_DP[0], size), _px(RED_DOT_CENTER_DP[1], size))
    red_radius = max(1, _px(RED_DOT_RADIUS_DP * 0.65, size))
    red_values = [
        alpha.getpixel((x, y))
        for y in range(red_center[1] - red_radius, red_center[1] + red_radius + 1)
        for x in range(red_center[0] - red_radius, red_center[0] + red_radius + 1)
        if math.dist((x, y), red_center) <= red_radius
    ]
    _require(red_values and sum(value <= 32 for value in red_values) / len(red_values) >= 0.8, f"{label} red-dot cutout is missing")

    body_samples = (
        (_px(30.0, size), _px(55.0, size)),
        (_px(54.0, size), _px(28.0, size)),
        (_px(80.0, size), _px(60.0, size)),
    )
    _require(all(alpha.getpixel(point) >= 220 for point in body_samples), f"{label} camera positive shape is incomplete")


def _read_text(path: Path, root: Path) -> str:
    _require(path.is_file(), f"Missing {_relative(path, root)}")
    try:
        return path.read_text(encoding="utf-8")
    except OSError as error:
        raise VerificationError(f"Cannot read {_relative(path, root)}: {error}") from error


def _parse_xml(text: str, label: str) -> ElementTree.Element:
    try:
        return ElementTree.fromstring(text)
    except ElementTree.ParseError as error:
        raise VerificationError(f"Invalid {label}: {error}") from error


def _single_child(parent: ElementTree.Element, tag: str, label: str) -> ElementTree.Element:
    children = parent.findall(f"./{tag}")
    _require(len(children) == 1, f"{label} must contain exactly one <{tag}> element")
    return children[0]


def _require_android_attribute(
    element: ElementTree.Element,
    attribute: str,
    expected: str,
    label: str,
) -> None:
    actual = element.get(f"{{{ANDROID_NAMESPACE}}}{attribute}")
    _require(actual == expected, f"{label} android:{attribute} is {actual!r}, expected {expected!r}")


def verify_launcher_icon_resources(root: Path) -> int:
    root = root.resolve()
    res = root / "android" / "app" / "src" / "main" / "res"
    manifest_path = root / "android" / "app" / "src" / "main" / "AndroidManifest.xml"
    manifest = _read_text(manifest_path, root)
    manifest_root = _parse_xml(manifest, "Android manifest XML")
    _require(manifest_root.tag == "manifest", "Android manifest root must be <manifest>")
    application = _single_child(manifest_root, "application", "Android manifest")
    _require_android_attribute(
        application,
        "icon",
        "@mipmap/ic_launcher",
        "Manifest <application>",
    )
    _require_android_attribute(
        application,
        "roundIcon",
        "@mipmap/ic_launcher_round",
        "Manifest <application>",
    )

    adaptive_xml = res / "mipmap-anydpi-v26" / "ic_launcher.xml"
    round_xml = res / "mipmap-anydpi-v26" / "ic_launcher_round.xml"
    xml = _read_text(adaptive_xml, root)
    round_text = _read_text(round_xml, root)
    _require(round_text == xml, "Adaptive legacy and round XML contents differ")
    adaptive_root = _parse_xml(xml, "adaptive icon XML")
    _require(adaptive_root.tag == "adaptive-icon", "Adaptive icon root must be <adaptive-icon>")

    background = _single_child(adaptive_root, "background", "Adaptive icon")
    _require_android_attribute(
        background,
        "drawable",
        "@drawable/ic_launcher_background",
        "Adaptive <background>",
    )

    foreground = _single_child(adaptive_root, "foreground", "Adaptive icon")
    foreground_inset = _single_child(foreground, "inset", "Adaptive <foreground>")
    _require_android_attribute(
        foreground_inset,
        "drawable",
        "@drawable/ic_launcher_foreground",
        "Adaptive <foreground><inset>",
    )
    _require_android_attribute(
        foreground_inset,
        "inset",
        "0%",
        "Adaptive <foreground><inset>",
    )

    monochrome = _single_child(adaptive_root, "monochrome", "Adaptive icon")
    monochrome_inset = _single_child(monochrome, "inset", "Adaptive <monochrome>")
    _require_android_attribute(
        monochrome_inset,
        "drawable",
        "@drawable/ic_launcher_monochrome",
        "Adaptive <monochrome><inset>",
    )
    _require_android_attribute(
        monochrome_inset,
        "inset",
        "0%",
        "Adaptive <monochrome><inset>",
    )

    expected_paths: set[Path] = set()
    decoded_count = 0
    for density, size in LEGACY.items():
        launcher_path = res / f"mipmap-{density}" / "ic_launcher.png"
        round_path = res / f"mipmap-{density}" / "ic_launcher_round.png"
        expected_paths.update((launcher_path, round_path))
        launcher = _read_png(launcher_path, size, "RGB", root)
        round_icon = _read_png(round_path, size, "RGB", root)
        decoded_count += 2
        _require(
            launcher.tobytes() == round_icon.tobytes(),
            f"{_relative(round_path, root)} content differs from the legacy icon",
        )
        _require_color_mark(launcher, _relative(launcher_path, root), transparent=False)

    for density, size in ADAPTIVE.items():
        directory = res / f"drawable-{density}"
        background_path = directory / "ic_launcher_background.png"
        foreground_path = directory / "ic_launcher_foreground.png"
        monochrome_path = directory / "ic_launcher_monochrome.png"
        expected_paths.update((background_path, foreground_path, monochrome_path))
        background = _read_png(background_path, size, "RGB", root)
        foreground = _read_png(foreground_path, size, "RGBA", root)
        monochrome = _read_png(monochrome_path, size, "RGBA", root)
        decoded_count += 3
        _require_brand_background(background, _relative(background_path, root))
        _require_color_mark(foreground, _relative(foreground_path, root), transparent=True)
        _require_monochrome(monochrome, _relative(monochrome_path, root))

    actual_paths = set(res.glob("**/ic_launcher*.png"))
    _require(actual_paths == expected_paths, "Launcher PNG resource set is not exactly the expected 25 files")
    _require(decoded_count == 25, f"Decoded {decoded_count} launcher PNGs, expected 25")

    play_path = root / "docs" / "images" / "branding" / "sitemark-play-icon.png"
    play = _read_png(play_path, 512, "RGBA", root)
    _require(play.getchannel("A").getextrema() == (255, 255), "Play icon must be fully opaque")
    _require(play.info.get("srgb") == 0, "Play icon must declare sRGB rendering intent 0")
    _require_color_mark(play, _relative(play_path, root), transparent=False)
    return decoded_count


def _parse_args(argv: list[str] | None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Verify SiteMark launcher icon resources")
    parser.add_argument("--root", type=Path, default=DEFAULT_ROOT, help="repository root")
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = _parse_args(argv)
    try:
        count = verify_launcher_icon_resources(args.root)
    except VerificationError as error:
        print(f"Launcher icon verification failed: {error}", file=sys.stderr)
        return 1
    print(f"Launcher icon resources verified: {count} PNG resources and Play icon verified")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
