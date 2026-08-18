/// qpdf 저장·병합·발췌 워커. §15(`_workspace/15_architect_qpdf_migration.md`) §5.2/§5.3/§5.4/§5.7의
/// 확정 설계를 구현한다.
///
/// **신설 불변식(§5.7, 그대로 구현)**
/// 1. `qpdf_ffi.dart`(생성물)와 이 파일 외 어떤 파일도 `dart:ffi`를 import하지 않는다.
/// 2. 이 파일은 `pdfrx`·`pdfrx_engine`을 import하지 않는다 -- pdfrx와 qpdf가 같은 isolate에서
///    만나지 않게 한다.
/// 3. `DynamicLibrary.open`은 워커 isolate(`_isolateMain`, `Isolate.spawn`으로 생성) 안에서
///    호출한다. 핸들·포인터는 isolate 경계를 넘기지 않는다(넘길 수 없다) -- 메인에 돌려주는 것은
///    `Map<String,Object?>`(원시 타입)뿐이다.
/// 4. `package:image`, `package:pdf/`는 이 파일에 들이지 않는다(§5.6 2-키 분리).
///
/// **잡 스펙 화이트리스트(§5.3)**: 공개된 5개 빌더(`buildSaveJob`/`buildRotateJob`/`buildMergeJob`/
/// `buildSplitJob`/`buildCompressJob`)만 잡 스펙을 만든다. 이 함수들은 순수 함수이며 파일 경로·
/// 페이지 인덱스 같은 구조화된 값만 받는다 -- 외부에서 임의 JSON 문자열이나 argv를 주입하는 공개
/// 진입점은 없다. 아래 금지 키는 이 파일 어디에도 리터럴로 등장하지 않는다(자동 검사 16 대응):
/// `replaceInput`, `streamData: uncompress`, `splitPages`, `qdf`, `encrypt`, `linearize`.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart' as pkg_ffi;

import '../core/cancel_token.dart';
import '../core/progress.dart';
import 'qpdf_ffi.dart';

// ─────────────────────────────────────────────────────────────────────────
// §5.2 확정: 모든 저장 잡에 공통 적용하는 쓰기 옵션.
// 6.6배 팽창의 세 원인(폰트 객체 복제/콘텐츠 비압축 재기록/오브젝트 스트림 해체)을 각각 겨냥한다.
// 리터럴은 이 한 곳에만 존재한다 -- 잡 빌더는 이 상수를 펼쳐 넣기만 한다.
const Map<String, Object?> _commonWriteOptions = {
  'objectStreams': 'generate',
  'compressStreams': 'y',
  'recompressFlate': '',
  'compressionLevel': '9',
  'removeUnreferencedResources': 'auto',
  'normalizeContent': 'n',
  // streamData는 기본값을 유지한다 -- "uncompress"를 여기 쓰지 않는 것 자체가 금지 키 봉쇄다.
};

/// 0-based 페이지 인덱스 목록을 qpdf range 문자열(1-based, 쉼표 나열)로 변환한다.
/// 순서를 그대로 보존한다 -- qpdf range는 나열 순서가 곧 출력 순서다(§5.2, 순서변경 지원 근거).
/// 압축(콤팩트 범위 표기, 예: "1-5")은 하지 않는다 -- 정확성이 축약보다 우선이다.
String _rangeFromIndices(List<int> zeroBasedIndices) {
  if (zeroBasedIndices.isEmpty) {
    throw ArgumentError('pageIndices must not be empty');
  }
  return zeroBasedIndices.map((i) => (i + 1).toString()).join(',');
}

/// 회전 스펙을 만들 때 쓰는 한 페이지 항목. [sourceIndex]는 원본 문서의 0-based 페이지 번호,
/// [rotation]은 원본 회전에 **더해지는** 상대 회전(0/90/180/270) -- `PageRef.rotation`과 같은 의미.
class QpdfPageEntry {
  const QpdfPageEntry({required this.sourceIndex, this.rotation = 0})
    : assert(rotation == 0 || rotation == 90 || rotation == 180 || rotation == 270);
  final int sourceIndex;
  final int rotation;
}

