from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter, PngImagePlugin


Color = tuple[int, int, int]
Point = tuple[float, float]
Bounds = tuple[float, float, float, float]


@dataclass(frozen=True)
class RoundedRectangle:
    bounds: Bounds
    radius: float


@dataclass(frozen=True)
class Circle:
    center: Point
    radius: float
    color: Color


@dataclass(frozen=True)
class Polyline:
    points: tuple[Point, ...]
    width: float


@dataclass(frozen=True)
class IconScene:
    artboard: float
    safe_zone: Bounds
    camera_body: RoundedRectangle
    camera_bump: RoundedRectangle
    lens: Circle
    letter: Polyline
    red_dot: Circle
    background_stops: tuple[Color, Color, Color]
    glass_stops: tuple[Color, Color, Color]
    letter_stops: tuple[Color, Color, Color]


SCENE = IconScene(
    artboard=108.0,
    safe_zone=(21.0, 21.0, 87.0, 87.0),
    camera_body=RoundedRectangle((21.0, 32.0, 87.0, 80.0), 9.0),
    camera_bump=RoundedRectangle((43.0, 25.0, 65.0, 38.0), 4.0),
    lens=Circle((54.0, 54.0), 16.0, (10, 73, 61)),
    letter=Polyline(
        ((45.0, 62.0), (45.0, 46.0), (54.0, 56.0), (63.0, 46.0), (63.0, 62.0)),
        4.2,
    ),
    red_dot=Circle((74.0, 42.0), 3.5, (255, 77, 79)),
    background_stops=((9, 47, 42), (23, 107, 85), (37, 141, 109)),
    glass_stops=((255, 255, 255), (208, 255, 235), (119, 229, 182)),
    letter_stops=((246, 255, 251), (217, 255, 240), (147, 242, 201)),
)

# Public acceptance constants remain available for tooling and documentation,
# but every value is derived from the single scene used by both renderers.
ARTBOARD_DP = SCENE.artboard
SAFE_ZONE_DP = SCENE.safe_zone
CAMERA_BODY_DP = SCENE.camera_body.bounds
CAMERA_BUMP_DP = SCENE.camera_bump.bounds
CAMERA_BOUNDS_DP = (
    min(CAMERA_BODY_DP[0], CAMERA_BUMP_DP[0]),
    min(CAMERA_BODY_DP[1], CAMERA_BUMP_DP[1]),
    max(CAMERA_BODY_DP[2], CAMERA_BUMP_DP[2]),
    max(CAMERA_BODY_DP[3], CAMERA_BUMP_DP[3]),
)
LENS_CENTER_DP = SCENE.lens.center
LENS_RADIUS_DP = SCENE.lens.radius
RED_DOT_CENTER_DP = SCENE.red_dot.center
RED_DOT_RADIUS_DP = SCENE.red_dot.radius
M_POINTS_DP = SCENE.letter.points
BACKGROUND_STOPS = SCENE.background_stops
GLASS_STOPS = SCENE.glass_stops
M_STOPS = SCENE.letter_stops


def _px(value: float, size: int) -> int:
    return round(value / SCENE.artboard * size)


def _rect_px(rect: tuple[float, float, float, float], size: int) -> tuple[int, int, int, int]:
    return tuple(_px(value, size) for value in rect)


def _circle_box(center: tuple[float, float], radius: float, size: int) -> tuple[int, int, int, int]:
    x, y = center
    return _rect_px((x - radius, y - radius, x + radius, y + radius), size)


def _mix(start: int, end: int, amount: float) -> int:
    return round(start + (end - start) * amount)


def _three_stop_gradient(size: int, stops: tuple[tuple[int, int, int], ...]) -> Image.Image:
    vertical = Image.linear_gradient("L").resize((size, size))
    horizontal = vertical.transpose(Image.Transpose.TRANSPOSE)
    ramp = Image.blend(horizontal, vertical, 0.5)
    channels: list[Image.Image] = []
    for channel_index in range(3):
        values: list[int] = []
        for index in range(256):
            amount = index / 255
            if amount <= 0.5:
                value = _mix(stops[0][channel_index], stops[1][channel_index], amount * 2)
            else:
                value = _mix(stops[1][channel_index], stops[2][channel_index], (amount - 0.5) * 2)
            values.append(value)
        channels.append(ramp.point(values))
    return Image.merge("RGB", channels).convert("RGBA")


def _deterministic_noise(size: int) -> Image.Image:
    state = 0x53_49_54_45
    pixels = bytearray(size * size)
    for index in range(len(pixels)):
        state = (1_664_525 * state + 1_013_904_223) & 0xFFFF_FFFF
        pixels[index] = state >> 24
    return Image.frombytes("L", (size, size), bytes(pixels))


