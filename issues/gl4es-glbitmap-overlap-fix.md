# gl4es: `glBitmap` erases neighboring glyphs where bounding boxes overlap

Patch: [`gl4es-glbitmap-overlap-fix.patch`](gl4es-glbitmap-overlap-fix.patch)
(applies to gl4es `src/gl/raster.c`, `gl4es_glBitmap()`).

## Symptom

Bitmap text drawn through gl4es one `glBitmap` per character loses pixels
along each glyph's right edge. With an oblique (italic) font the effect is
dramatic: the tops of glyphs — which lean right, into the next character's
cell — get visibly clipped, and the whole face reads a weight lighter than
the font data.

Concrete example: freeglut's SGI-style menus drawing Helvetica Bold
Oblique 14 (`helvBO14_bdf`, from the sgi-demos project). The word "Flat"
at 2x pixel zoom rendered like this — note the top bar of the `F`, which
should be 7 font pixels (14 device pixels) wide, truncated to 5 (10):

```
   rendered (broken)                     font data ('F', 10x11)
   ##########......####                  ...#######
   ##########......####                  ...##.....
   ####............####                  ...##.....
   ####............####                  ..##......
   ####..........####                    ..##......
   ####..........####                    ..######..
   ...                                    .##.......
```

Exactly the bits in the glyph's *second byte* (columns 8–9) disappeared —
the columns that fall under the *next* character's bounding box.

## Root cause

`gl4es_glBitmap()` does not draw immediately; it composites each bitmap
into a CPU-side RGBA accumulation buffer (`glstate->raster.bitmap`) that
is flushed to the GL as a single textured quad later (`bitmap_flush()`).
The compositing loop wrote a value for **every** pixel of the bitmap's
rectangle:

```c
int p = (b & (1 << (7 - (bx % 8)))) ? 1 : 0;
*to++ = col[0]*p;   // writes 0 when the bit is 0
*to++ = col[1]*p;
*to++ = col[2]*p;
*to++ = col[3]*p;   // alpha 0, but it OVERWRITES what was there
```

For unset bits this stores transparent black — *overwriting* whatever an
earlier `glBitmap` in the same batch had already put at that location.

That is not what `glBitmap` does. Per the OpenGL specification, a bitmap
only produces fragments where the bitmap bit is 1; zero bits leave the
framebuffer untouched:

> "These fragments are generated using the current raster position [...]
> A fragment is produced for each bit set to 1 in the bitmap."

The bug is invisible as long as consecutive bitmaps don't overlap. But
font glyphs routinely do: a glyph's advance is usually smaller than its
bounding box (kerning, and especially oblique/italic shear, where the box
leans right over the next character's cell). Each character's blank left
margin then erases the right edge of the character drawn before it. The
loss is systematic — every pair of adjacent glyphs — which is why the
whole face looks thinned rather than randomly corrupted.

A single glyph drawn alone renders perfectly, which is what makes the bug
easy to misattribute to the font data or the caller.

## Fix

Skip unset bits instead of writing zeros, in both compositing loops (the
`raster_need_transform()` variant and the plain one):

```c
if (b & (1 << (7 - (bx % 8)))) {
    *to++ = col[0];
    *to++ = col[1];
    *to++ = col[2];
    *to++ = col[3];
} else
    to += 4;
```

The accumulation buffer is zero-initialized when a batch starts
(`bm_drawing == 0` path does a `memset`), so pixels never touched by any
bitmap still composite as transparent — the flush/blend behavior of
`bitmap_flush()` is unchanged. The only difference is that a zero bit no
longer clobbers a previously set pixel, matching the spec.

`glDrawPixels(..., GL_BITMAP, ...)` routes through the same function and
is fixed as well. Nothing else reads the skipped pixels' previous values,
so there is no behavior change for non-overlapping bitmaps.

## Verification

- **Probe**: a minimal GLUT program drawing the `F` glyph alone via
  `glBitmap` at zoom 1 and zoom 2 rendered correctly before *and* after
  the fix — confirming the corruption needs two overlapping calls.
- **Pixel readback**: rendering the menu label "Flat" at 2x zoom and
  ASCII-dumping the framebuffer. Before: `F` top bar 10 device pixels,
  with the two source columns under `l`'s box missing. After: all glyphs
  match the BDF source data pixel-for-pixel (bar full 14 device pixels,
  `a` and `t` crossbars complete).
- Exercised through both the macOS/ANGLE native stack and the Emscripten
  WebGL build of gl4es.

## Applying

```sh
cd gl4es
git apply /path/to/gl4es-glbitmap-overlap-fix.patch
./build-all.sh
```

The fix is candidate material for upstream (ptitSeb/gl4es): it corrects
`glBitmap` semantics for any application drawing multi-character bitmap
text, not just freeglut's menus.
