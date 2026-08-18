// GENERATED FILE — ffigen.yaml(리포지토리 루트)로 생성하도록 설계된 바인딩.
//
// 이 커밋 시점에는 `dart run ffigen`을 이 호스트에서 실행할 수 없었다: ffigen은 헤더 파싱에
// `libclang`(Windows에서는 별도의 표준 LLVM 배포판이 제공하는 `libclang.dll`)이 필요한데, 이
// 머신에는 Android NDK의 clang(`clang.exe`)만 있고 `libclang.dll`은 어디에도 없다(NDK는 컴파일러
// 실행 파일만 배포하고 파싱 라이브러리는 배포하지 않는다). 별도 LLVM 설치(~수백 MB 다운로드)는
// 사용자 승인 없이 진행하지 않는 것이 안전 규칙(다운로드는 명시적 승인 필요)이므로, 대신
// `ffigen.yaml`의 화이트리스트에 정확히 대응하는 바인딩을 **手写**했다. `ffigen.yaml`이 이
// 파일의 사양이다 -- LLVM이 설치된 환경에서 `dart run ffigen --config ffigen.yaml`을 실행하면
// 이 파일을 대체할 수 있어야 하며, 그때 함수 시그니처가 바뀌면 그것이 곧 이 손수 작성분의 버그다.
//
// 대상 헤더(native/qpdf/install-arm64-v8a/include/qpdf/): qpdfjob-c.h, qpdf-c.h, qpdflogger-c.h.
// qpdf 12.4.0. 이 파일 자체는 수정 금지 대상(생성물)이지만, 위 사유로 사람이 직접 채웠다 --
// 재생성 전까지는 이 파일도 사람이 관리한다는 뜻이다. 재생성 시 이 주석 블록은 유지한다.
//
// ignore_for_file: always_specify_types, camel_case_types, non_constant_identifier_names,
// ignore_for_file: unused_field, constant_identifier_names
library;

import 'dart:ffi' as ffi;

// ── 불투명 핸들 타입 ────────────────────────────────────────────────────────
// 전부 `typedef struct _xxx* xxx;` 형태(qpdf-c.h/qpdfjob-c.h/qpdflogger-c.h) -- 내용을 알 수
// 없는 불투명 포인터로만 다룬다. Dart 쪽에서 역참조하지 않는다.

final class _qpdfjob_handle extends ffi.Opaque {}

/// `qpdfjob-c.h`의 `qpdfjob_handle`.
typedef qpdfjob_handle = ffi.Pointer<_qpdfjob_handle>;

final class _qpdf_data extends ffi.Opaque {}

/// `qpdf-c.h`의 `qpdf_data`.
typedef qpdf_data = ffi.Pointer<_qpdf_data>;

final class _qpdf_error extends ffi.Opaque {}

/// `qpdf-c.h`의 `qpdf_error`.
typedef qpdf_error = ffi.Pointer<_qpdf_error>;

final class _qpdflogger_handle extends ffi.Opaque {}

/// `qpdflogger-c.h`의 `qpdflogger_handle`.
typedef qpdflogger_handle = ffi.Pointer<_qpdflogger_handle>;

// ── qpdf-c.h: enum qpdf_error_code_e (필요한 값만) ─────────────────────────
// 전체 열거값은 Constants.h에 더 있으나 이 프로젝트는 qpdf_has_error()/텍스트 메시지로
// 실패를 판정하므로(§ qpdf_isolate.dart) 코드값 자체에 의존하는 분기를 만들지 않는다. 참고용으로만 남긴다.
abstract final class qpdf_error_code_e {
  static const int qpdf_e_success = 0;
}

// ── qpdflogger-c.h: enum qpdf_log_dest_e ───────────────────────────────────
abstract final class qpdf_log_dest_e {
  static const int qpdf_log_dest_default = 0;
  static const int qpdf_log_dest_stdout = 1;
  static const int qpdf_log_dest_stderr = 2;
  static const int qpdf_log_dest_discard = 3;
  static const int qpdf_log_dest_custom = 4;
}