def _camera_mask(size: int) -> Image.Image:
    mask = Image.new("L", (size, size), 0)
    draw = ImageDraw.Draw(mask)
    for primitive in (SCENE.camera_body, SCENE.camera_bump):
        draw.rounded_rectangle(
            _rect_px(primitive.bounds, size),
            radius=_px(primitive.radius, size),
            fill=255,
        )
    return mask


def _rounded_polyline_mask(size: int) -> Image.Image:
    mask = Image.new("L", (size, size), 0)
    draw = ImageDraw.Draw(mask)
    points = [(_px(x, size), _px(y, size)) for x, y in SCENE.letter.points]
    width = _px(SCENE.letter.width, size)
    radius = width // 2
    draw.line(points, fill=255, width=width, joint="curve")
    for x, y in points:
        draw.ellipse((x - radius, y - radius, x + radius, y + radius), fill=255)
    return mask


def render_background(size: int) -> Image.Image:
    return _three_stop_gradient(size, SCENE.background_stops)


def render_foreground(size: int, monochrome: bool = False) -> Image.Image:
    camera_mask = _camera_mask(size)
    lens_box = _circle_box(SCENE.lens.center, SCENE.lens.radius, size)
    red_dot_box = _circle_box(SCENE.red_dot.center, SCENE.red_dot.radius, size)
    m_mask = _rounded_polyline_mask(size)

    if monochrome:
        alpha = camera_mask.copy()
        alpha_draw = ImageDraw.Draw(alpha)
        alpha_draw.ellipse(lens_box, fill=0)
        alpha_draw.ellipse(red_dot_box, fill=0)
        result = Image.new("RGBA", (size, size), (255, 255, 255, 0))
        result.putalpha(alpha)
        m_layer = Image.new("RGBA", (size, size), (255, 255, 255, 0))
        m_layer.putalpha(m_mask)
        result.alpha_composite(m_layer)
        return result

    result = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    glass = _three_stop_gradient(size, SCENE.glass_stops)
    noise = _deterministic_noise(size).filter(
        ImageFilter.GaussianBlur(_px(0.8, size))
    )
    noise_alpha = noise.point(lambda value: max(118, min(178, round(118 + value * 0.24))))
    glass.putalpha(ImageChops.multiply(camera_mask, noise_alpha))
    result.alpha_composite(glass)

    softened = camera_mask.filter(ImageFilter.GaussianBlur(_px(0.9, size)))
    edge = ImageChops.subtract(camera_mask, softened).point(lambda value: min(255, value * 4))
    highlight_region = Image.new("L", (size, size), 0)
    highlight_draw = ImageDraw.Draw(highlight_region)
    highlight_draw.ellipse(_rect_px((14.0, 15.0, 70.0, 58.0), size), fill=168)
    highlight_region = highlight_region.filter(ImageFilter.GaussianBlur(_px(7.5, size)))
    edge = ImageChops.multiply(edge, highlight_region)
    highlight = Image.new("RGBA", (size, size), (255, 255, 255, 0))
    highlight.putalpha(edge)
    result.alpha_composite(highlight)

    draw = ImageDraw.Draw(result)
    draw.ellipse(lens_box, fill=(*SCENE.lens.color, 196))

    m_layer = _three_stop_gradient(size, SCENE.letter_stops)
    m_layer.putalpha(m_mask)
    result.alpha_composite(m_layer)

    draw = ImageDraw.Draw(result)
    draw.ellipse(red_dot_box, fill=(*SCENE.red_dot.color, 255))
    highlight_radius = SCENE.red_dot.radius * 0.34
    highlight_center = (
        SCENE.red_dot.center[0] - SCENE.red_dot.radius * 0.28,
        SCENE.red_dot.center[1] - SCENE.red_dot.radius * 0.28,
    )
    draw.ellipse(
        _circle_box(highlight_center, highlight_radius, size),
        fill=(255, 151, 152, 190),
    )
    return result


def render_full_icon(size: int) -> Image.Image:
    result = render_background(size)
    result.alpha_composite(render_foreground(size))
    return result.convert("RGB")


def _svg_number(value: float) -> str:
    return f"{value:g}"


def _svg_color(color: Color) -> str:
    return "#" + "".join(f"{channel:02X}" for channel in color)


def _svg_stops(colors: tuple[Color, Color, Color], opacities: tuple[float, ...] | None = None) -> str:
    offsets = ("0", "0.5", "1")
    lines: list[str] = []
    for index, (offset, color) in enumerate(zip(offsets, colors)):
        opacity = "" if opacities is None else f' stop-opacity="{_svg_number(opacities[index])}"'
        lines.append(f'      <stop offset="{offset}" stop-color="{_svg_color(color)}"{opacity}/>')
    return "\n".join(lines)


