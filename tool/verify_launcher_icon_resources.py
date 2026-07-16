from __future__ import annotations

from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
RES = ROOT / "android" / "app" / "src" / "main" / "res"
LEGACY = {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}
ADAPTIVE = {"mdpi": 108, "hdpi": 162, "xhdpi": 216, "xxhdpi": 324, "xxxhdpi": 432}


def require_png(path: Path, size: int) -> None:
    assert path.exists(), f"Missing {path.relative_to(ROOT)}"
    with Image.open(path) as image:
        assert image.size == (size, size), (
            f"{path.relative_to(ROOT)} is {image.size}, expected {(size, size)}"
        )


def main() -> None:
    manifest = (ROOT / "android" / "app" / "src" / "main" / "AndroidManifest.xml").read_text(
        encoding="utf-8"
    )
    assert 'android:icon="@mipmap/ic_launcher"' in manifest
    assert 'android:roundIcon="@mipmap/ic_launcher_round"' in manifest

    adaptive_xml = RES / "mipmap-anydpi-v26" / "ic_launcher.xml"
    round_xml = RES / "mipmap-anydpi-v26" / "ic_launcher_round.xml"
    assert adaptive_xml.exists(), "Missing adaptive ic_launcher.xml"
    assert round_xml.exists(), "Missing adaptive ic_launcher_round.xml"
    xml = adaptive_xml.read_text(encoding="utf-8")
    for required in (
        "@drawable/ic_launcher_background",
        "@drawable/ic_launcher_foreground",
        "@drawable/ic_launcher_monochrome",
        'android:inset="0%"',
    ):
        assert required in xml, f"Missing {required} in adaptive icon XML"
    assert round_xml.read_text(encoding="utf-8") == xml

    for density, size in LEGACY.items():
        require_png(RES / f"mipmap-{density}" / "ic_launcher.png", size)
        require_png(RES / f"mipmap-{density}" / "ic_launcher_round.png", size)

    for density, size in ADAPTIVE.items():
        for name in (
            "ic_launcher_background.png",
            "ic_launcher_foreground.png",
            "ic_launcher_monochrome.png",
        ):
            require_png(RES / f"drawable-{density}" / name, size)

    print("Launcher icon resources verified")


if __name__ == "__main__":
    main()
