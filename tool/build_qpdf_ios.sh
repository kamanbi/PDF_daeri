#!/usr/bin/env bash
# tool/build_qpdf_ios.sh
#
# qpdf + libjpeg-turbo를 iOS(arm64, 실기기)용 정적 라이브러리로 빌드해
# ios/qpdf/libqpdf_all.a 하나로 합친다. macOS에서만 실행된다(Codemagic 클라우드 Mac).
# Android 짝: tool/build_qpdf_android.sh (같은 버전·같은 crypto 옵션).
#
# 앱에는 `-force_load`로 링크되고(ios/Flutter/*.xcconfig), Dart는 `DynamicLibrary.process()`로 연다
# (lib/pdf/qpdf_isolate.dart `_openQpdf`). 시뮬레이터용은 만들지 않는다(Mac 없음, 실기기 TestFlight만).
set -euo pipefail

LIBJPEG_VERSION="3.0.4"
QPDF_VERSION="12.4.0"
LIBJPEG_SHA256="0270f9496ad6d69e743f1e7b9e3e9398f5b4d606b6a47744df4b73df50f62e38"
QPDF_SHA256="2783a032f443cc886dad41aa6d5fae3dabf23dec00ee7ec2cfb27ef67ebcf529"
IOS_MIN="16.0"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_ROOT="${BUILD_ROOT:-$REPO_ROOT/.qpdf_build_tmp}"
OUT_DIR="$REPO_ROOT/ios/qpdf"
OUT_LIB="$OUT_DIR/libqpdf_all.a"

if [ "${1:-}" = "--verify-only" ]; then
  [ -f "$OUT_LIB" ] || { echo "없음: $OUT_LIB"; exit 1; }
  lipo -info "$OUT_LIB"
  # 앱(lib/pdf/qpdf_ffi.dart)이 DynamicLibrary.process()로 찾는 qpdf C API 핵심 심볼이 정의돼 있는지 본다.
  # (pipefail 환경에서 nm | grep -q는 조기 종료로 실패하므로 결과를 변수에 받아 here-string으로 검사한다.)
  SYMS="$(nm -g "$OUT_LIB" 2>/dev/null || true)"
  MISSING=""
  for s in qpdf_init qpdf_cleanup qpdf_init_write qpdf_get_num_pages qpdf_get_page_n \
           qpdf_oh_get_type_code qpdf_oh_get_stream_data qpdf_is_encrypted; do
    grep -Eq " T _${s}\$" <<<"$SYMS" || MISSING="$MISSING $s"
  done
  if [ -n "$MISSING" ]; then echo "누락된 qpdf 심볼:$MISSING"; exit 1; fi
  echo "OK: qpdf C API 핵심 심볼 확인"
  exit 0
fi

[ "$(uname)" = "Darwin" ] || { echo "macOS에서만 실행할 수 있습니다."; exit 1; }
command -v cmake >/dev/null || brew install cmake
SDK="$(xcrun --sdk iphoneos --show-sdk-path)"
JOBS="$(sysctl -n hw.ncpu)"
mkdir -p "$BUILD_ROOT" "$OUT_DIR"

fetch() { # name url sha256
  local file="$BUILD_ROOT/$1.tar.gz"
  [ -f "$file" ] || curl -fL -o "$file" "$2"
  echo "$3  $file" | shasum -a 256 -c -
  [ -d "$BUILD_ROOT/$1" ] || tar xzf "$file" -C "$BUILD_ROOT"
}
fetch "libjpeg-turbo-${LIBJPEG_VERSION}" \
  "https://github.com/libjpeg-turbo/libjpeg-turbo/archive/refs/tags/${LIBJPEG_VERSION}.tar.gz" "$LIBJPEG_SHA256"
fetch "qpdf-${QPDF_VERSION}" \
  "https://github.com/qpdf/qpdf/releases/download/v${QPDF_VERSION}/qpdf-${QPDF_VERSION}.tar.gz" "$QPDF_SHA256"

IOS_FLAGS=(
  -DCMAKE_SYSTEM_NAME=iOS
  -DCMAKE_OSX_SYSROOT=iphoneos
  -DCMAKE_SYSTEM_PROCESSOR=aarch64
  -DCMAKE_OSX_ARCHITECTURES=arm64
  -DCMAKE_OSX_DEPLOYMENT_TARGET="$IOS_MIN"
  -DCMAKE_BUILD_TYPE=Release
  -DCMAKE_POSITION_INDEPENDENT_CODE=ON
)

echo "== libjpeg-turbo (iOS arm64) =="
JPEG_PREFIX="$BUILD_ROOT/install-jpeg"
rm -rf "$BUILD_ROOT/build-jpeg"
cmake -S "$BUILD_ROOT/libjpeg-turbo-${LIBJPEG_VERSION}" -B "$BUILD_ROOT/build-jpeg" "${IOS_FLAGS[@]}" \
  -DENABLE_SHARED=OFF -DENABLE_STATIC=ON -DWITH_JPEG8=ON -DWITH_TURBOJPEG=OFF -DWITH_SIMD=OFF \
  -DCMAKE_INSTALL_PREFIX="$JPEG_PREFIX"
cmake --build "$BUILD_ROOT/build-jpeg" --target install -j "$JOBS"

echo "== qpdf ${QPDF_VERSION} (iOS arm64, 정적) =="
rm -rf "$BUILD_ROOT/build-qpdf"
cmake -S "$BUILD_ROOT/qpdf-${QPDF_VERSION}" -B "$BUILD_ROOT/build-qpdf" "${IOS_FLAGS[@]}" \
  -DBUILD_SHARED_LIBS=OFF -DBUILD_STATIC_LIBS=ON \
  -DUSE_IMPLICIT_CRYPTO=OFF -DREQUIRE_CRYPTO_NATIVE=ON -DDEFAULT_CRYPTO=native \
  -DBUILD_DOC=OFF -DINSTALL_MANUAL=OFF -DINSTALL_EXAMPLES=OFF \
  -DCMAKE_MACOSX_BUNDLE=OFF \
  -DLIBJPEG_H_PATH="$JPEG_PREFIX/include" -DLIBJPEG_LIB_PATH="$JPEG_PREFIX/lib/libjpeg.a" \
  -DZLIB_H_PATH="$SDK/usr/include" -DZLIB_LIB_PATH="$SDK/usr/lib/libz.tbd"
# CLI 실행 파일은 iOS에서 의미가 없으므로 라이브러리 타깃만 빌드한다.
cmake --build "$BUILD_ROOT/build-qpdf" --target libqpdf -j "$JOBS"

QPDF_A="$(find "$BUILD_ROOT/build-qpdf" -name 'libqpdf*.a' | head -1)"
[ -n "$QPDF_A" ] || { echo "libqpdf.a를 찾지 못했습니다."; exit 1; }
echo "qpdf 정적 라이브러리: $QPDF_A"

# 하나로 합쳐 -force_load 한 번으로 모든 심볼을 앱에 넣는다.
libtool -static -o "$OUT_LIB" "$QPDF_A" "$JPEG_PREFIX/lib/libjpeg.a"
bash "$0" --verify-only
ls -l "$OUT_LIB"
echo "== 완료: $OUT_LIB =="
