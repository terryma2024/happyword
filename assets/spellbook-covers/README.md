# assets/spellbook-covers — design source for Spellbook covers

This folder holds Recraft V4 Vector SVG source files for V0.9.5 Spellbook cover art.
The shipped 128x128 transparent PNG derivatives live under
`harmonyos/entry/src/main/resources/rawfile/spellbook_covers/`.

| File | Used by | Notes |
| --- | --- | --- |
| `default.svg` | Unknown / missing pack cover fallback | Generated with Recraft V4 Vector on 2026-05-29; transparent background. |
| `fruit-forest.svg` | Built-in `fruit-forest` pack | Generated with Recraft V4 Vector on 2026-05-29; transparent background. |
| `school-castle.svg` | Built-in `school-castle` pack | Generated with Recraft V4 Vector on 2026-05-29; transparent background. |
| `home-cottage.svg` | Built-in `home-cottage` pack | Generated with Recraft V4 Vector on 2026-05-29; transparent background. |
| `animal-safari.svg` | Built-in `animal-safari` pack | Generated with Recraft V4 Vector on 2026-05-29; transparent background. |
| `ocean-realm.svg` | Built-in `ocean-realm` pack | Generated with Recraft V4 Vector on 2026-05-29; transparent background. |

Re-rasterize a cover with:

```bash
magick -background none assets/spellbook-covers/<name>.svg \
  -resize 128x128 -gravity center -extent 128x128 -depth 8 \
  harmonyos/entry/src/main/resources/rawfile/spellbook_covers/<name>.png
```