/// qpdf `--rotate=+<angle>:<range>` 스펙 목록을 만든다. **range는 출력 페이지 위치(1-based)를
/// 가리킨다 -- 원본 페이지 번호가 아니다.** 이는 추정이 아니라 실측으로 확인했다: 호스트 CLI로
/// 3페이지 문서를 [2,1,3] 순서로 재배열하며 "range=1"에 회전을 걸었을 때, 결과 파일에서
/// `/Rotate`가 실제로 붙은 것은 출력 1번째 페이지(=원본 2페이지)였다(`--qdf --object-streams=disable`
/// 덤프로 오브젝트 순서 확인, `job-json-file`로 JSON 잡 스펙도 동일 결과로 재확인).
/// 항상 상대 회전(`+angle`)을 쓴다 -- `PageRef.rotation`의 의미(원본에 더해지는 값)와 일치시키기
/// 위함이며, qpdf CLI의 절대 회전(부호 없는 `angle:range`)은 쓰지 않는다.
List<String> _rotateSpecs(List<QpdfPageEntry> orderedPages) {
  final byAngle = <int, List<int>>{}; // rotation -> [출력 1-based 위치...]
  for (var i = 0; i < orderedPages.length; i++) {
    final rotation = orderedPages[i].rotation;
    if (rotation == 0) continue;
    (byAngle[rotation] ??= []).add(i + 1);
  }
  return [for (final entry in byAngle.entries) '+${entry.key}:${entry.value.join(',')}'];
}

// ─────────────────────────────────────────────────────────────────────────
// §5.3 잡 빌더 5종. 순수 함수 -- FFI·파일 I/O를 하지 않는다. 단위 테스트로 독립 검증 가능.

/// 삭제·순서변경·발췌(회전 없음). 단일 소스, [pageIndices] 순서가 결과 페이지 순서다(0-based).
Map<String, Object?> buildSaveJob({required String sourcePath, required String outputPath, required List<int> pageIndices}) {
  return {
    'inputFile': sourcePath,
    'pages': [
      {'file': sourcePath, 'range': _rangeFromIndices(pageIndices)},
    ],
    'outputFile': outputPath,
    ..._commonWriteOptions,
  };
}

/// 삭제·순서변경·발췌 + 회전. [pages] 순서가 결과 페이지 순서이며, 각 항목의 [QpdfPageEntry.rotation]이
/// 해당 출력 위치에 적용된다. 재인코딩 없음 -- `/Rotate` 속성만 바뀐다(pdf-core.md 불변식 2).
Map<String, Object?> buildRotateJob({required String sourcePath, required String outputPath, required List<QpdfPageEntry> pages}) {
  final job = buildSaveJob(sourcePath: sourcePath, outputPath: outputPath, pageIndices: [for (final p in pages) p.sourceIndex]);
  final rotateSpecs = _rotateSpecs(pages);
  if (rotateSpecs.isNotEmpty) {
    job['rotate'] = rotateSpecs;
  }
  return job;
}

/// 다중 소스를 순서대로 이어붙인다. `--empty`로 첫 문서 메타데이터 상속 문제를 피한다(E17).
Map<String, Object?> buildMergeJob({required List<String> sourcePdfPaths, required String outputPath}) {
  if (sourcePdfPaths.isEmpty) {
    throw ArgumentError('sourcePdfPaths must not be empty');
  }
  return {
    'empty': '',
    'pages': [for (final p in sourcePdfPaths) {'file': p}],
    'outputFile': outputPath,
    ..._commonWriteOptions,
  };
}

/// 선택 페이지로 새 문서를 만든다(나누기). `buildSaveJob`과 qpdf 대응이 동일하다(§5.2) --
/// `--split-pages`(다중 출력)는 스테이징 규약과 충돌하므로 절대 쓰지 않는다.
Map<String, Object?> buildSplitJob({required String sourcePath, required String outputPath, required List<int> pageIndices}) =>
    buildSaveJob(sourcePath: sourcePath, outputPath: outputPath, pageIndices: pageIndices);

/// L1 무손실 최적화(§6.1) 전용 -- 페이지 선택 없이 전체 문서를 공통 쓰기 옵션으로 다시 쓴다.
Map<String, Object?> buildCompressJob({required String sourcePath, required String outputPath}) {
  return {'inputFile': sourcePath, 'outputFile': outputPath, ..._commonWriteOptions};
}

// ─────────────────────────────────────────────────────────────────────────
// 잡 실행. 5개 공개 진입점이 각자의 빌더로 스펙을 만든 뒤 동일한 워커 isolate 실행 경로를 탄다.

