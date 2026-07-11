# createMainFBO: blit-destination size goes stale when the main FBO is re-created at a new size

> Drafted with AI assistance while bringing the SGI Open Inventor demos
> (sgi-demos/inventor-sdl2-gles2) up on gl4es (Emscripten).
> To be reviewed/reworked by a human before any upstream submission.

## Symptom

On a NOEGL host (Emscripten) where the app re-creates the LIBGL_FB=2
main FBO after the drawing surface changes size — e.g. an SDL2 app that
opens a second, larger window, which on the web resizes the shared
canvas — the presented image is the old, smaller FBO region stretched
across the whole canvas (content enlarged and cropped to its lower-left
corner).

Observed in SGI Inventor's textomatic (two windows: 320x220 editor
created first, 620x490 main view second): only the lower-left corner of
the text ever showed.

## Cause

`blitMainFBO()` (src/gl/framebuffers.c) sets its output viewport from
`glstate->fbowidth/fboheight` — the default-framebuffer size. On NOEGL
hosts that value is only established inside `createMainFBO()` by the
earlier fix, guarded with "only when never set":

```c
if(!glstate->fbowidth || !glstate->fboheight) { ... }
```

When the caller re-invokes `createMainFBO(new_w, new_h)` after a
surface resize, the FBO itself is resized but `fbowidth/fboheight`
keep the *old* surface size, so the final blit maps the new FBO to the
old, smaller viewport.

## Fix

Also refresh `fbowidth/fboheight` when they were tracking the previous
main-FBO size (i.e. the same NOEGL bootstrap case, one resize later):

```c
int oldw = glstate->fbo.mainfbo_width, oldh = glstate->fbo.mainfbo_height;
...
if(!glstate->fbowidth || !glstate->fboheight ||
   (glstate->fbowidth == oldw && glstate->fboheight == oldh)) {
    glstate->fbowidth  = width;
    glstate->fboheight = height;
}
```

A host that manages the real default framebuffer (EGL/GLX paths, where
fbowidth comes from the context) never has fbowidth equal to the main
FBO size by construction, so the extra condition is a no-op there.

## Verified

- textomatic and noodle (multi-window Inventor demos) now present
  correctly framed on Emscripten/WebGL after the second window resizes
  the canvas; single-window demos unchanged.
- Native (ANGLE) regression: pixel diffs vs desktop GL unchanged across
  all 12 Inventor demos.

Related: extends the earlier NOEGL fbowidth bootstrap fix
(gl4es-mainfbo-fbowidth.patch).