def _svg_rounded_rectangle(identifier: str, primitive: RoundedRectangle) -> str:
    left, top, right, bottom = primitive.bounds
    return (
        f'<rect id="{identifier}" x="{_svg_number(left)}" y="{_svg_number(top)}" '
        f'width="{_svg_number(right - left)}" height="{_svg_number(bottom - top)}" '
        f'rx="{_svg_number(primitive.radius)}" fill="#FFFFFF"/>'
    )


def build_master_svg() -> str:
    points = " ".join(f"{_svg_number(x)},{_svg_number(y)}" for x, y in SCENE.letter.points)
    return f"""<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg" width="1080" height="1080" viewBox="0 0 108 108">
  <defs>
    <linearGradient id="background" x1="0" y1="0" x2="1" y2="1">
{_svg_stops(SCENE.background_stops)}
    </linearGradient>
    <linearGradient id="glass" x1="0" y1="0" x2="1" y2="1">
{_svg_stops(SCENE.glass_stops, (0.78, 0.40, 0.25))}
    </linearGradient>
    <linearGradient id="letter" x1="0" y1="0" x2="1" y2="1">
{_svg_stops(SCENE.letter_stops)}
    </linearGradient>
    <mask id="camera-mask" maskUnits="userSpaceOnUse" x="0" y="0" width="108" height="108">
      {_svg_rounded_rectangle("camera-body", SCENE.camera_body)}
      {_svg_rounded_rectangle("camera-bump", SCENE.camera_bump)}
    </mask>
    <filter id="frost" x="-20%" y="-20%" width="140%" height="140%">
      <feTurbulence type="fractalNoise" baseFrequency="0.03" numOctaves="2" seed="7" result="noise"/>
      <feDisplacementMap in="SourceGraphic" in2="noise" scale="0.7"/>
      <feGaussianBlur stdDeviation="0.08"/>
    </filter>
  </defs>
  <rect width="108" height="108" fill="url(#background)"/>
  <rect id="camera-glass" width="108" height="108" fill="url(#glass)" mask="url(#camera-mask)" filter="url(#frost)"/>
  <circle id="lens" cx="{_svg_number(SCENE.lens.center[0])}" cy="{_svg_number(SCENE.lens.center[1])}" r="{_svg_number(SCENE.lens.radius)}" fill="{_svg_color(SCENE.lens.color)}" fill-opacity="0.77"/>
  <polyline id="letter-m" points="{points}" fill="none" stroke="url(#letter)" stroke-width="{_svg_number(SCENE.letter.width)}" stroke-linecap="round" stroke-linejoin="round"/>
  <circle id="red-dot" cx="{_svg_number(SCENE.red_dot.center[0])}" cy="{_svg_number(SCENE.red_dot.center[1])}" r="{_svg_number(SCENE.red_dot.radius)}" fill="{_svg_color(SCENE.red_dot.color)}"/>
</svg>
"""


def write_assets(root: Path) -> dict[str, Path]:
    branding = root / "assets" / "branding"
    docs_branding = root / "docs" / "images" / "branding"
    branding.mkdir(parents=True, exist_ok=True)
    docs_branding.mkdir(parents=True, exist_ok=True)

    paths = {
        "legacy": branding / "sitemark-icon.png",
        "background": branding / "sitemark-icon-background.png",
        "foreground": branding / "sitemark-icon-foreground.png",
        "monochrome": branding / "sitemark-icon-monochrome.png",
        "master_svg": docs_branding / "sitemark-icon-master.svg",
        "play": docs_branding / "sitemark-play-icon.png",
    }
    render_full_icon(1024).save(paths["legacy"], optimize=True)
    render_background(432).convert("RGB").save(paths["background"], optimize=True)
    render_foreground(432).save(paths["foreground"], optimize=True)
    render_foreground(432, monochrome=True).save(paths["monochrome"], optimize=True)
    play_png_info = PngImagePlugin.PngInfo()
    play_png_info.add(b"sRGB", b"\x00")
    render_full_icon(512).convert("RGBA").save(
        paths["play"],
        optimize=True,
        pnginfo=play_png_info,
    )
    paths["master_svg"].write_text(build_master_svg(), encoding="utf-8")
    return paths


if __name__ == "__main__":
    repository_root = Path(__file__).resolve().parents[1]
    for name, path in write_assets(repository_root).items():
        print(f"{name}: {path}")