/// qpdf 잡 실행 결과. `pdf_engine.dart`가 소비할 원시 타입만 담는다(§8.2 규칙).
/// 성공: `{'ok': true, 'bytes': int, 'pageCount': int}`
/// 실패: `{'ok': false, 'error': <code>, 'detail': String?}`
/// (`code` ∈ missing/corrupted/cancelled/unknown -- `pdf_engine.dart`의 `_failureFromErrorMap`과
/// 동일한 코드 집합을 쓴다, `PdfFailure` 매핑은 그 파일의 책임)
typedef QpdfJobResult = Map<String, Object?>;

Future<QpdfJobResult> runSaveJob({
  required String sourcePath,
  required String outputPath,
  required List<int> pageIndices,
  void Function(PdfProgress progress)? onProgress,
  CancelToken? cancelToken,
  String? libraryPathOverride,
}) => _executeJob(
  jobSpec: buildSaveJob(sourcePath: sourcePath, outputPath: outputPath, pageIndices: pageIndices),
  outputPath: outputPath,
  onProgress: onProgress,
  cancelToken: cancelToken,
  libraryPathOverride: libraryPathOverride,
);

Future<QpdfJobResult> runRotateJob({
  required String sourcePath,
  required String outputPath,
  required List<QpdfPageEntry> pages,
  void Function(PdfProgress progress)? onProgress,
  CancelToken? cancelToken,
  String? libraryPathOverride,
}) => _executeJob(
  jobSpec: buildRotateJob(sourcePath: sourcePath, outputPath: outputPath, pages: pages),
  outputPath: outputPath,
  onProgress: onProgress,
  cancelToken: cancelToken,
  libraryPathOverride: libraryPathOverride,
);

Future<QpdfJobResult> runMergeJob({
  required List<String> sourcePdfPaths,
  required String outputPath,
  void Function(PdfProgress progress)? onProgress,
  CancelToken? cancelToken,
  String? libraryPathOverride,
}) => _executeJob(
  jobSpec: buildMergeJob(sourcePdfPaths: sourcePdfPaths, outputPath: outputPath),
  outputPath: outputPath,
  onProgress: onProgress,
  cancelToken: cancelToken,
  libraryPathOverride: libraryPathOverride,
);

Future<QpdfJobResult> runSplitJob({
  required String sourcePath,
  required String outputPath,
  required List<int> pageIndices,
  void Function(PdfProgress progress)? onProgress,
  CancelToken? cancelToken,
  String? libraryPathOverride,
}) => _executeJob(
  jobSpec: buildSplitJob(sourcePath: sourcePath, outputPath: outputPath, pageIndices: pageIndices),
  outputPath: outputPath,
  onProgress: onProgress,
  cancelToken: cancelToken,
  libraryPathOverride: libraryPathOverride,
);

Future<QpdfJobResult> runCompressJob({
  required String sourcePath,
  required String outputPath,
  void Function(PdfProgress progress)? onProgress,
  CancelToken? cancelToken,
  String? libraryPathOverride,
}) => _executeJob(
  jobSpec: buildCompressJob(sourcePath: sourcePath, outputPath: outputPath),
  outputPath: outputPath,
  onProgress: onProgress,
  cancelToken: cancelToken,
  libraryPathOverride: libraryPathOverride,
);

/// inspect(§5.2 표) -- `qpdfjob` 아님. `qpdf_read` -> `qpdf_is_encrypted` -> `qpdf_get_num_pages`.
/// 출력 파일을 만들지 않는 유일한 경로이므로 워커 isolate 스폰 없이 동기적으로 실행해도 무방하나,
/// 다른 잡과의 일관성 및 대용량 문서에서의 UI 정지 방지를 위해 같은 워커 경로를 탄다.
Future<QpdfJobResult> runInspect({required String pdfPath, String? password, String? libraryPathOverride}) async {
  final receivePort = ReceivePort();
  await Isolate.spawn(
    _inspectIsolateMain,
    _InspectRequest(
      sendPort: receivePort.sendPort,
      pdfPath: pdfPath,
      password: password,
      libraryPath: libraryPathOverride ?? _defaultLibraryPath(),
    ),
  );
  final result = await receivePort.first as Map<String, Object?>;
  receivePort.close();
  return result;
}

