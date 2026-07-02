# Make the LIBGL_FB=2 main-FBO path work on Emscripten/WebGL (NOEGL builds)

## Summary

Two small fixes to `createMainFBO()` in `src/gl/framebuffers.c` that make the
`LIBGL_FB=2` render-to-FBO path usable under Emscripten (and more generally
under NOEGL hosts). Without them the main FBO either fails framebuffer
completeness on WebGL, or blits with a 0x0 viewport and presents nothing.

Context: on the web there is no real back buffer — the browser presents
whatever is in the canvas drawing buffer when the frame callback returns.
Classic double-buffered GL apps that clear right after SwapBuffers therefore
show a black canvas unless gl4es renders into its main FBO and blits it to the
default framebuffer at swap time (`gl4es_pre_swap()`), i.e. exactly the
`LIBGL_FB=2` mode. These fixes were found bringing an unmodified 1990s GLUT
demo up on Emscripten through gl4es (built with `-DNOX11=ON -DNOEGL=ON
-DSTATICLIB=ON`), where the host creates the GLES2 context via SDL2 and calls
`initialize_gl4es()` / `gl4es_pre_swap()` / `gl4es_post_swap()` itself.

## Fix 1 — WebGL-legal depth/stencil for the main FBO

`createMainFBO()` allocates:

```c
gles_glRenderbufferStorage(GL_RENDERBUFFER, GL_STENCIL_INDEX8, width, height);
...
gles_glRenderbufferStorage(GL_RENDERBUFFER, GL_DEPTH_COMPONENT24, width, height);
...
gles_glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_STENCIL_ATTACHMENT, ...);
gles_glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_DEPTH_ATTACHMENT, ...);
```

WebGL rejects both parts:

- `GL_DEPTH_COMPONENT24` is not a valid renderbuffer format on WebGL1 (core
  allows only `DEPTH_COMPONENT16`):
  ```
  WebGL warning: renderbufferStorage(Multisample)?: Invalid `internalFormat`: 0x81a6.
  ```
- Separate DEPTH + STENCIL attachments are forbidden in WebGL; a framebuffer
  that wants both must use a single packed `DEPTH_STENCIL` renderbuffer on
  `DEPTH_STENCIL_ATTACHMENT`:
  ```
  WebGL warning: checkFramebufferStatus: Framebuffer not complete. (status: 0x8cd6)
  DEPTH_ATTACHMENT: Attachment has no width or height.
  ```

The FBO comes up incomplete, `createMainFBO()` prints
`LIBGL: Error while creating main fbo` and deletes it, and `LIBGL_FB=2`
silently degrades to rendering directly to the (doomed) default framebuffer.

Fix: under `__EMSCRIPTEN__`, allocate one packed `GL_DEPTH_STENCIL` (0x84F9)
renderbuffer and attach it to `GL_DEPTH_STENCIL_ATTACHMENT` (0x821A). The
existing `mainfbo_ste` renderbuffer id stays allocated but unused, so
`deleteMainFBO()` is unaffected. Non-Emscripten paths are unchanged.

## Fix 2 — blitMainFBO() blits with a 0x0 viewport on NOEGL hosts

`blitMainFBO()` sets its viewport from the default-framebuffer size:

```c
gl4es_glViewport(0, 0, glstate->fbowidth, glstate->fboheight);
```

`glstate->fbowidth/fboheight` are established in `NewGLState()` from a
`glGetIntegerv(GL_VIEWPORT)` grab — which is deliberately skipped for the
default glstate under `__EMSCRIPTEN__` (and AMIGAOS4), because there may be no
context yet. Nothing else on the NOEGL path ever sets them, so they stay 0 and
every `blitMainFBO()` call rasterizes into a zero-area viewport: the swap-time
blit executes but presents nothing (black canvas, no GL errors).

Fix: in `createMainFBO()`, when `fbowidth/fboheight` were never established
(both 0), initialize them from the FBO size. Guarded so EGL/GLX hosts — where
they are already set from the real drawable and can legitimately differ from a
`LIBGL_FBO`-forced FBO size — keep their existing behavior.

## Usage note for NOEGL hosts (documentation-worthy)

In NOEGL builds nothing inside gl4es ever calls `createMainFBO()` — the only
call sites are in the EGL/GLX MakeCurrent/SwapBuffers paths (`src/glx/glx.c`).
A NOEGL host that wants `LIBGL_FB=2` must therefore, after
`initialize_gl4es()` with a current context:

```c
createMainFBO(drawable_width, drawable_height);
bindMainFBO();
```

and call `gl4es_pre_swap()` / `gl4es_post_swap()` around its platform swap.
This mirrors the existing NOEGL contract for `set_getprocaddress()` /
`set_getmainfbsize()`. If preferred, a follow-up could export a small
`gl4es_create_mainfbo(w,h)` wrapper so hosts don't link internal symbols.

## Environment

- gl4es v1.1.7, `-DNOX11=ON -DNOEGL=ON -DDEFAULT_ES=2 -DSTATICLIB=ON`
- Emscripten (emsdk clang 22), `-s USE_SDL=2 -s FULL_ES2=1`, WebGL1 context
  created by SDL2; verified in Firefox (Hardware vendor: Mozilla)
- Host: freeglut with an SDL2 backend driving context creation and swap
- Verified: with both fixes, an unmodified GLUT demo (immediate-mode geometry,
  fixed-function lighting + texturing) renders correctly at 60 fps with
  `LIBGL_FB=2`; native (non-Emscripten) builds unaffected.
