# glCallLists GL_2/3/4_BYTES computes wrong list ids

> Drafted with AI assistance while bringing the SGI Open Inventor demos
> (sgi-demos/inventor-sdl2-gles2) up on gl4es (macOS/ANGLE and Emscripten).
> To be reviewed/reworked by a human before any upstream submission.

## Symptom

All SoText2/SoText3 text invisible under gl4es: Inventor replays glyph
display lists keyed by UCS-2 character code via
`glCallLists(n, GL_2_BYTES, string)`, and every character resolves to a
wrong (empty) list id.

## Root cause

The `call_bytes` macro in `gl4es_glCallLists` (src/gl/gl4es.c) — already
flagged `// seriously wtf` — computes

    list += byte[j] << (stride - j)      // GL_2_BYTES: b0*4 + b1*2

instead of the GL-spec big-endian concatenation

    list = b0*256^(N-1) + ... + bN-1     // GL_2_BYTES: b0*256 + b1

e.g. 'A' (0x00,0x41) selected list 130 instead of 65.

## Fix

    list += *(l + (i * stride + j)) << (8 * (stride - 1 - j));

## Repro

Record list base+0x48 containing any drawing; then
`GLubyte s[2]={0x00,0x48}; glListBase(base); glCallLists(1, GL_2_BYTES, s);`
draws nothing before the fix, replays list base+0x48 after.

Verified: SoText3 glyph geometry (and, with the companion raster fixes,
SoText2 bitmap glyphs) render pixel-identical to desktop GL.
