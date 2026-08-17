# Edition artwork

Public-domain paintings (Met open access, CC0) used as the hero plate at the top of
each edition. `HeroArtworkCatalog` picks one per edition by mood + date; the asset name
here is what `HeroArtwork.assetName` refers to.

## Crop to the canvas, with no padding

The hero renders with `aspectRatio(contentMode: .fill)` into a wide, short plate, so any
letterboxing baked into the file shows up as black bars beside the painting — the layout
can't distinguish padding from paint.

Museum downloads often arrive matted onto a fixed canvas: ten of the original twelve
files here carried black borders (up to 44px on the Renoir), which is exactly how those
bars appeared. Before adding a painting, **crop it to the artwork itself** — no black
surround, no mat, no frame.

Quick check for a file you're about to add:

```python
from PIL import Image
im = Image.open(path).convert("L"); w, h = im.size; px = im.load()
edge = lambda vals: sum(vals) / len(vals)
print(edge([px[0, y] for y in range(0, h, 2)]),      # left
      edge([px[w - 1, y] for y in range(0, h, 2)]),  # right
      edge([px[x, 0] for x in range(0, w, 2)]),      # top
      edge([px[x, h - 1] for x in range(0, w, 2)]))  # bottom
```

A mean below ~12 on any edge means a black border — unless the painting is genuinely
dark there (Turner's *Whalers* reads 9.7 on its first column and jumps to 55 by the
third; padding stays flat at 0 for dozens of columns).
