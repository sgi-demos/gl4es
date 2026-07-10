# glGetBooleanv bypasses gl4es state; GL1 framebuffer-mode queries return 0

> Drafted with AI assistance while bringing the SGI Open Inventor demos
> (sgi-demos/inventor-sdl2-gles2) up on gl4es (macOS/ANGLE and Emscripten).
> To be reviewed/reworked by a human before any upstream submission.

## Symptom

SGI Inventor renders everything in the default 0.8 gray — no materials —
on gl4es, while the same build on desktop GL is fully colored ("the
grayscale maze").

## Root cause (two parts)

1. `gl4es_glGetBooleanv` (src/gl/wrap/gles.c) forwards the pname straight
   to the GLES2 driver, bypassing `gl4es_commonGet` and all of gl4es' own
   state. Any enum the driver rejects fails soft: INVALID_ENUM and the
   output value untouched, so callers read 0. Even enums gl4es *does*
   answer elsewhere (GL_DOUBLEBUFFER, GL_MAX_LIGHTS...) return garbage
   through the Booleanv path.

2. `gl4es_commonGet` (src/gl/getter.c) has no cases for the GL1
   framebuffer-mode queries GL_RGBA_MODE / GL_INDEX_MODE / GL_STEREO.
   On GLES these are constants: RGBA=1, INDEX=0, STEREO=0.

Fixed-function code takes load-bearing decisions on those zeros:
Inventor's SoGLLazyElement::init() calls glGetBooleanv(GL_RGBA_MODE),
reads 0, concludes the framebuffer is COLOR INDEX mode, and never sends
RGBA materials at all.

## Fix

- `gl4es_glGetBooleanv` first consults `gl4es_commonGet` (single-value
  pnames only, so no risk for array pnames, which keep the old path).
- `gl4es_commonGet` answers GL_RGBA_MODE (1), GL_INDEX_MODE (0),
  GL_STEREO (0); enums added to src/gl/const.h (internal code compiles
  against GLES headers which lack them).

## Repro

    GLboolean b = 0;
    glGetBooleanv(GL_RGBA_MODE, &b);   // b == 0 before the fix, 1 after

Verified: Inventor maze via gl4es on ANGLE/macOS renders pixel-identical
to Apple desktop OpenGL after this fix.