/// Android에서는 `.so`가 `System.loadLibrary`가 찾는 표준 위치(APK jniLibs → 앱 네이티브 라이브러리
/// 디렉터리)에 있으므로 이름만으로 연다. 다른 플랫폼(호스트 테스트)은 항상 [libraryPathOverride]를
/// 명시적으로 넘겨야 한다 -- 이 함수는 그 경우 예외를 던진다(무음으로 잘못된 라이브러리를 찾지 않는다).
String _defaultLibraryPath() {
  if (Platform.isAndroid) return 'libqpdf.so';
  throw StateError(
    'qpdf library path must be supplied explicitly on this platform (no libqpdf.so default outside Android)',
  );
}

// ── isolate 경계를 넘는 메시지. 원시 타입만 담는다(§8.2/§5.7 불변식 4). ──────────────────────

class _JobRequest {
  const _JobRequest({
    required this.sendPort,
    required this.progressPort,
    required this.jobSpecJson,
    required this.libraryPath,
  });
  final SendPort sendPort;
  final SendPort? progressPort;
  final String jobSpecJson;
  final String libraryPath;
}

class _InspectRequest {
  const _InspectRequest({required this.sendPort, required this.pdfPath, required this.password, required this.libraryPath});
  final SendPort sendPort;
  final String pdfPath;
  final String? password;
  final String libraryPath;
}

/// §5.4 확정 규칙 구현: 잡 진입 직전 마지막 취소 확인. 잡이 시작된 뒤 취소되면 완료를 기다린 뒤
/// 출력 파일을 지우고 `{'ok': false, 'error': 'cancelled'}`를 반환한다(부분 산출물 없음).
Future<QpdfJobResult> _executeJob({
  required Map<String, Object?> jobSpec,
  required String outputPath,
  void Function(PdfProgress progress)? onProgress,
  CancelToken? cancelToken,
  String? libraryPathOverride,
}) async {
  if (cancelToken?.isCancelled ?? false) {
    return const {'ok': false, 'error': 'cancelled'};
  }

  final spec = Map<String, Object?>.of(jobSpec);
  final resultPort = ReceivePort();
  final progressPort = ReceivePort();
  StreamSubscription<Object?>? progressSub;
  if (onProgress != null) {
    spec['progress'] = ''; // qpdfjob은 progress가 명시적으로 요청된 잡에서만 리포터를 호출한다.
    progressSub = progressPort.listen((msg) {
      if (msg is Map) {
        onProgress(PdfProgress.fromMap(msg.cast<String, Object?>()));
      }
    });
  }

  Isolate? isolate;
  QpdfJobResult result;
  try {
    isolate = await Isolate.spawn(
      _jobIsolateMain,
      _JobRequest(
        sendPort: resultPort.sendPort,
        progressPort: onProgress != null ? progressPort.sendPort : null,
        jobSpecJson: jsonEncode(spec),
        libraryPath: libraryPathOverride ?? _defaultLibraryPath(),
      ),
    );
    final raw = await resultPort.first;
    result = (raw as Map).cast<String, Object?>();
  } finally {
    resultPort.close();
    progressPort.close();
    await progressSub?.cancel();
    isolate?.kill(priority: Isolate.immediate);
  }

  if (cancelToken?.isCancelled ?? false) {
    if (result['ok'] == true) {
      try {
        await File(outputPath).delete();
      } catch (_) {
        // 최선 노력 -- 상위(Workspace.rollbackStaging)가 다시 정리한다.
      }
    }
    return const {'ok': false, 'error': 'cancelled'};
  }

  return result;
}

/// 워커 isolate 진입점(잡 실행). 이 함수 밖으로 `qpdf_data`/`qpdfjob_handle` 등 네이티브 포인터가
/// 나가지 않는다 -- 돌려주는 것은 [SendPort.send]로 보낼 수 있는 원시 `Map`뿐이다.
void _jobIsolateMain(_JobRequest req) {
  final library = ffi.DynamicLibrary.open(req.libraryPath);
  final bindings = QpdfBindings(library);
  final result = _runJobSync(bindings: bindings, jobJson: req.jobSpecJson, progressPort: req.progressPort);
  req.sendPort.send(result);
}