// ── 콜백 네이티브 시그니처 ──────────────────────────────────────────────────

/// `qpdfjob_register_progress_reporter`의 `report_progress` 콜백.
typedef qpdf_report_progress_fn_native = ffi.Void Function(ffi.Int32 percent, ffi.Pointer<ffi.Void> data);
typedef qpdf_report_progress_fn_dart = void Function(int percent, ffi.Pointer<ffi.Void> data);

/// `qpdflogger_set_error` 등의 `qpdf_log_fn_t`. 반환 0 = 성공.
typedef qpdf_log_fn_native =
    ffi.Int32 Function(ffi.Pointer<ffi.Char> data, ffi.Size len, ffi.Pointer<ffi.Void> udata);
typedef qpdf_log_fn_dart = int Function(ffi.Pointer<ffi.Char> data, int len, ffi.Pointer<ffi.Void> udata);

// ── 바인딩 클래스 ───────────────────────────────────────────────────────────

/// qpdf C API 심볼을 [library]에서 조회해 담는다. `qpdf_isolate.dart`가 워커 isolate 안에서
/// `DynamicLibrary.open`한 핸들로 이 클래스를 인스턴스화하는 유일한 소비처다(§5.7 불변식 1).
class QpdfBindings {
  QpdfBindings(ffi.DynamicLibrary library)
    : qpdfjob_init = library.lookupFunction<qpdfjob_handle Function(), qpdfjob_handle Function()>('qpdfjob_init'),
      qpdfjob_cleanup = library
          .lookupFunction<
            ffi.Void Function(ffi.Pointer<qpdfjob_handle>),
            void Function(ffi.Pointer<qpdfjob_handle>)
          >('qpdfjob_cleanup'),
      qpdfjob_initialize_from_json = library
          .lookupFunction<
            ffi.Int32 Function(qpdfjob_handle, ffi.Pointer<ffi.Char>),
            int Function(qpdfjob_handle, ffi.Pointer<ffi.Char>)
          >('qpdfjob_initialize_from_json'),
      qpdfjob_run = library.lookupFunction<ffi.Int32 Function(qpdfjob_handle), int Function(qpdfjob_handle)>(
        'qpdfjob_run',
      ),
      qpdfjob_register_progress_reporter = library
          .lookupFunction<
            ffi.Void Function(qpdfjob_handle, ffi.Pointer<ffi.NativeFunction<qpdf_report_progress_fn_native>>, ffi.Pointer<ffi.Void>),
            void Function(qpdfjob_handle, ffi.Pointer<ffi.NativeFunction<qpdf_report_progress_fn_native>>, ffi.Pointer<ffi.Void>)
          >('qpdfjob_register_progress_reporter'),
      qpdfjob_set_logger = library
          .lookupFunction<
            ffi.Void Function(qpdfjob_handle, qpdflogger_handle),
            void Function(qpdfjob_handle, qpdflogger_handle)
          >('qpdfjob_set_logger'),
      qpdfjob_get_logger = library
          .lookupFunction<
            qpdflogger_handle Function(qpdfjob_handle),
            qpdflogger_handle Function(qpdfjob_handle)
          >('qpdfjob_get_logger'),
      qpdf_init = library.lookupFunction<qpdf_data Function(), qpdf_data Function()>('qpdf_init'),
      qpdf_cleanup = library
          .lookupFunction<ffi.Void Function(ffi.Pointer<qpdf_data>), void Function(ffi.Pointer<qpdf_data>)>(
            'qpdf_cleanup',
          ),
      qpdf_read = library
          .lookupFunction<
            ffi.Int32 Function(qpdf_data, ffi.Pointer<ffi.Char>, ffi.Pointer<ffi.Char>),
            int Function(qpdf_data, ffi.Pointer<ffi.Char>, ffi.Pointer<ffi.Char>)
          >('qpdf_read'),
      qpdf_has_error = library.lookupFunction<ffi.Int32 Function(qpdf_data), int Function(qpdf_data)>(
        'qpdf_has_error',
      ),
      qpdf_get_error = library.lookupFunction<qpdf_error Function(qpdf_data), qpdf_error Function(qpdf_data)>(
        'qpdf_get_error',
      ),
      qpdf_get_error_full_text = library
          .lookupFunction<
            ffi.Pointer<ffi.Char> Function(qpdf_data, qpdf_error),
            ffi.Pointer<ffi.Char> Function(qpdf_data, qpdf_error)
          >('qpdf_get_error_full_text'),
      qpdf_is_encrypted = library.lookupFunction<ffi.Int32 Function(qpdf_data), int Function(qpdf_data)>(
        'qpdf_is_encrypted',
      ),
      qpdf_get_num_pages = library.lookupFunction<ffi.Int32 Function(qpdf_data), int Function(qpdf_data)>(
        'qpdf_get_num_pages',
      ),
      qpdflogger_default_logger = library
          .lookupFunction<qpdflogger_handle Function(), qpdflogger_handle Function()>('qpdflogger_default_logger'),
      qpdflogger_create = library.lookupFunction<qpdflogger_handle Function(), qpdflogger_handle Function()>(
        'qpdflogger_create',
      ),
      qpdflogger_cleanup = library
          .lookupFunction<
            ffi.Void Function(ffi.Pointer<qpdflogger_handle>),
            void Function(ffi.Pointer<qpdflogger_handle>)
          >('qpdflogger_cleanup'),
      qpdflogger_set_error = library
          .lookupFunction<
            ffi.Void Function(qpdflogger_handle, ffi.Int32, ffi.Pointer<ffi.NativeFunction<qpdf_log_fn_native>>, ffi.Pointer<ffi.Void>),
            void Function(qpdflogger_handle, int, ffi.Pointer<ffi.NativeFunction<qpdf_log_fn_native>>, ffi.Pointer<ffi.Void>)
          >('qpdflogger_set_error');

