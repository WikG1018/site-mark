from pathlib import Path

replacements = [
    ("v1.0.25", "v1.0.26"),
    ("1.0.25+40", "1.0.26+41"),
]

for name in ("README.md", "README_EN.md", "pubspec.yaml"):
    path = Path(name)
    text = path.read_text(encoding="utf-8")
    original = text
    for old, new in replacements:
        text = text.replace(old, new)
    if text != original:
        path.write_text(text, encoding="utf-8")
        print(f"updated {name}")
    else:
        print(f"unchanged {name}")

# Guard: no leftover v1.0.25 download URLs mixed with new filenames
for name in ("README.md", "README_EN.md"):
    text = Path(name).read_text(encoding="utf-8")
    if "v1.0.25/sitemark-v1.0.26" in text or "v1.0.26/sitemark-v1.0.25" in text:
        raise SystemExit(f"corrupted version mix in {name}")
    if "1.0.25" in text:
        print(f"note: leftover 1.0.25 mention in {name}")
print("pubspec:", [l for l in Path("pubspec.yaml").read_text().splitlines() if l.startswith("version:")])
