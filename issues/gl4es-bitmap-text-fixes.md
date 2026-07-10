# Bitmap text (glRasterPos/glBitmap) fixes: perspective divide, latched raster color, unpack alignment, readback flush

> Drafted with AI assistance while bringing the SGI Open Inventor demos
> (sgi-demos/inventor-sdl2-gles2) up on gl4es (macOS/ANGLE and Emscripten).
> To be reviewed/reworked by a human before any upstream submission.

Four related defects in the glBitmap path, found via SGI Inventor's
SoText2 (screen-space bitmap text: glRasterPos3f + glBitmap glyphs
recorded in display lists, replayed with glCallLists). One .patch, four
logically separate hunks:

## 1. glRasterPos3f misses the perspective divide (src/gl/raster.c)

The raster position is transformed by modelview and projection but never
divided by clip w. Correct for orthographic projections (w=1); under any
perspective projection (w = -z_eye) the computed window position is far
off-window and the position-set is silently skipped — bitmap text never
draws. Fix: divide x,y,z by w (reject w<=0) before the viewport mapping.

## 2. Raster color must be latched at glRasterPos time (raster.h/raster.c)

GL latches the *current raster color* when the raster position is set;
gl4es sampled `glstate->color` at glBitmap-draw time instead. Scene
graphs (Inventor) set the text color before glRasterPos and may send
other colors before the glyphs flush, so text picked up whatever color
came later. Fix: `rasterpos_t` gains a latched color (+valid flag,
falling back to the old behavior when the raster pos was never set);
the bitmap writer uses it.

## 3. glBitmap ignores GL_UNPACK_ALIGNMENT (raster.c, listdraw.c)

Rows were assumed tightly packed (`(width+7)/8` bytes); the GL default
unpack alignment is 4, and classic font code (Inventor's libFL) emits
4-byte-aligned rows. Result: row shear — speckled, shredded glyphs.
Fix: honor `glstate->texture.unpack_align` for the row stride in the
direct path; normalize to tight packing when recording into display
lists and replay with alignment 1 (recorded copies previously also
under-allocated: `(width+7)/8` of a 4-aligned source).

## 4. glReadPixels misses pending bitmaps (src/gl/texture_read.c)

Batched glBitmap draws (`bm_drawing`) are flushed by glDrawXXX and
swap, but not by glReadPixels — a readback (screenshots, tests) sees a
framebuffer without the text that will appear on screen. Fix: call
`bitmap_flush()` at the top of `gl4es_glReadPixels`.

## Verification

SGI slotcar (1994) title screen — SoText3 tessellated title, four lines
of SoText2 bitmap text, textures, gradient sky — renders via gl4es on
ANGLE/macOS with 0.002% pixel difference vs Apple desktop OpenGL
(edge rasterization only). Standalone repro snippets available:
tessellation + list + GL_2_BYTES + perspective rasterpos all covered.
