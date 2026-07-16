from __future__ import annotations

import textwrap
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter

ARTBOARD_DP = 108.0
SAFE_ZONE_DP = (21.0, 21.0, 87.0, 87.0)
CAMERA_BOUNDS_DP = (21.0, 25.0, 87.0, 80.0)
CAMERA_BODY_DP = (21.0, 32.0, 87.0, 80.0)
CAMERA_BUMP_DP = (43.0, 25.0, 65.0, 38.0)
LENS_CENTER_DP = (54.0, 54.0)
LENS_RADIUS_DP = 16.0
RED_DOT_CENTER_DP = (74.0, 42.0)
RED_DOT_RADIUS_DP = 3.5
M_POINTS_DP = ((45.0, 62.0), (45.0, 46.0), (54.0, 56.0), (63.0, 46.0), (63.0, 62.0))

BACKGROUND_STOPS = ((9, 47, 42), (23, 107, 85), (37, 141, 109))
GLASS_STOPS = ((255, 255, 255), (208, 255, 235), (119, 229, 182))
M_STOPS = ((246, 255, 251), (217, 255, 240), (147, 242, 201))


def _px(value: float, size: int) -> int:
    return round(value / ARTBOARD_DP * size)


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


def _camera_mask(size: int) -> Image.Image:
    mask = Image.new("L", (size, size), 0)
    draw = ImageDraw.Draw(mask)
    draw.rounded_rectangle(
        _rect_px(CAMERA_BODY_DP, size),
        radius=_px(9.0, size),
        fill=255,
    )
    draw.rounded_rectangle(
        _rect_px(CAMERA_BUMP_DP, size),
        radius=_px(4.0, size),
        fill=255,
    )
    return mask


def _rounded_polyline_mask(size: int) -> Image.Image:
    mask = Image.new("L", (size, size), 0)
    draw = ImageDraw.Draw(mask)
    points = [(_px(x, size), _px(y, size)) for x, y in M_POINTS_DP]
    width = _px(4.2, size)
    radius = width // 2
    draw.line(points, fill=255, width=width, joint="curve")
    for x, y in points:
        draw.ellipse((x - radius, y - radius, x + radius, y + radius), fill=255)
    return mask


def render_background(size: int) -> Image.Image:
    return _three_stop_gradient(size, BACKGROUND_STOPS)


def render_foreground(size: int, monochrome: bool = False) -> Image.Image:
    camera_mask = _camera_mask(size)
    lens_box = _circle_box(LENS_CENTER_DP, LENS_RADIUS_DP, size)
    red_dot_box = _circle_box(RED_DOT_CENTER_DP, RED_DOT_RADIUS_DP, size)
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
    glass = _three_stop_gradient(size, GLASS_STOPS)
    noise = Image.effect_noise((size, size), 18).filter(
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
    draw.ellipse(lens_box, fill=(10, 73, 61, 196))

    m_layer = _three_stop_gradient(size, M_STOPS)
    m_layer.putalpha(m_mask)
    result.alpha_composite(m_layer)

    draw = ImageDraw.Draw(result)
    draw.ellipse(red_dot_box, fill=(255, 77, 79, 255))
    highlight_radius = RED_DOT_RADIUS_DP * 0.34
    highlight_center = (
        RED_DOT_CENTER_DP[0] - RED_DOT_RADIUS_DP * 0.28,
        RED_DOT_CENTER_DP[1] - RED_DOT_RADIUS_DP * 0.28,
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


def build_master_svg() -> str:
    return textwrap.dedent(
        """\
        <?xml version="1.0" encoding="UTF-8"?>
        <svg xmlns="http://www.w3.org/2000/svg" width="1080" height="1080" viewBox="0 0 108 108">
          <defs>
            <linearGradient id="background" x1="0" y1="0" x2="1" y2="1">
              <stop offset="0" stop-color="#092F2A"/>
              <stop offset="0.55" stop-color="#176B55"/>
              <stop offset="1" stop-color="#258D6D"/>
            </linearGradient>
            <linearGradient id="glass" x1="0" y1="0" x2="1" y2="1">
              <stop offset="0" stop-color="#FFFFFF" stop-opacity="0.78"/>
              <stop offset="0.5" stop-color="#D0FFEB" stop-opacity="0.40"/>
              <stop offset="1" stop-color="#77E5B6" stop-opacity="0.25"/>
            </linearGradient>
            <linearGradient id="letter" x1="0" y1="0" x2="1" y2="1">
              <stop offset="0" stop-color="#F6FFFB"/>
              <stop offset="1" stop-color="#93F2C9"/>
            </linearGradient>
            <linearGradient id="highlight" x1="0" y1="0" x2="1" y2="1">
              <stop offset="0" stop-color="#FFFFFF" stop-opacity="0.55"/>
              <stop offset="0.75" stop-color="#FFFFFF" stop-opacity="0.16"/>
              <stop offset="1" stop-color="#FFFFFF" stop-opacity="0"/>
            </linearGradient>
            <filter id="frost" x="-20%" y="-20%" width="140%" height="140%">
              <feTurbulence type="fractalNoise" baseFrequency="0.03" numOctaves="2" seed="7" result="noise"/>
              <feDisplacementMap in="SourceGraphic" in2="noise" scale="0.7"/>
              <feGaussianBlur stdDeviation="0.08"/>
            </filter>
            <filter id="highlight-soft" x="-20%" y="-20%" width="140%" height="140%">
              <feGaussianBlur stdDeviation="0.18"/>
            </filter>
          </defs>
          <rect width="108" height="108" fill="url(#background)"/>
          <path d="M30 32H43L47 25H61L65 32H78A9 9 0 0 1 87 41V71A9 9 0 0 1 78 80H30A9 9 0 0 1 21 71V41A9 9 0 0 1 30 32Z" fill="url(#glass)" filter="url(#frost)"/>
          <path d="M24 58V42A7 7 0 0 1 31 35H42L47 28H59" fill="none" stroke="url(#highlight)" stroke-width="1.1" stroke-linecap="round" filter="url(#highlight-soft)"/>
          <circle cx="54" cy="54" r="16" fill="#0A493D" fill-opacity="0.77"/>
          <path d="M45 62V46L54 56L63 46V62" fill="none" stroke="url(#letter)" stroke-width="4.2" stroke-linecap="round" stroke-linejoin="round"/>
          <circle cx="74" cy="42" r="3.5" fill="#FF4D4F"/>
        </svg>
        """
    )


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
    render_full_icon(512).convert("RGBA").save(paths["play"], optimize=True)
    paths["master_svg"].write_text(build_master_svg(), encoding="utf-8")
    return paths


if __name__ == "__main__":
    repository_root = Path(__file__).resolve().parents[1]
    for name, path in write_assets(repository_root).items():
        print(f"{name}: {path}")
