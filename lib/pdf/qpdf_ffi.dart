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
// **M-E0 갱신(`_workspace/31_architect_external_compress_l2.md` §1.2/§2.7/§3.2, 2026-08-19)**:
// `ffigen.yaml`을 다시 실행해도 이 호스트는 여전히 `libclang.dll`이 없어(`dart run ffigen
// --config ffigen.yaml` 재시도 결과 M-Q2와 동일한
// "Couldn't find dynamic library in default locations" 실패) 자동 생성이 안 된다. L2-ext
// 3-패스 왕복(§2.2)에 필요한 qpdf_oh_* 30개(§1.2 실검증 목록)를 **다시 手写**로 추가했다.
// 기존 19개 심볼(qpdfjob_*/qpdf_init~get_num_pages/qpdflogger_*)의 타입·시그니처는 손대지
// 않았다 -- 추가만 했다.
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

/// `qpdf-c.h`의 `typedef unsigned int qpdf_oh;`(M-E0 신설). **포인터가 아니다** — qpdf_data
/// 내부 객체 테이블의 인덱스일 뿐인 불투명 정수 핸들이다(qpdf-c.h 601행 주석: "qpdf_oh는 qpdf_data
/// 내부 객체 테이블의 인덱스"). 항상 그 값을 만든 `qpdf_data`와 짝을 지어서만 의미가 있다 — 다른
/// `qpdf_data`의 `qpdf_oh`를 섞어 쓰면 조용히 잘못된 객체를 가리킬 수 있다(qpdf-c.h 888행 주석).
typedef qpdf_oh = ffi.Uint32;

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

// ── Constants.h(qpdf-c.h가 트랜지티브로 요구): enum qpdf_stream_decode_level_e (M-E0 신설) ──
// `qpdf_oh_get_stream_data`의 `decode_level` 파라미터. 이 확장은 `qpdf_dl_none`만 쓴다
// (§1.5 — DCTDecode 스트림의 원시 바이트 = 완전한 JPEG 파일을 얻기 위함, `qpdf_dl_all`은 절대
// 사용 금지). 나머지 값도 순서가 헤더와 정확히 일치해야 하므로 전부 옮겨 적는다.
abstract final class qpdf_stream_decode_level_e {
  static const int qpdf_dl_none = 0;
  static const int qpdf_dl_generalized = 1;
  static const int qpdf_dl_specialized = 2;
  static const int qpdf_dl_all = 3;
}