QpdfJobResult _runJobSync({required QpdfBindings bindings, required String jobJson, SendPort? progressPort}) {
  final handlePtr = pkg_ffi.malloc<qpdfjob_handle>();
  final loggerPtr = pkg_ffi.malloc<qpdflogger_handle>();
  final errorBuffer = StringBuffer();
  ffi.NativeCallable<qpdf_log_fn_native>? logCallable;
  ffi.NativeCallable<qpdf_report_progress_fn_native>? progressCallable;
  ffi.Pointer<pkg_ffi.Utf8>? jobJsonPtr;

  try {
    handlePtr.value = bindings.qpdfjob_init();
    final job = handlePtr.value;
    if (job == ffi.nullptr) {
      return const {'ok': false, 'error': 'unknown', 'detail': 'qpdfjob_init returned null'};
    }

    // 커스텀 로거: qpdf가 stderr로 내보내는 에러/경고 텍스트를 캡처한다(qpdfjob-c.h에 잡 레벨
    // 에러 텍스트 조회 함수가 없다 -- E7). 반환 0 = 성공(qpdf_log_fn_t 계약).
    logCallable = ffi.NativeCallable<qpdf_log_fn_native>.isolateLocal((
      ffi.Pointer<ffi.Char> data,
      int len,
      ffi.Pointer<ffi.Void> udata,
    ) {
      if (len > 0) {
        final bytes = data.cast<ffi.Uint8>().asTypedList(len);
        errorBuffer.write(utf8.decode(bytes, allowMalformed: true));
      }
      return 0;
    }, exceptionalReturn: 1);

    loggerPtr.value = bindings.qpdflogger_create();
    bindings.qpdflogger_set_error(loggerPtr.value, qpdf_log_dest_e.qpdf_log_dest_custom, logCallable.nativeFunction, ffi.nullptr);
    bindings.qpdfjob_set_logger(job, loggerPtr.value);

    if (progressPort != null) {
      progressCallable = ffi.NativeCallable<qpdf_report_progress_fn_native>.isolateLocal((int percent, ffi.Pointer<ffi.Void> data) {
        progressPort.send(PdfProgress(phase: PdfPhase.writing, done: percent, total: 100).toMap());
      });
      bindings.qpdfjob_register_progress_reporter(job, progressCallable.nativeFunction, ffi.nullptr);
    }

    jobJsonPtr = jobJson.toNativeUtf8();
    final initRc = bindings.qpdfjob_initialize_from_json(job, jobJsonPtr.cast());
    if (initRc != 0) {
      return {'ok': false, 'error': 'unknown', 'detail': _detailOrCode('initialize_from_json', initRc, errorBuffer)};
    }

    final runRc = bindings.qpdfjob_run(job);
    if (runRc != 0) {
      return {'ok': false, 'error': _errorCodeFor(errorBuffer), 'detail': _detailOrCode('run', runRc, errorBuffer)};
    }
  } finally {
    if (progressCallable != null) progressCallable.close();
    if (logCallable != null) logCallable.close();
    if (handlePtr.value != ffi.nullptr) bindings.qpdfjob_cleanup(handlePtr);
    if (loggerPtr.value != ffi.nullptr) bindings.qpdflogger_cleanup(loggerPtr);
    if (jobJsonPtr != null) pkg_ffi.malloc.free(jobJsonPtr);
    pkg_ffi.malloc.free(handlePtr);
    pkg_ffi.malloc.free(loggerPtr);
  }

  // 잡은 성공했다. 결과 파일에서 바이트·페이지 수를 얻는다(qpdfjob-c.h는 이를 직접 주지 않는다).
  final outputPathMatch = _outputPathFromJson(jobJson);
  if (outputPathMatch == null) {
    return const {'ok': false, 'error': 'unknown', 'detail': 'outputFile missing from job spec'};
  }
  final outputFile = File(outputPathMatch);
  if (!outputFile.existsSync()) {
    return {'ok': false, 'error': 'unknown', 'detail': 'qpdf reported success but output file is missing: $outputPathMatch'};
  }
  final bytes = outputFile.lengthSync();
  final inspectResult = _inspectSync(bindings: bindings, pdfPath: outputPathMatch, password: null);
  if (inspectResult['ok'] != true) {
    return {'ok': false, 'error': 'unknown', 'detail': 'post-write inspect failed: ${inspectResult['detail']}'};
  }
  return {'ok': true, 'bytes': bytes, 'pageCount': inspectResult['pageCount']};
}

String _detailOrCode(String step, int rc, StringBuffer errorBuffer) {
  final captured = errorBuffer.toString().trim();
  return captured.isNotEmpty ? captured : '$step failed with exit code $rc';
}

