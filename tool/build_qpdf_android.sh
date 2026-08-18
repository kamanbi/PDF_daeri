#!/usr/bin/env bash
# tool/build_qpdf_android.sh
#
# qpdf(libqpdf.so) + libjpeg-turbo(정적, qpdf에 내장)를 Android용으로
# 크로스컴파일한다. M-Q0 시행착오를 반영한 재현 스크립트.
#
# 사용법 (Git Bash / MSYS 기준):
#   NDK=/c/Android/sdk/ndk/28.2.13676358 \
#   CMAKE=/c/Android/sdk/cmake/3.31.6/bin/cmake.exe \
#   NINJA=/c/Android/sdk/cmake/3.31.6/bin/ninja.exe \
#   bash tool/build_qpdf_android.sh
#
# 필수 조건:
#   - Android NDK r28 이상 (여기서는 28.2.13676358로 검증됨)
#   - CMake 3.31.x 이상 (중요 — 아래 "겪은 문제 1" 참고. NDK 동봉 3.22.1은 사용 금지)
#   - 작업 디렉터리가 반드시 ASCII 경로일 것 (아래 "겪은 문제 2" 참고)
#
# 겪은 문제 1 — CMake 3.22.1(Android SDK 기본 동봉 버전)이 NDK r28의 clang 19
#   컴파일러 식별 단계에서 크래시한다(Windows 종료 코드 -1073740791 =
#   0xC0000409, STATSTACK_BUFFER_OVERRUN에 해당하는 __fastfail).
#   `sdkmanager "cmake;3.31.6"`로 설치한 3.31.6에서는 재현되지 않았다.
#   원인은 규명하지 않았다(NDK r28+CMake 3.22.1 조합의 알려진 비호환으로 추정) —
#   사실만 기록한다. 3.31.6 이상을 사용하라.
#
# 겪은 문제 2 — 이 스크립트를 실행하는 셸의 현재 작업 디렉터리(cwd)가
#   비-ASCII(한글) 경로(F:\PDF_대리)일 때 CMake configure 단계에서 위와
#   동일한 크래시(-1073740791)가 재현되었다. cwd를 ASCII 경로(F:\PDF_daeri)로
#   바꾼 뒤에는 100% 재현되지 않았다. clang.exe 단독 호출은 비-ASCII cwd에서도
#   정상 동작했으므로, 크래시는 CMake 자체의 cwd 처리(코드페이지/wide-char
#   변환 추정)에 있는 것으로 보인다 — 확정 규명은 아니며 회피만 확인했다.
#   → 이 스크립트를 실행하기 전에 반드시 ASCII 경로로 cd 한 뒤 실행할 것.
#
# 겪은 문제 3 (미해결/특이사항, 아키텍트 판정서 §9 "미조사" 대응) —
#   qpdf CMake의 crypto 선택 로직은 DEFAULT_CRYPTO=native 만으로는
#   활성화되지 않는다. REQUIRE_CRYPTO_NATIVE=ON을 명시하지 않으면
#   "no crypto provider is available"로 configure가 실패한다
#   (libqpdf/CMakeLists.txt의 USE_IMPLICIT_CRYPTO=OFF 분기 참고).
#   또한 JPEG_LIBRARY/JPEG_INCLUDE_DIR, ZLIB_LIBRARY/ZLIB_INCLUDE_DIR라는
#   변수명은 qpdf CMakeLists.txt에 존재하지 않는다(아키텍트 판정서 §2.3의
#   예시 커맨드는 이 두 변수명을 썼으나 실제 qpdf 12.4.0 소스와 다르다).
#   실제로는 LIBJPEG_H_PATH/LIBJPEG_LIB_PATH, ZLIB_H_PATH/ZLIB_LIB_PATH를
#   find_path/find_library 캐시 변수로 직접 주입해야 한다. 이 스크립트는
#   실제 동작이 확인된 변수명을 사용한다.
#
# 겪은 문제 4 — try_run 기반 크로스컴파일 검사(R1이 우려했던 항목)는
#   이번 빌드(libjpeg-turbo, qpdf 둘 다)에서 실제로 발생하지 않았다.
#   configure 로그에 실패한 Performing Test 항목은 HAVE_LD_SCRIPT(링커 스크립트
#   지원 여부, 실패해도 빌드에 영향 없음)와 flag_shadow_local(컴파일러 플래그
#   지원 여부 probe) 정도이며 둘 다 정상적인 "미지원 기능 감지"이지 크로스컴파일
#   실행 불가로 인한 오류가 아니다. CMAKE_CROSSCOMPILING이 설정된 상태에서
#   qpdf/libjpeg-turbo의 CMakeLists.txt는 try_run이 아니라 컴파일 전용 검사
#   (check_cxx_source_compiles 등)만 사용하는 것으로 보인다.
#
# 겪은 문제 5 — x86_64 SIMD(WITH_SIMD=ON)에는 어셈블러가 필요하나, 별도로
#   nasm/yasm을 설치하지 않아도 NDK r28에 yasm.exe가 동봉되어 있어
#   CMake가 자동으로 찾아 사용했다(NDK toolchain bin 디렉터리 내
#   yasm.exe). arm64-v8a는 NEON intrinsics 경로를 쓰므로 애초에
#   외부 어셈블러가 필요 없다.
#
# 미해결 항목:
#   - armeabi-v7a(32비트) 미빌드 (Q16 미결 — 사용자 판단 대기)
#   - qpdfjob C API를 통한 실제 저장/삭제/병합 잡 실행은 이번 라운드
#     범위 밖(M-Q0는 .so 생성까지). M-Q1~M-Q2에서 ffigen 바인딩 후 검증 예정
#   - "std::format 등 C++20 표준 라이브러리 기능이 NDK libc++에서 실제로
#     링크되는가"(16_..._spike.md §9 미확인 항목)는 이번 빌드가 12.4.0으로
#     오류 없이 성공함으로써 사실상 해소됨 — qpdf 12.4.0 소스가 실제로
#     <format> 등을 사용하는 경로에서 NDK r28 libc++와 링크에 성공했다

