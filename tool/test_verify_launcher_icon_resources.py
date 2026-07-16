from __future__ import annotations

import shutil
import subprocess
import sys
import tempfile
import unittest
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

        corruptions = {
            "blank foreground": blank_foreground,
            "old Flutter legacy": old_flutter_legacy,
            "missing monochrome cutouts": remove_monochrome_cutouts,
            "legacy round mismatch": mismatch_round_icon,
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
