# DMG window artwork

Source and specs for the MagicWall installer window.

## Files

| File | Purpose |
|---|---|
| `background.html` | Design source, rendered at 660 × 420 CSS px |
| `render-background.sh` | Regenerates the PNGs with headless Chrome + `sips` |
| `background.png` | 660 × 420 px, 72 dpi — 1× background |
| `background@2x.png` | 1320 × 840 px, 144 dpi — 2× background |

The committed PNGs are what the release uses. `render-background.sh` is only
needed when changing the artwork.

## Layout

`Scripts/dmg-settings.py` builds the Finder window with:

- window bounds **660 × 448 pt** (660 × 420 pt content + Finder title bar);
- icons **128 pt**, labels **14 pt**;
- app icon at **(180, 200)**, Applications link at **(480, 200)** — Finder
  coordinates are points from the top-left of the content area;
- background **660 × 420 pt**, with its pixel coordinates exactly 2× the point
  coordinates in the @2x file.

Keep the instruction and the icon labels above roughly y=300. Finder's title bar
and the optional path bar can cover the bottom of the background; the brick
pattern and the small caption below that line are decorative on purpose.

The background must not contain the app or Applications icons: those are real
files placed by Finder. The arrow and instruction are the only guidance.

## Regenerating

```bash
./Scripts/dmg/render-background.sh
```

Requires Google Chrome. The script fails if the output is not exactly
660 × 420 or 1320 × 840. It also stamps 72/144 dpi, which Finder uses to decide
the point size of the image.

Do **not** add `hide_extensions` to `dmg-settings.py`: `SetFile -a E` would
attach `com.apple.FinderInfo` to the signed app bundle and
`codesign --verify --strict` would reject it. Finder already hides the `.app`
extension.

## Preview

```bash
./Scripts/build-dmg.sh \
  build/release/Build/Products/Release/MagicWall.app \
  /tmp/MagicWall-preview.dmg \
  0.5.0
open /tmp/MagicWall-preview.dmg
```
