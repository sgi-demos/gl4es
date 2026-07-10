# glTexImage2D: sized internal formats GL_RGB4 / GL_LUMINANCE8 sample black

> Drafted with AI assistance while bringing the SGI Open Inventor demos
> (sgi-demos/inventor-sdl2-gles2) up on gl4es (macOS/ANGLE).
> To be reviewed/reworked by a human before any upstream submission.

## Symptom

Textures uploaded with the sized internal formats `GL_RGB4` (0x804F) or
`GL_LUMINANCE8` (0x8040) render black (or garbage) under gl4es, while
`GL_RGB`, `GL_RGB5`, `GL_RGB8`, and component-count (`3`) uploads of the
same data are fine.

Legacy fixed-function scene graphs pick these formats deliberately: SGI
Inventor's `SoGLTextureImageElement` selects
`{GL_LUMINANCE8, GL_LUMINANCE8_ALPHA8, GL_RGB4, GL_RGBA4}` for
low-quality textures (`textureQuality < 0.8`) whenever `GL_EXT_texture`
is advertised — which gl4es does advertise.

## Root cause

`swizzle_texture()` (src/gl/texture.c) normalizes internal formats via a
switch that already handles the sized formats `GL_RGB5`, `GL_RGB8`,
`GL_RGBA4`, `GL_RGBA8`, and `GL_LUMINANCE8_ALPHA8` — but not `GL_RGB4`
or `GL_LUMINANCE8`. Unknown formats fall into the `default:` bare
`convert = 1` path, which mangles the upload.

## Fix

Two case labels:

- `GL_RGB4` joins the `GL_RGB5`/`GL_RGB565` branch (RGB → 565 convert;
  the closest GLES-representable sized RGB format);
- `GL_LUMINANCE8` joins the `GL_LUMINANCE` branch.

## Repro

    // 128x128 solid (200,60,60) RGB888 buffer
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGB4, 128, 128, 0,
                 GL_RGB, GL_UNSIGNED_BYTE, img);
    // draw textured quad, read back center pixel:
    // before: 0,0,0   after: 200,60,60 (via 565: 206,61,58 rounding)

Verified on ANGLE/macOS with a 5-format matrix
(3 / GL_RGB / GL_RGB8 / GL_RGB4 / GL_RGB5): all now render correctly.

## Note

Other sized formats remain unhandled (e.g. `GL_RGBA2`, `GL_RGB10`,
`GL_LUMINANCE4_ALPHA4`, `GL_INTENSITY*`, `GL_ALPHA8`); a follow-up could
sweep the full GL 1.x sized-format table into the same branches rather
than relying on the default convert path.