set -euo pipefail

# ── 경로 설정 (환경변수로 덮어쓰기 가능) ─────────────────────────
NDK="${NDK:-C:/Android/sdk/ndk/28.2.13676358}"
CMAKE="${CMAKE:-C:/Android/sdk/cmake/3.31.6/bin/cmake.exe}"
NINJA="${NINJA:-C:/Android/sdk/cmake/3.31.6/bin/ninja.exe}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NATIVE_DIR="$REPO_ROOT/native"
BUILD_ROOT="${BUILD_ROOT:-$REPO_ROOT/.qpdf_build_tmp}"   # ASCII 경로 강제 — repo 안 사용 시 .gitignore 대상 확인할 것

LIBJPEG_VERSION="3.0.4"
QPDF_VERSION="12.4.0"   # 실패 시 12.2.0으로 재시도 (아래 "버전 결정" 참고)

ANDROID_PLATFORM_LEVEL="android-26"   # minSdkVersion(API 26)과 반드시 일치

ABIS=("arm64-v8a" "x86_64")   # armeabi-v7a는 Q16 미결로 제외

mkdir -p "$BUILD_ROOT" "$NATIVE_DIR/libjpeg-turbo" "$NATIVE_DIR/qpdf"

echo "== 작업 디렉터리 ASCII 확인 =="
case "$REPO_ROOT" in
  *[!\ -~]*) echo "경고: REPO_ROOT에 비-ASCII 문자가 있습니다. CMake가 크래시할 수 있습니다: $REPO_ROOT" ;;
  *) echo "OK: $REPO_ROOT" ;;
esac

# ── 1. 소스 확보 ──────────────────────────────────────────────
if [ ! -f "$BUILD_ROOT/libjpeg-turbo-${LIBJPEG_VERSION}.tar.gz" ]; then
  curl -L -o "$BUILD_ROOT/libjpeg-turbo-${LIBJPEG_VERSION}.tar.gz" \
    "https://github.com/libjpeg-turbo/libjpeg-turbo/archive/refs/tags/${LIBJPEG_VERSION}.tar.gz"
fi
if [ ! -f "$BUILD_ROOT/qpdf-${QPDF_VERSION}.tar.gz" ]; then
  curl -L -o "$BUILD_ROOT/qpdf-${QPDF_VERSION}.tar.gz" \
    "https://github.com/qpdf/qpdf/releases/download/v${QPDF_VERSION}/qpdf-${QPDF_VERSION}.tar.gz"
fi

[ -d "$BUILD_ROOT/libjpeg-turbo-${LIBJPEG_VERSION}" ] || tar xzf "$BUILD_ROOT/libjpeg-turbo-${LIBJPEG_VERSION}.tar.gz" -C "$BUILD_ROOT"
[ -d "$BUILD_ROOT/qpdf-${QPDF_VERSION}" ] || tar xzf "$BUILD_ROOT/qpdf-${QPDF_VERSION}.tar.gz" -C "$BUILD_ROOT"

