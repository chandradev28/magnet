#!/usr/bin/env bash
set -euo pipefail

# Build the Android libtorrent bridge from the exact source checked into this
# repository. The upstream Flutter package downloads a prebuilt .so, which
# would silently omit any fixes made to torrent_bridge.cpp.

ABI="${1:-arm64-v8a}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NDK_DIR="${ANDROID_NDK_ROOT:-}"

if [[ -z "$NDK_DIR" || ! -x "$NDK_DIR/toolchains/llvm/prebuilt/linux-x86_64/bin/clang++" ]]; then
  echo "ANDROID_NDK_ROOT must point to an installed Android NDK" >&2
  exit 1
fi

case "$ABI" in
  arm64-v8a)
    OPENSSL_TARGET="android-arm64"
    CLANG_TARGET="aarch64-linux-android24"
    ;;
  armeabi-v7a)
    OPENSSL_TARGET="android-arm"
    CLANG_TARGET="armv7a-linux-androideabi24"
    ;;
  x86_64)
    OPENSSL_TARGET="android-x86_64"
    CLANG_TARGET="x86_64-linux-android24"
    ;;
  *)
    echo "Unsupported Android ABI: $ABI" >&2
    exit 1
    ;;
esac

LIBTORRENT_VERSION="v2.1.1"
OPENSSL_TAG="openssl-3.2.1"
BOOST_VERSION="1.84.0"
BOOST_DIR="boost_1_84_0"
WORK_DIR="$(mktemp -d "${RUNNER_TEMP:-/tmp}/magnet-native.XXXXXX")"
OUT_DIR="$ROOT_DIR/third_party/libtorrent_flutter/prebuilt/android/$ABI"
LLVM_DIR="$NDK_DIR/toolchains/llvm/prebuilt/linux-x86_64/bin"

mkdir -p "$OUT_DIR"
echo "Building patched libtorrent bridge for $ABI in $WORK_DIR"

curl -fsSL "https://archives.boost.io/release/$BOOST_VERSION/source/$BOOST_DIR.tar.gz" \
  -o "$WORK_DIR/$BOOST_DIR.tar.gz"
tar -xf "$WORK_DIR/$BOOST_DIR.tar.gz" -C "$WORK_DIR"

git clone --depth 1 --branch "$OPENSSL_TAG" \
  https://github.com/openssl/openssl.git "$WORK_DIR/openssl-src"
(
  cd "$WORK_DIR/openssl-src"
  export ANDROID_NDK_ROOT="$NDK_DIR"
  export PATH="$LLVM_DIR:$PATH"
  EXTRA_OPTS=()
  if [[ "$ABI" == "armeabi-v7a" ]]; then
    EXTRA_OPTS+=(no-asm)
  fi
  ./Configure "$OPENSSL_TARGET" -D__ANDROID_API__=24 \
    --prefix="$WORK_DIR/openssl-install" -fPIC \
    no-shared no-tests no-ui-console no-docs "${EXTRA_OPTS[@]}"
  make -j"$(nproc)"
  make install_sw
)

git clone --depth 1 --branch "$LIBTORRENT_VERSION" --recurse-submodules \
  https://github.com/arvidn/libtorrent.git "$WORK_DIR/libtorrent-src"

if [[ -d "$WORK_DIR/openssl-install/lib64" ]]; then
  OSSL_LIB_DIR="$WORK_DIR/openssl-install/lib64"
else
  OSSL_LIB_DIR="$WORK_DIR/openssl-install/lib"
fi

mkdir -p "$WORK_DIR/libtorrent-src/build"
(
  cd "$WORK_DIR/libtorrent-src/build"
  cmake .. \
    -DCMAKE_SYSTEM_NAME=Android \
    -DCMAKE_ANDROID_NDK="$NDK_DIR" \
    -DCMAKE_ANDROID_ARCH_ABI="$ABI" \
    -DCMAKE_ANDROID_STL_TYPE=c++_static \
    -DCMAKE_SYSTEM_VERSION=24 \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
    -DBUILD_SHARED_LIBS=OFF \
    -Dstatic_runtime=ON \
    -Ddeprecated-functions=ON \
    -Dencryption=ON \
    -Dwebtorrent=OFF \
    -DOPENSSL_ROOT_DIR="$WORK_DIR/openssl-install" \
    -DOPENSSL_INCLUDE_DIR="$WORK_DIR/openssl-install/include" \
    -DOPENSSL_CRYPTO_LIBRARY="$OSSL_LIB_DIR/libcrypto.a" \
    -DOPENSSL_SSL_LIBRARY="$OSSL_LIB_DIR/libssl.a" \
    -DBOOST_ROOT="$WORK_DIR/$BOOST_DIR" \
    -DBoost_INCLUDE_DIR="$WORK_DIR/$BOOST_DIR" \
    -G Ninja -Wno-dev
  ninja -j"$(nproc)"
  grep -E '^webtorrent:BOOL=OFF$' CMakeCache.txt
)

LT_LIB="$(find "$WORK_DIR/libtorrent-src/build" -name libtorrent-rasterbar.a -print -quit)"
if [[ -z "$LT_LIB" ]]; then
  echo "libtorrent-rasterbar.a was not produced" >&2
  exit 1
fi

"$LLVM_DIR/clang++" \
  --target="$CLANG_TARGET" \
  -shared -fPIC -O3 -std=c++17 -flto \
  -Wl,-z,max-page-size=16384 \
  -DTORRENT_BRIDGE_EXPORTS -DTORRENT_USE_OPENSSL -DBOOST_NO_IOSTREAM \
  -I"$WORK_DIR/libtorrent-src/include" \
  -I"$WORK_DIR/libtorrent-src/build/include" \
  -I"$WORK_DIR/$BOOST_DIR" \
  -I"$WORK_DIR/openssl-install/include" \
  -o "$OUT_DIR/liblibtorrent_flutter.so" \
  "$ROOT_DIR/third_party/libtorrent_flutter/src/torrent_bridge.cpp" \
  -Wl,--whole-archive "$LT_LIB" -Wl,--no-whole-archive \
  "$OSSL_LIB_DIR/libssl.a" "$OSSL_LIB_DIR/libcrypto.a" \
  -llog -static-libstdc++

test -s "$OUT_DIR/liblibtorrent_flutter.so"
file "$OUT_DIR/liblibtorrent_flutter.so"
echo "Built patched native bridge: $OUT_DIR/liblibtorrent_flutter.so"
