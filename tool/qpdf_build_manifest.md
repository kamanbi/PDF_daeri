# qpdf/libjpeg-turbo Android 빌드 매니페스트

빌드 스크립트: `tool/build_qpdf_android.sh` · 작성/실행: build-runner · 2026-08-18

## 도구 버전

| 항목 | 값 |
|---|---|
| Android NDK | 28.2.13676358 (r28) — `C:\Android\sdk\ndk\28.2.13676358` |
| CMake | 3.31.6 — `C:\Android\sdk\cmake\3.31.6` (NDK 동봉/기본 3.22.1 사용 금지 — 크래시, 아래 참고) |
| Ninja | 3.31.6 배포에 동봉된 `ninja.exe` |
| clang | Android clang 19.0.1 (NDK r28 동봉, LLVM 19 계열) |

## 소스

| 라이브러리 | 버전 | 출처 | SHA-256 (tar.gz) |
|---|---|---|---|
| libjpeg-turbo | 3.0.4 | `github.com/libjpeg-turbo/libjpeg-turbo` 태그 3.0.4 tarball | `0270f9496ad6d69e743f1e7b9e3e9398f5b4d606b6a47744df4b73df50f62e38` |
| qpdf | 12.4.0 | `github.com/qpdf/qpdf` 릴리스 소스 tarball `qpdf-12.4.0.tar.gz` | `2783a032f443cc886dad41aa6d5fae3dabf23dec00ee7ec2cfb27ef67ebcf529` |

## 빌드 설정

- `ANDROID_PLATFORM=android-26` (minSdkVersion API 26과 일치)
- `ANDROID_STL=c++_static` (libqpdf.so 단일 소비자이므로 정적 링크 — `libc++_shared.so` 의존성 없음, `readobj -d`로 확인)
- qpdf: `BUILD_SHARED_LIBS=ON`, `BUILD_STATIC_LIBS=OFF`, `USE_IMPLICIT_CRYPTO=OFF`, `REQUIRE_CRYPTO_NATIVE=ON`, `DEFAULT_CRYPTO=native`
- libjpeg-turbo: `ENABLE_SHARED=OFF`, `ENABLE_STATIC=ON`, `WITH_JPEG8=ON` (정적 라이브러리로 qpdf에 내장 링크, 별도 .so 없음)
- zlib: NDK 제공 `libz.a` 정적 링크 (동적 `.so` 미사용)

## 산출물 SHA-256 (jniLibs 배치본, strip 후)

| 파일 | ABI | 크기(byte) | SHA-256 |
|---|---|---|---|
| `android/app/src/main/jniLibs/arm64-v8a/libqpdf.so` | arm64-v8a | 4,609,152 | `21f40e9f222ebd9550f8060187c39ebb97401040be10ce5b6ff570f781a53578` |
| `android/app/src/main/jniLibs/x86_64/libqpdf.so` | x86_64 | 4,862,384 | `1ddfa02146da57b93f84f35276e154abc5952155ee7481d4b8f5c34ce4a734a7` |

## 재현 방법

```
NDK=/c/Android/sdk/ndk/28.2.13676358 \
CMAKE=/c/Android/sdk/cmake/3.31.6/bin/cmake.exe \
NINJA=/c/Android/sdk/cmake/3.31.6/bin/ninja.exe \
bash tool/build_qpdf_android.sh
```

작업 디렉터리(cwd)는 반드시 ASCII 경로여야 한다. 자세한 시행착오는 `tool/build_qpdf_android.sh` 상단 주석과 `_workspace/17_build-runner_qpdf_ndk_build.md` 참고.
