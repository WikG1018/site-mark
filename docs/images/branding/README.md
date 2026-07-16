# SiteMark launcher icon assets

The shared declarative scene in `tool/generate_launcher_icon.py` is the source of
truth for geometry and palette. It deterministically emits the PNG inputs under
`assets/branding/`, the Google Play upload asset `sitemark-play-icon.png`, and
the editable vector companion `sitemark-icon-master.svg` from that same scene.

The SVG is a derived, editable handoff artifact; the PNG files are rendered by
Pillow from the shared scene rather than rasterized from the SVG file itself.
If an SVG edit should become a production change, apply the corresponding scene
change and regenerate every output so the vector and raster versions stay in sync.

On Windows, regenerate all source and Android launcher assets from the repository
root with:

```powershell
python -m pip install -r tool/icon-requirements.txt
pwsh.exe -NoLogo -NoProfile -File tool/generate_launcher_icons.ps1
```

The geometry is intentionally scene-generated: the lens stays at `(54, 54)` on
a `108 × 108 dp` artboard, and the foreground stays inside the central
`66 × 66 dp` safe zone. The wrapper finishes by verifying all 25 Android PNGs
and the Play PNG, and exits unsuccessfully if any resource violates the contract.
