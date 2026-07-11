# glRasterPos3f rejects valid raster positions with NDC z < 0

> Drafted with AI assistance while bringing the SGI Open Inventor demos
> (sgi-demos/inventor-sdl2-gles2) up on gl4es (macOS/ANGLE and Emscripten).
> To be reviewed/reworked by a human before any upstream submission.

## Symptom

Bitmap text (glRasterPos3f + glBitmap) placed with an orthographic
camera renders at a stale position — typically wherever the last
*accepted* raster position was, or collapsed at the window origin.
Observed in SGI Inventor's Paint By Numbers game: all SoText2 clue
numbers piled up along the bottom edge of the window instead of
labeling their rows/columns.

## Cause

`gl4es_glRasterPos3f` (src/gl/raster.c) validates the transformed
position with:

```c
if ((transl[0] * w2 + w2) >= 0 && (transl[1] * h2 + h2) >= 0 && transl[2] >= 0) {
```

`transl` is in normalized device coordinates after the perspective
divide, where the GL view volume spans **[-1, 1] on every axis**. The
`transl[2] >= 0` term rejects the entire near half of the depth range,
so any raster position between the near plane and the view-volume
mid-plane silently fails to latch. Orthographic cameras hit this
constantly: an object halfway between near and far sits exactly at
NDC z = 0, and anything nearer is negative.

(Per the GL 1.x spec, glRasterPos is only meant to be marked invalid
when the position lies *outside* the view volume, i.e. |x|,|y|,|z| > 1
after the divide.)

## Fix

Accept the spec's NDC z range:

```c
if ((transl[0] * w2 + w2) >= 0 && (transl[1] * h2 + h2) >= 0 &&
    transl[2] >= -1.0f && transl[2] <= 1.0f) {
```

## Verified

- Inventor Paint By Numbers (SoText2 clue labels, orthographic camera):
  clue numbers render at the correct grid positions after the fix;
  pixel diff against a desktop-GL reference render drops from 4.1% to
  0.6% (residual is glyph anti-aliasing).
- Regression-checked the other Inventor demos (maze, slotcar, hohoho,
  puck, spacecadet, linkatron, drop — perspective cameras, SoText2 HUDs):
  unchanged.
- Both backends: macOS native (ANGLE) and Emscripten/WebGL.

Related: the perspective-divide fix in gl4es-bitmap-text-fixes.patch —
that made w-division happen at all; this fixes the acceptance test on
the divided z.