// ── Constants.h: enum qpdf_object_type_e (필요한 값만, M-E0 신설) ──────────────────────────
// `qpdf_oh_get_type_code`의 반환값. 이 확장은 스트림/딕셔너리 판별에만 쓴다 -- 헤더의 선언
// 순서(0-based) 그대로 옮겨 적었다(Constants.h 109~130행).
abstract final class qpdf_object_type_e {
  static const int ot_uninitialized = 0;
  static const int ot_reserved = 1;
  static const int ot_null = 2;
  static const int ot_boolean = 3;
  static const int ot_integer = 4;
  static const int ot_real = 5;
  static const int ot_string = 6;
  static const int ot_name = 7;
  static const int ot_array = 8;
  static const int ot_dictionary = 9;
  static const int ot_stream = 10;
  static const int ot_operator = 11;
  static const int ot_inlineimage = 12;
  static const int ot_unresolved = 13;
  static const int ot_destroyed = 14;
  static const int ot_reference = 15;
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
          >('qpdflogger_set_error'),
      // ── M-E0 신설: L2-ext 3-패스 왕복(qpdf-c.h "STREAM FUNCTIONS"/"PAGE FUNCTIONS"/object graph) ──
      qpdf_oh_get_stream_data = library
          .lookupFunction<
            ffi.Int32 Function(qpdf_data, qpdf_oh, ffi.Int32, ffi.Pointer<ffi.Int32>, ffi.Pointer<ffi.Pointer<ffi.Uint8>>, ffi.Pointer<ffi.Size>),
            int Function(qpdf_data, int, int, ffi.Pointer<ffi.Int32>, ffi.Pointer<ffi.Pointer<ffi.Uint8>>, ffi.Pointer<ffi.Size>)
          >('qpdf_oh_get_stream_data'),
      qpdf_oh_replace_stream_data = library
          .lookupFunction<
            ffi.Void Function(qpdf_data, qpdf_oh, ffi.Pointer<ffi.Uint8>, ffi.Size, qpdf_oh, qpdf_oh),
            void Function(qpdf_data, int, ffi.Pointer<ffi.Uint8>, int, int, int)
          >('qpdf_oh_replace_stream_data'),
      qpdf_oh_free_buffer = library
          .lookupFunction<
            ffi.Void Function(ffi.Pointer<ffi.Pointer<ffi.Uint8>>),
            void Function(ffi.Pointer<ffi.Pointer<ffi.Uint8>>)
          >('qpdf_oh_free_buffer'),
      qpdf_get_page_n = library
          .lookupFunction<qpdf_oh Function(qpdf_data, ffi.Size), int Function(qpdf_data, int)>('qpdf_get_page_n'),
      qpdf_push_inherited_attributes_to_page = library
          .lookupFunction<ffi.Int32 Function(qpdf_data), int Function(qpdf_data)>(
            'qpdf_push_inherited_attributes_to_page',
          ),
      qpdf_oh_get_key = library
          .lookupFunction<
            qpdf_oh Function(qpdf_data, qpdf_oh, ffi.Pointer<ffi.Char>),
            int Function(qpdf_data, int, ffi.Pointer<ffi.Char>)
          >('qpdf_oh_get_key'),
      qpdf_oh_has_key = library
          .lookupFunction<
            ffi.Int32 Function(qpdf_data, qpdf_oh, ffi.Pointer<ffi.Char>),
            int Function(qpdf_data, int, ffi.Pointer<ffi.Char>)
          >('qpdf_oh_has_key'),
      qpdf_oh_get_dict = library.lookupFunction<qpdf_oh Function(qpdf_data, qpdf_oh), int Function(qpdf_data, int)>(
        'qpdf_oh_get_dict',
      ),
      qpdf_oh_is_stream = library
          .lookupFunction<ffi.Int32 Function(qpdf_data, qpdf_oh), int Function(qpdf_data, int)>('qpdf_oh_is_stream'),
      qpdf_oh_is_dictionary_of_type = library
          .lookupFunction<
            ffi.Int32 Function(qpdf_data, qpdf_oh, ffi.Pointer<ffi.Char>, ffi.Pointer<ffi.Char>),
            int Function(qpdf_data, int, ffi.Pointer<ffi.Char>, ffi.Pointer<ffi.Char>)
          >('qpdf_oh_is_dictionary_of_type'),
      qpdf_oh_get_type_code = library
          .lookupFunction<ffi.Int32 Function(qpdf_data, qpdf_oh), int Function(qpdf_data, int)>(
            'qpdf_oh_get_type_code',
          ),
      qpdf_oh_begin_dict_key_iter = library
          .lookupFunction<ffi.Void Function(qpdf_data, qpdf_oh), void Function(qpdf_data, int)>(
            'qpdf_oh_begin_dict_key_iter',
          ),
      qpdf_oh_dict_more_keys = library.lookupFunction<ffi.Int32 Function(qpdf_data), int Function(qpdf_data)>(
        'qpdf_oh_dict_more_keys',
      ),
      qpdf_oh_dict_next_key = library
          .lookupFunction<ffi.Pointer<ffi.Char> Function(qpdf_data), ffi.Pointer<ffi.Char> Function(qpdf_data)>(
            'qpdf_oh_dict_next_key',
          ),
      qpdf_oh_replace_key = library
          .lookupFunction<
            ffi.Void Function(qpdf_data, qpdf_oh, ffi.Pointer<ffi.Char>, qpdf_oh),
            void Function(qpdf_data, int, ffi.Pointer<ffi.Char>, int)
          >('qpdf_oh_replace_key'),
      qpdf_oh_remove_key = library
          .lookupFunction<
            ffi.Void Function(qpdf_data, qpdf_oh, ffi.Pointer<ffi.Char>),
            void Function(qpdf_data, int, ffi.Pointer<ffi.Char>)
          >('qpdf_oh_remove_key'),
      qpdf_oh_is_name_and_equals = library
          .lookupFunction<
            ffi.Int32 Function(qpdf_data, qpdf_oh, ffi.Pointer<ffi.Char>),
            int Function(qpdf_data, int, ffi.Pointer<ffi.Char>)
          >('qpdf_oh_is_name_and_equals'),
      qpdf_oh_new_integer = library
          .lookupFunction<qpdf_oh Function(qpdf_data, ffi.Int64), int Function(qpdf_data, int)>(
            'qpdf_oh_new_integer',
          ),
      qpdf_oh_new_name = library
          .lookupFunction<qpdf_oh Function(qpdf_data, ffi.Pointer<ffi.Char>), int Function(qpdf_data, ffi.Pointer<ffi.Char>)>(
            'qpdf_oh_new_name',
          ),
      qpdf_oh_new_null = library.lookupFunction<qpdf_oh Function(qpdf_data), int Function(qpdf_data)>(
        'qpdf_oh_new_null',
      ),
      qpdf_oh_get_array_n_items = library
          .lookupFunction<ffi.Int32 Function(qpdf_data, qpdf_oh), int Function(qpdf_data, int)>(
            'qpdf_oh_get_array_n_items',
          ),
      qpdf_oh_get_array_item = library
          .lookupFunction<qpdf_oh Function(qpdf_data, qpdf_oh, ffi.Int32), int Function(qpdf_data, int, int)>(
            'qpdf_oh_get_array_item',
          ),
      qpdf_oh_get_int_value_as_int = library
          .lookupFunction<ffi.Int32 Function(qpdf_data, qpdf_oh), int Function(qpdf_data, int)>(
            'qpdf_oh_get_int_value_as_int',
          ),
      qpdf_oh_get_object_id = library
          .lookupFunction<ffi.Int32 Function(qpdf_data, qpdf_oh), int Function(qpdf_data, int)>(
            'qpdf_oh_get_object_id',
          ),
      qpdf_oh_get_generation = library
          .lookupFunction<ffi.Int32 Function(qpdf_data, qpdf_oh), int Function(qpdf_data, int)>(
            'qpdf_oh_get_generation',
          ),
      qpdf_get_object_by_id = library
          .lookupFunction<qpdf_oh Function(qpdf_data, ffi.Int32, ffi.Int32), int Function(qpdf_data, int, int)>(
            'qpdf_get_object_by_id',
          ),
      qpdf_oh_release_all = library.lookupFunction<ffi.Void Function(qpdf_data), void Function(qpdf_data)>(
        'qpdf_oh_release_all',
      ),
      qpdf_init_write = library
          .lookupFunction<
            ffi.Int32 Function(qpdf_data, ffi.Pointer<ffi.Char>),
            int Function(qpdf_data, ffi.Pointer<ffi.Char>)
          >('qpdf_init_write'),
      qpdf_write = library.lookupFunction<ffi.Int32 Function(qpdf_data), int Function(qpdf_data)>('qpdf_write'),
      // ── M-E2 신설: `/ImageMask` 판정에 필요한 boolean 값 조회(qpdf-c.h 708행, 심볼 실검증 완료
      // -- `test/native/qpdf30.dll`에서 문자열 존재 확인). `QPDF_BOOL`은 `typedef int`(141행)다.
      qpdf_oh_get_bool_value = library
          .lookupFunction<ffi.Int32 Function(qpdf_data, qpdf_oh), int Function(qpdf_data, int)>(
            'qpdf_oh_get_bool_value',
          );

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