  // FULL INTERFACE (qpdfjob-c.h)
  final qpdfjob_handle Function() qpdfjob_init;
  final void Function(ffi.Pointer<qpdfjob_handle>) qpdfjob_cleanup;
  final int Function(qpdfjob_handle, ffi.Pointer<ffi.Char>) qpdfjob_initialize_from_json;
  final int Function(qpdfjob_handle) qpdfjob_run;
  final void Function(qpdfjob_handle, ffi.Pointer<ffi.NativeFunction<qpdf_report_progress_fn_native>>, ffi.Pointer<ffi.Void>)
  qpdfjob_register_progress_reporter;
  final void Function(qpdfjob_handle, qpdflogger_handle) qpdfjob_set_logger;
  final qpdflogger_handle Function(qpdfjob_handle) qpdfjob_get_logger;

  // inspect (qpdf-c.h)
  final qpdf_data Function() qpdf_init;
  final void Function(ffi.Pointer<qpdf_data>) qpdf_cleanup;
  final int Function(qpdf_data, ffi.Pointer<ffi.Char>, ffi.Pointer<ffi.Char>) qpdf_read;
  final int Function(qpdf_data) qpdf_has_error;
  final qpdf_error Function(qpdf_data) qpdf_get_error;
  final ffi.Pointer<ffi.Char> Function(qpdf_data, qpdf_error) qpdf_get_error_full_text;
  final int Function(qpdf_data) qpdf_is_encrypted;
  final int Function(qpdf_data) qpdf_get_num_pages;

  // logger (qpdflogger-c.h)
  final qpdflogger_handle Function() qpdflogger_default_logger;
  final qpdflogger_handle Function() qpdflogger_create;
  final void Function(ffi.Pointer<qpdflogger_handle>) qpdflogger_cleanup;
  final void Function(qpdflogger_handle, int, ffi.Pointer<ffi.NativeFunction<qpdf_log_fn_native>>, ffi.Pointer<ffi.Void>)
  qpdflogger_set_error;
}
