#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
TOOLCHAIN="$SCRIPT_DIR/ios-cmake/ios.toolchain.cmake"
SRC_DIR="$SCRIPT_DIR/recastnavigation"
OUT_DIR="$SCRIPT_DIR/xcframeworks"

BUILD_DEVICE="$SCRIPT_DIR/build-ios-device"
BUILD_SIM="$SCRIPT_DIR/build-ios-sim"

COMMON_CMAKE_ARGS=(
  -DRECASTNAVIGATION_DEMO=OFF
  -DRECASTNAVIGATION_TESTS=OFF
  -DRECASTNAVIGATION_EXAMPLES=OFF
  -DBUILD_SHARED_LIBS=OFF
  -DCMAKE_BUILD_TYPE=Release
  -DENABLE_BITCODE=OFF
  -DCMAKE_INTERPROCEDURAL_OPTIMIZATION=OFF
)

cmake -S "$SRC_DIR" -B "$BUILD_DEVICE" \
  -G Xcode \
  -DCMAKE_TOOLCHAIN_FILE="$TOOLCHAIN" \
  -DPLATFORM=OS64 \
  "${COMMON_CMAKE_ARGS[@]}"

cmake --build "$BUILD_DEVICE" --config Release

cmake -S "$SRC_DIR" -B "$BUILD_SIM" \
  -G Xcode \
  -DCMAKE_TOOLCHAIN_FILE="$TOOLCHAIN" \
  -DPLATFORM=SIMULATOR64COMBINED \
  "${COMMON_CMAKE_ARGS[@]}"

cmake --build "$BUILD_SIM" --config Release

mkdir -p "$OUT_DIR"

find_lib() {
  local build_dir="$1"
  local name="$2"
  local lib_path
  lib_path="$(find "$build_dir" -path "*Release*" -name "lib${name}.a" -print -quit)"
  if [[ -z "${lib_path}" ]]; then
    echo "error: lib${name}.a not found under ${build_dir}" >&2
    exit 1
  fi
  echo "$lib_path"
}

LIB_DETOUR_DEVICE="$(find_lib "$BUILD_DEVICE" Detour)"
LIB_DETOUR_SIM="$(find_lib "$BUILD_SIM" Detour)"
LIB_DETOURTILECACHE_DEVICE="$(find_lib "$BUILD_DEVICE" DetourTileCache)"
LIB_DETOURTILECACHE_SIM="$(find_lib "$BUILD_SIM" DetourTileCache)"
LIB_DETOURCROWD_DEVICE="$(find_lib "$BUILD_DEVICE" DetourCrowd)"
LIB_DETOURCROWD_SIM="$(find_lib "$BUILD_SIM" DetourCrowd)"
LIB_RECAST_DEVICE="$(find_lib "$BUILD_DEVICE" Recast)"
LIB_RECAST_SIM="$(find_lib "$BUILD_SIM" Recast)"

HEADERS_DETOUR="$SRC_DIR/Detour/Include"
HEADERS_DETOURTILECACHE="$SRC_DIR/DetourTileCache/Include"
HEADERS_DETOURCROWD="$SRC_DIR/DetourCrowd/Include"
HEADERS_RECAST="$SRC_DIR/Recast/Include"

rm -rf \
  "$OUT_DIR/Detour.xcframework" \
  "$OUT_DIR/DetourTileCache.xcframework" \
  "$OUT_DIR/DetourCrowd.xcframework" \
  "$OUT_DIR/Recast.xcframework"

xcodebuild -create-xcframework \
  -library "$LIB_DETOUR_DEVICE" -headers "$HEADERS_DETOUR" \
  -library "$LIB_DETOUR_SIM" -headers "$HEADERS_DETOUR" \
  -output "$OUT_DIR/Detour.xcframework"

xcodebuild -create-xcframework \
  -library "$LIB_DETOURTILECACHE_DEVICE" -headers "$HEADERS_DETOURTILECACHE" \
  -library "$LIB_DETOURTILECACHE_SIM" -headers "$HEADERS_DETOURTILECACHE" \
  -output "$OUT_DIR/DetourTileCache.xcframework"

xcodebuild -create-xcframework \
  -library "$LIB_DETOURCROWD_DEVICE" -headers "$HEADERS_DETOURCROWD" \
  -library "$LIB_DETOURCROWD_SIM" -headers "$HEADERS_DETOURCROWD" \
  -output "$OUT_DIR/DetourCrowd.xcframework"

xcodebuild -create-xcframework \
  -library "$LIB_RECAST_DEVICE" -headers "$HEADERS_RECAST" \
  -library "$LIB_RECAST_SIM" -headers "$HEADERS_RECAST" \
  -output "$OUT_DIR/Recast.xcframework"
