# Clang warning suppressions never apply to non-MSVC Clang (unreachable `elseif` + `CMAKE_CC_COMPILER_ID` typo)

## Summary

`CMakeLists.txt` intends to silence a set of Clang warnings (`-Wno-deprecated-declarations`, `-Wno-unused-function`, `-Wno-unused-variable`, `-Wno-dangling-else`, `-Wno-implicit-const-int-float-conversion`, `-Wno-visibility`), but on the most common Clang targets — macOS and Emscripten — none of them are applied. Two separate problems combine to cause this.

## Problem 1 — the Clang suppressions sit in an unreachable branch

```cmake
if(NOT WIN32_MSVC)
    # ... -std=gnu11 / -funwind-tables / -fvisibility=hidden ...
elseif(CMAKE_C_COMPILER_ID MATCHES "Clang")
    add_definitions(-Wno-deprecated-declarations) #strdup
    add_definitions(-Wno-unused-function -Wno-unused-variable -Wno-dangling-else)
    add_definitions(-Wno-implicit-const-int-float-conversion)
    add_definitions(-Wno-visibility)
else()
    # ... Intel / MSVC ...
endif()
```

Any non-MSVC Clang (macOS, Linux, Emscripten) satisfies `NOT WIN32_MSVC`, so it takes the **first** branch and never reaches the `elseif(... "Clang")`. That `elseif` is only reachable when `WIN32_MSVC` is true (clang-cl on Windows), so for everyone else the listed suppressions are dead.

## Problem 2 — typo in the second Clang block

```cmake
if (CMAKE_CC_COMPILER_ID MATCHES "Clang" OR CMAKE_SYSTEM_NAME MATCHES "Emscripten")
    add_definitions(-Wno-pointer-sign -Wno-dangling-else)
endif()
```

`CMAKE_CC_COMPILER_ID` (double `C`) isn't a defined variable, so the Clang half of this condition never matches. It works **only** via the `CMAKE_SYSTEM_NAME MATCHES "Emscripten"` half — which is why an Emscripten build happens to suppress `-Wdangling-else` but a native macOS Clang build does not.

## Net effect

On macOS Clang, the build emits warnings the project clearly intended to silence, e.g.:

```
src/gl/getter.c:878:45: warning: implicit conversion from 'long' to 'GLfloat' ... [-Wimplicit-const-int-float-conversion]
src/gl/render.c:24:112: warning: implicit conversion from 'int' to 'GLfloat' ... [-Wimplicit-const-int-float-conversion]
```

(These particular ones are benign — normalized values scaled by `INT_MAX`, where `2147483647` rounds to `2147483648` as a 32-bit float — but they're exactly the warnings `-Wno-implicit-const-int-float-conversion` was meant to quiet.) `-Wdangling-else` similarly leaks through on native Clang.

## Fix

Fix the typo and consolidate all the intended Clang suppressions into the one reachable Clang/Emscripten block, so they cover every Clang target (and clang-cl, which also matches `CMAKE_C_COMPILER_ID MATCHES "Clang"`). The now-redundant `elseif(... "Clang")` body in the first block is replaced with a pointer to the consolidated block (kept as a branch so clang-cl still routes there rather than falling into the MSVC `else()`).

Patch attached (`gl4es-cmake-clang-warning-suppression.patch`):

```diff
 elseif(CMAKE_C_COMPILER_ID MATCHES "Clang")
-    add_definitions(-Wno-deprecated-declarations) #strdup
-    add_definitions(-Wno-unused-function -Wno-unused-variable -Wno-dangling-else)
-    add_definitions(-Wno-implicit-const-int-float-conversion)
-    add_definitions(-Wno-visibility)
+    # Clang warning suppressions are applied in the consolidated Clang/Emscripten
+    # block below, so they also cover non-MSVC Clang ...
 else()
 ...
-if (CMAKE_CC_COMPILER_ID MATCHES "Clang" OR CMAKE_SYSTEM_NAME MATCHES "Emscripten")
-    add_definitions(-Wno-pointer-sign -Wno-dangling-else)
+if (CMAKE_C_COMPILER_ID MATCHES "Clang" OR CMAKE_SYSTEM_NAME MATCHES "Emscripten")
+    add_definitions(-Wno-pointer-sign -Wno-dangling-else
+                    -Wno-deprecated-declarations          # strdup
+                    -Wno-unused-function -Wno-unused-variable
+                    -Wno-implicit-const-int-float-conversion
+                    -Wno-visibility)
 endif()
```

## Environment

- Native build: macOS, Apple Clang, gl4es as a static ES2 lib (`-DNOX11=ON -DNOEGL=ON -DDEFAULT_ES=2 -DSTATICLIB=ON`).
- Also verified the Emscripten build path (`emcmake`), where only `-Wdangling-else`/`-Wpointer-sign` were being suppressed (via the `CMAKE_SYSTEM_NAME` clause) before this change.
