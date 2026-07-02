#!/bin/sh
set -o verbose
rm -rf build && mkdir build && cd build
cmake -DNOX11=ON -DNOEGL=ON -DDEFAULT_ES=2 \
      -DSTATICLIB=ON -DCMAKE_BUILD_TYPE=RelWithDebInfo ..
make
cd ..
mv lib/libGL.a lib/libGL-native.a

rm -rf build-web && mkdir build-web && cd build-web
emcmake cmake -DNOX11=ON -DNOEGL=ON -DDEFAULT_ES=2 -DSTATICLIB=ON ..
emmake make
cd ..
mv lib/libGL.a lib/libGL-web.a