# ── 2. libjpeg-turbo 크로스컴파일 (정적, qpdf에만 내장 링크) ──────
for ABI in "${ABIS[@]}"; do
  echo "== libjpeg-turbo ($ABI) =="
  BJ="$BUILD_ROOT/build-jpeg-$ABI"
  rm -rf "$BJ"
  "$CMAKE" -S "$BUILD_ROOT/libjpeg-turbo-${LIBJPEG_VERSION}" -B "$BJ" -G Ninja \
    -DCMAKE_TOOLCHAIN_FILE="$NDK/build/cmake/android.toolchain.cmake" \
    -DANDROID_ABI="$ABI" \
    -DANDROID_PLATFORM="$ANDROID_PLATFORM_LEVEL" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_MAKE_PROGRAM="$NINJA" \
    -DENABLE_SHARED=OFF -DENABLE_STATIC=ON \
    -DWITH_JPEG8=ON \
    -DCMAKE_INSTALL_PREFIX="$NATIVE_DIR/libjpeg-turbo/install-$ABI"
  "$CMAKE" --build "$BJ" --target install -- -j "$(nproc 2>/dev/null || echo 4)"
done

# ── 3. qpdf 크로스컴파일 (공유 라이브러리) ─────────────────────
# 버전 결정: 12.4.0을 우선 시도한다. C++20 컴파일 오류가 실제로
# 발생하면(예: "requires at least C++20" 계열 오류) 12.2.0(C++17 마지막
# 릴리스)으로 QPDF_VERSION을 바꿔 재시도한다. 이번 실행에서는 12.4.0이
# arm64-v8a·x86_64 양쪽 다 오류 없이 성공했으므로 다운그레이드가
# 필요하지 않았다.
for ABI in "${ABIS[@]}"; do
  echo "== qpdf ${QPDF_VERSION} ($ABI) =="
  case "$ABI" in
    arm64-v8a) ZLIB_TRIPLE="aarch64-linux-android" ;;
    x86_64)    ZLIB_TRIPLE="x86_64-linux-android" ;;
    *) echo "지원하지 않는 ABI: $ABI"; exit 1 ;;
  esac

  JPEG_PREFIX="$NATIVE_DIR/libjpeg-turbo/install-$ABI"
  ZLIB_LIB="$NDK/toolchains/llvm/prebuilt/windows-x86_64/sysroot/usr/lib/$ZLIB_TRIPLE/libz.a"
  ZLIB_INC="$NDK/toolchains/llvm/prebuilt/windows-x86_64/sysroot/usr/include"

  BQ="$BUILD_ROOT/build-qpdf-$ABI"
  rm -rf "$BQ"
  "$CMAKE" -S "$BUILD_ROOT/qpdf-${QPDF_VERSION}" -B "$BQ" -G Ninja \
    -DCMAKE_TOOLCHAIN_FILE="$NDK/build/cmake/android.toolchain.cmake" \
    -DANDROID_ABI="$ABI" \
    -DANDROID_PLATFORM="$ANDROID_PLATFORM_LEVEL" \
    -DANDROID_STL=c++_static \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_MAKE_PROGRAM="$NINJA" \
    -DBUILD_SHARED_LIBS=ON -DBUILD_STATIC_LIBS=OFF \
    -DUSE_IMPLICIT_CRYPTO=OFF -DREQUIRE_CRYPTO_NATIVE=ON -DDEFAULT_CRYPTO=native \
    -DBUILD_DOC=OFF -DINSTALL_MANUAL=OFF -DINSTALL_EXAMPLES=OFF \
    -DLIBJPEG_H_PATH="$JPEG_PREFIX/include" -DLIBJPEG_LIB_PATH="$JPEG_PREFIX/lib/libjpeg.a" \
    -DZLIB_H_PATH="$ZLIB_INC" -DZLIB_LIB_PATH="$ZLIB_LIB" \
    -DCMAKE_INSTALL_PREFIX="$NATIVE_DIR/qpdf/install-$ABI"
  "$CMAKE" --build "$BQ" --target install -- -j "$(nproc 2>/dev/null || echo 4)"
done

# ── 4. jniLibs 배치 (strip 포함) ────────────────────────────
STRIP="$NDK/toolchains/llvm/prebuilt/windows-x86_64/bin/llvm-strip.exe"
for ABI in "${ABIS[@]}"; do
  DEST="$REPO_ROOT/android/app/src/main/jniLibs/$ABI"
  mkdir -p "$DEST"
  cp "$NATIVE_DIR/qpdf/install-$ABI/lib/libqpdf.so" "$DEST/libqpdf.so"
  "$STRIP" "$DEST/libqpdf.so"
  echo "배치 완료: $DEST/libqpdf.so ($(stat -c%s "$DEST/libqpdf.so" 2>/dev/null || wc -c < "$DEST/libqpdf.so") bytes)"
done

echo "== 완료 =="
echo "libjpeg-turbo, qpdf 설치본: $NATIVE_DIR"
echo "jniLibs 배치: $REPO_ROOT/android/app/src/main/jniLibs/{${ABIS[*]}}/libqpdf.so"