  // ── M-E0 신설: L2-ext 3-패스 왕복(§2.2) ── `qpdf_oh` 파라미터/반환은 전부 Dart `int`로 표현한다
  // (포인터가 아니라 `qpdf_data` 내부 인덱스이므로, §22의 "qpdf_oh는 값이지 포인터가 아니다" 주석
  // 그대로). 반드시 그 값을 만든 것과 같은 `qpdf_data`와 짝지어 호출해야 한다(qpdf-c.h 888행).
  final int Function(qpdf_data, int stream_oh, int decode_level, ffi.Pointer<ffi.Int32> filtered, ffi.Pointer<ffi.Pointer<ffi.Uint8>> bufp, ffi.Pointer<ffi.Size> len)
  qpdf_oh_get_stream_data;
  final void Function(qpdf_data, int stream_oh, ffi.Pointer<ffi.Uint8> buf, int len, int filter, int decode_parms)
  qpdf_oh_replace_stream_data;
  final void Function(ffi.Pointer<ffi.Pointer<ffi.Uint8>> bufp) qpdf_oh_free_buffer;
  final int Function(qpdf_data, int zeroBasedIndex) qpdf_get_page_n;
  final int Function(qpdf_data) qpdf_push_inherited_attributes_to_page;
  final int Function(qpdf_data, int oh, ffi.Pointer<ffi.Char> key) qpdf_oh_get_key;
  final int Function(qpdf_data, int oh, ffi.Pointer<ffi.Char> key) qpdf_oh_has_key;
  final int Function(qpdf_data, int oh) qpdf_oh_get_dict;
  final int Function(qpdf_data, int oh) qpdf_oh_is_stream;
  final int Function(qpdf_data, int oh, ffi.Pointer<ffi.Char> type, ffi.Pointer<ffi.Char> subtype)
  qpdf_oh_is_dictionary_of_type;
  final int Function(qpdf_data, int oh) qpdf_oh_get_type_code;
  final void Function(qpdf_data, int dict) qpdf_oh_begin_dict_key_iter;
  final int Function(qpdf_data) qpdf_oh_dict_more_keys;
  final ffi.Pointer<ffi.Char> Function(qpdf_data) qpdf_oh_dict_next_key;
  final void Function(qpdf_data, int oh, ffi.Pointer<ffi.Char> key, int item) qpdf_oh_replace_key;
  final void Function(qpdf_data, int oh, ffi.Pointer<ffi.Char> key) qpdf_oh_remove_key;
  final int Function(qpdf_data, int oh, ffi.Pointer<ffi.Char> name) qpdf_oh_is_name_and_equals;
  final int Function(qpdf_data, int value) qpdf_oh_new_integer;
  final int Function(qpdf_data, ffi.Pointer<ffi.Char> name) qpdf_oh_new_name;
  final int Function(qpdf_data) qpdf_oh_new_null;
  final int Function(qpdf_data, int oh) qpdf_oh_get_array_n_items;
  final int Function(qpdf_data, int oh, int n) qpdf_oh_get_array_item;
  final int Function(qpdf_data, int oh) qpdf_oh_get_int_value_as_int;
  final int Function(qpdf_data, int oh) qpdf_oh_get_object_id;
  final int Function(qpdf_data, int oh) qpdf_oh_get_generation;
  final int Function(qpdf_data, int objid, int generation) qpdf_get_object_by_id;
  final void Function(qpdf_data) qpdf_oh_release_all;
  final int Function(qpdf_data, ffi.Pointer<ffi.Char> filename) qpdf_init_write;
  final int Function(qpdf_data) qpdf_write;
  final int Function(qpdf_data, int oh) qpdf_oh_get_bool_value;
}
