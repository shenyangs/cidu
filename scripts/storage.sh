#!/bin/bash
# Sourced by build/test: bundled static dependencies, no downloads at build time.
set -euo pipefail
if command -v cmake >/dev/null; then
  cmake_bin=(cmake)
elif command -v uvx >/dev/null; then
  cmake_bin=(uvx --from cmake==3.31.6 cmake)
else
  echo 'Install CMake (3.16+) or uv to build the bundled LevelDB/Snappy sources.' >&2
  exit 1
fi
"${cmake_bin[@]}" -Wno-dev -S vendor -B build/storage -DCMAKE_BUILD_TYPE=Release -DCMAKE_OSX_DEPLOYMENT_TARGET=13.0 -DCMAKE_OSX_ARCHITECTURES=arm64 >build/storage-config.log
"${cmake_bin[@]}" --build build/storage --parallel 4 >build/storage-build.log
storage_flags=(-I vendor/leveldb-1.23/include -import-objc-header vendor/leveldb-1.23/include/leveldb/c.h build/storage/leveldb-1.23/libleveldb.a build/storage/snappy-1.2.1/libsnappy.a -lc++)
