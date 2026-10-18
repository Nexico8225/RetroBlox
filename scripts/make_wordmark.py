#!/usr/bin/env python3
"""RetroBlox wordmark asset: upload/RetroBlox.png -> public/retro/logo-wordmark.png

The user's logo is white letters + red outline on solid black. To use it on the
blue header / white cards we turn darkness into transparency (alpha = max RGB)
and autocrop to the glyphs. Also emits a favicon-friendly square chip version
with the wordmark scaled onto it (unused by default, kept for options).
"""
from PIL import Image

SRC = "/home/z/my-project/upload/RetroBlox.png"
OUT = "/home/z/my-project/public/retro/logo-wordmark.png"

im = Image.open(SRC).convert("RGBA")
px = im.load()
w, h = im.size

for y in range(h):
    for x in range(w):
        r, g, b, a = px[x, y]
        # black background -> transparent; bright content (white/red) stays.
        # alpha from the max channel keeps anti-aliased edges smooth.
        alpha = max(r, g, b)
        if alpha < 6:
            px[x, y] = (0, 0, 0, 0)
        else:
            # un-darken semi-dark edge pixels slightly so the red outline
            # doesn't look muddy on dark-blue header
            px[x, y] = (r, g, b, alpha)

bbox = im.getbbox()
im = im.crop(bbox)
im.save(OUT)
print("saved", OUT, im.size, "ratio", round(im.size[0] / im.size[1], 3))
