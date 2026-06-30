# Operator-precedence bug in `fpe_shader.c`: `!need->need_texs & (1<<i)` should be `!(need->need_texs & (1<<i))`

## Summary

In `fpe_shader_t fpe_*` shader generation (`src/gl/fpe_shader.c`, in the texture-coordinate varying loop), a `need_texs` bit test is missing parentheses, so `!` is applied to the whole bitfield instead of to the masked bit. The per-texture "is this texunit needed?" check is therefore effectively dead for all texture units except 0, and only when `need_texs == 0`.

Clang flags it:

```
src/gl/fpe_shader.c:913:21: warning: logical not is only applied to the left hand side of this bitwise operator [-Wlogical-not-parentheses]
  913 |             if(t && !need->need_texs&(1<<i))
      |                     ^               ~
```

## The code

```c
// textures coordinates
for (int i=0; i<hardext.maxtex; i++) {
    int t = state->texture[i].textype;
    if(point && !pointsprite) t=0;
    if(!is_default)
        if(t && !need->need_texs&(1<<i))   // <-- here
            t = 0;
    ...
```

## Why it's wrong

`!` has higher precedence than `&`, so the expression parses as:

```c
(!need->need_texs) & (1<<i)
```

`!need->need_texs` evaluates to `1` when `need_texs == 0` and `0` otherwise, i.e. a 0/1 value. AND-ing that with `(1<<i)`:

- for `i == 0`: `(0|1) & 1` — can be non-zero, but only when `need_texs == 0`;
- for `i >= 1`: `(0|1) & (1<<i)` is **always 0** (`1 & 2 == 0`, `1 & 4 == 0`, …).

So `t = 0` (dropping the texcoord for an unneeded unit) only ever fires for unit 0 and only when no textures are needed at all. For every unit `i >= 1`, the intended "this texunit isn't in the needed set, so drop its varying" path never runs.

## Intended behavior

The surrounding logic and the rest of this same file make the intent clear — it should test the masked bit, then negate. Compare the correct idiom already used elsewhere in `fpe_shader.c`:

```c
t = (need->need_texs&(1<<i))?1:0;
...
if(need && (need->need_texs&(1<<i)) && t==0)
...
if(need && !(need->need_texs&(1<<i)))
```

So line 913 should read:

```c
if(t && !(need->need_texs&(1<<i)))
```

## Impact

When a `need` mask is supplied (fragment-stage needs driving vertex-stage varying emission), the vertex shader emits `_gl4es_TexCoord_%d` varyings for texture units that aren't actually needed, instead of dropping them. On lenient desktop GL this is usually just wasted varyings; on stricter ES2/WebGL stacks (e.g. ANGLE, browser WebGL) it can push against varying limits or surface as vertex/fragment varying mismatches. Found while running an unmodified GLU/GLUT demo (sphere-mapped, multi-texunit-capable) through gl4es over an ES2/ANGLE context.

## Fix

One-line parenthesization (patch attached, `gl4es-fpe_shader-logical-not-parens.patch`):

```diff
-            if(t && !need->need_texs&(1<<i))
+            if(t && !(need->need_texs&(1<<i)))
```

## Environment

- gl4es built as a static lib for an OpenGL ES 2.0 backend (`-DNOX11=ON -DNOEGL=ON -DDEFAULT_ES=2 -DSTATICLIB=ON`).
- Compiler: Apple clang (macOS); the warning is clang `-Wlogical-not-parentheses` (on by default).
