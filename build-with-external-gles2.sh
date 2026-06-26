#!/bin/sh
# build-with-external-gles2.sh — configure & build gl4es with an external gles2
rm -rf build && mkdir build && cd build

cmake -DNOX11=ON -DNOEGL=ON -DDEFAULT_ES=2 \
      -DSTATICLIB=ON -DCMAKE_BUILD_TYPE=RelWithDebInfo ..

make