/// qpdf 종료 코드 3(경고만)까지는 우리가 'unknown'으로 뭉뚱그리지 않고 캡처된 텍스트로 원인을
/// 추정한다 -- 정확한 코드 분류는 M-Q3에서 `PdfFailure` 매핑을 확정할 때 세분화한다(§ 미해결 항목).
String _errorCodeFor(StringBuffer errorBuffer) {
  final text = errorBuffer.toString().toLowerCase();
  if (text.contains('no such file') || text.contains('cannot open')) return 'missing';
  if (text.contains('password') || text.contains('encrypt')) return 'encrypted';
  if (text.contains('operation for a non-linearized') || text.contains('unable to find') || text.contains('expected')) {
    return 'corrupted';
  }
  return 'unknown';
}

/// jobJson에서 `"outputFile":"..."` 값을 뽑는다. jsonEncode로 우리가 직접 만든 스펙이므로 형태가
/// 고정돼 있다 -- 정식 JSON 파서 왕복 대신 가벼운 디코드로 충분하다.
String? _outputPathFromJson(String jobJson) {
  final decoded = jsonDecode(jobJson) as Map<String, Object?>;
  return decoded['outputFile'] as String?;
}

/// inspect isolate 진입점.
void _inspectIsolateMain(_InspectRequest req) {
  final library = ffi.DynamicLibrary.open(req.libraryPath);
  final bindings = QpdfBindings(library);
  final result = _inspectSync(bindings: bindings, pdfPath: req.pdfPath, password: req.password);
  req.sendPort.send(result);
}

/// `qpdf_init` → `qpdf_read` → `qpdf_is_encrypted` → `qpdf_get_num_pages` → `qpdf_cleanup`(§5.2 표).
/// 실패: `{'ok': false, 'error': 'missing'|'corrupted'|'encrypted'|'unknown', 'detail': String}`
/// 성공: `{'ok': true, 'pageCount': int, 'isEncrypted': bool, 'bytes': int}`
QpdfJobResult _inspectSync({required QpdfBindings bindings, required String pdfPath, String? password}) {
  final file = File(pdfPath);
  if (!file.existsSync()) {
    return {'ok': false, 'error': 'missing', 'detail': pdfPath};
  }
  final bytes = file.lengthSync();

  final dataPtr = pkg_ffi.malloc<qpdf_data>();
  ffi.Pointer<pkg_ffi.Utf8>? pathPtr;
  ffi.Pointer<pkg_ffi.Utf8>? passwordPtr;
  try {
    dataPtr.value = bindings.qpdf_init();
    final qpdf = dataPtr.value;
    pathPtr = pdfPath.toNativeUtf8();
    passwordPtr = password?.toNativeUtf8();
    final rc = bindings.qpdf_read(qpdf, pathPtr.cast(), passwordPtr?.cast() ?? ffi.nullptr);
    final hasError = bindings.qpdf_has_error(qpdf) != 0;
    if (rc != 0 || hasError) {
      final err = bindings.qpdf_get_error(qpdf);
      final textPtr = err == ffi.nullptr ? ffi.nullptr : bindings.qpdf_get_error_full_text(qpdf, err);
      final text = textPtr == ffi.nullptr ? 'qpdf_read failed (rc=$rc)' : textPtr.cast<pkg_ffi.Utf8>().toDartString();
      final isPasswordIssue = text.toLowerCase().contains('password') || text.toLowerCase().contains('encrypt');
      return {'ok': false, 'error': isPasswordIssue ? 'encrypted' : 'corrupted', 'detail': text};
    }
    final isEncrypted = bindings.qpdf_is_encrypted(qpdf) != 0;
    final pageCount = bindings.qpdf_get_num_pages(qpdf);
    if (pageCount < 0) {
      return const {'ok': false, 'error': 'corrupted', 'detail': 'qpdf_get_num_pages returned -1'};
    }
    return {'ok': true, 'pageCount': pageCount, 'isEncrypted': isEncrypted, 'bytes': bytes};
  } finally {
    if (dataPtr.value != ffi.nullptr) bindings.qpdf_cleanup(dataPtr);
    pkg_ffi.malloc.free(dataPtr);
    if (pathPtr != null) pkg_ffi.malloc.free(pathPtr);
    if (passwordPtr != null) pkg_ffi.malloc.free(passwordPtr);
  }
}
