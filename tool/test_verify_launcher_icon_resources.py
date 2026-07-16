from __future__ import annotations

import shutil
import subprocess
import sys
import tempfile
import unittest
from collections.abc import Callable
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
VERIFIER = ROOT / "tool" / "verify_launcher_icon_resources.py"


class LauncherIconResourceVerifierTest(unittest.TestCase):
    def _fixture(self, parent: Path) -> Path:
        root = parent / "fixture"
        manifest = root / "android" / "app" / "src" / "main" / "AndroidManifest.xml"
        manifest.parent.mkdir(parents=True)
        shutil.copy2(
            ROOT / "android" / "app" / "src" / "main" / "AndroidManifest.xml",
            manifest,
        )
        shutil.copytree(
            ROOT / "android" / "app" / "src" / "main" / "res",
            root / "android" / "app" / "src" / "main" / "res",
        )
        play = root / "docs" / "images" / "branding" / "sitemark-play-icon.png"
        play.parent.mkdir(parents=True)
        shutil.copy2(ROOT / "docs" / "images" / "branding" / "sitemark-play-icon.png", play)
        return root

    def _run(self, root: Path, optimized: bool) -> subprocess.CompletedProcess[str]:
        command = [sys.executable]
        if optimized:
            command.append("-O")
        command.extend((str(VERIFIER), "--root", str(root)))
        return subprocess.run(
            command,
            cwd=ROOT,
            text=True,
            capture_output=True,
            check=False,
        )

    def _rewrite_adaptive_pair(self, root: Path, transform: Callable[[str], str]) -> None:
        directory = root / "android/app/src/main/res/mipmap-anydpi-v26"
        for name in ("ic_launcher.xml", "ic_launcher_round.xml"):
            path = directory / name
            original = path.read_text(encoding="utf-8")
            updated = transform(original)
            self.assertNotEqual(updated, original)
            path.write_text(updated, encoding="utf-8")

    def test_real_resources_pass_in_normal_and_optimized_python(self) -> None:
        for optimized in (False, True):
            with self.subTest(optimized=optimized):
                result = self._run(ROOT, optimized)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertIn("25 PNG resources and Play icon verified", result.stdout)

    def test_corrupt_fixtures_fail_in_normal_and_optimized_python(self) -> None:
        def blank_foreground(root: Path) -> None:
            path = root / "android/app/src/main/res/drawable-xxxhdpi/ic_launcher_foreground.png"
            Image.new("RGBA", (432, 432), (0, 0, 0, 0)).save(path)

        def old_flutter_legacy(root: Path) -> None:
            for name in ("ic_launcher.png", "ic_launcher_round.png"):
                path = root / f"android/app/src/main/res/mipmap-mdpi/{name}"
                image = Image.new("RGB", (48, 48), (3, 169, 244))
                ImageDraw.Draw(image).polygon(((12, 24), (26, 10), (38, 22), (26, 36)), fill="white")
                image.save(path)

        def remove_monochrome_cutouts(root: Path) -> None:
            path = root / "android/app/src/main/res/drawable-xxxhdpi/ic_launcher_monochrome.png"
            with Image.open(path).convert("RGBA") as image:
                draw = ImageDraw.Draw(image)
                draw.ellipse((152, 152, 280, 280), fill=(255, 255, 255, 255))
                draw.ellipse((282, 154, 310, 182), fill=(255, 255, 255, 255))
                image.save(path)

        def mismatch_round_icon(root: Path) -> None:
            path = root / "android/app/src/main/res/mipmap-xxxhdpi/ic_launcher_round.png"
            with Image.open(path).convert("RGB") as image:
                image.putpixel((0, 0), (255, 255, 255))
                image.save(path)

        def wrong_monochrome_inset(root: Path) -> None:
            self._rewrite_adaptive_pair(
                root,
                lambda text: text.replace(
                    'android:drawable="@drawable/ic_launcher_monochrome"\n          android:inset="0%"',
                    'android:drawable="@drawable/ic_launcher_monochrome"\n          android:inset="12%"',
                ),
            )

        def wrong_monochrome_drawable_hidden_by_comment(root: Path) -> None:
            self._rewrite_adaptive_pair(
                root,
                lambda text: text.replace(
                    '@drawable/ic_launcher_monochrome',
                    '@drawable/not_launcher_monochrome',
                    1,
                ).replace(
                    "  <monochrome>",
                    "  <!-- @drawable/ic_launcher_monochrome -->\n  <monochrome>",
                ),
            )

        def wrong_manifest_icon_hidden_by_comment(root: Path) -> None:
            path = root / "android/app/src/main/AndroidManifest.xml"
            text = path.read_text(encoding="utf-8")
            text = text.replace(
                'android:icon="@mipmap/ic_launcher"',
                'android:icon="@mipmap/not_launcher"',
                1,
            ).replace(
                "    <application",
                '    <!-- android:icon="@mipmap/ic_launcher" -->\n    <application',
            )
            path.write_text(text, encoding="utf-8")

        def foreground_values_only_on_wrong_node(root: Path) -> None:
            self._rewrite_adaptive_pair(
                root,
                lambda text: text.replace(
                    '@drawable/ic_launcher_foreground',
                    '@drawable/not_launcher_foreground',
                ).replace(
                    "</adaptive-icon>",
                    '  <metadata android:drawable="@drawable/ic_launcher_foreground" '
                    'android:inset="0%" />\n</adaptive-icon>',
                ),
            )

        corruptions = {
            "blank foreground": blank_foreground,
            "old Flutter legacy": old_flutter_legacy,
            "missing monochrome cutouts": remove_monochrome_cutouts,
            "legacy round mismatch": mismatch_round_icon,
            "wrong monochrome inset": wrong_monochrome_inset,
            "wrong monochrome drawable hidden by comment": wrong_monochrome_drawable_hidden_by_comment,
            "wrong manifest icon hidden by comment": wrong_manifest_icon_hidden_by_comment,
            "foreground values only on wrong node": foreground_values_only_on_wrong_node,
        }
        for name, corrupt in corruptions.items():
            for optimized in (False, True):
                with self.subTest(corruption=name, optimized=optimized):
                    with tempfile.TemporaryDirectory() as temp_dir:
                        root = self._fixture(Path(temp_dir))
                        corrupt(root)
                        result = self._run(root, optimized)
                        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
                        self.assertIn("Launcher icon verification failed:", result.stderr)


if __name__ == "__main__":
    unittest.main()
