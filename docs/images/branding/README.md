# SiteMark launcher icon assets

The editable source is `sitemark-icon-master.svg`. Generated Android inputs live
under `assets/branding/`; the Google Play upload asset is
`sitemark-play-icon.png`.

On Windows, regenerate all source and Android launcher assets from the repository
root with:

```powershell
pwsh.exe -NoLogo -NoProfile -File tool/generate_launcher_icons.ps1
```

The geometry is intentionally code-generated: the lens stays at `(54, 54)` on a
`108 × 108 dp` artboard, and the foreground stays inside the central `66 × 66 dp`
safe zone.
