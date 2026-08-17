/// 앱 작업공간 경로 + 스테이징 저장 트랜잭션 단일 구현. (설계 §2.9, §7)
///
/// 레이아웃(모두 `root` 하위):
///   docs/`docId`/document.pdf         PdfEngine이 스테이징을 거쳐 쓴다
///   docs/`docId`/sources/             임포트·스캔 원본 복사본 (재편집용, 함부로 지우지 않는다)
///   docs/`docId`.tmp/                 저장 스테이징. 커밋 전까지만 존재
///   docs/`docId`.old/                 커밋 중 임시로만 존재
///   thumbs/`docId`.jpg                문서 대표 썸네일 (삭제해도 재생성 가능)
///   recent/`id`.pdf                   SAF/인텐트로 받은 외부 PDF 복사본
///   cache/`key`.jpg                   렌더 캐시. **항상 삭제해도 안전**
///
/// `docId`는 UUID v4다. 사용자 제목을 경로에 절대 쓰지 않는다(한글·특수문자 사고
/// 원천 차단, CLAUDE.md).
library;

import 'dart:io';

import 'package:flutter/services.dart'
    show MethodChannel, MissingPluginException, PlatformException;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

abstract interface class Workspace {
  /// 저장 전 여유 공간 확인(§7.3)에 쓰는 고정 안전 버퍼. SQLite WAL 저널·
  /// `thumbs/` 썸네일·`cache/` 렌더 캐시·파일시스템 블록 오버헤드를 흡수한다.
  /// 전부 이 클래스가 소유하는 디렉터리의 비용이므로 여기 둔다
  /// (2026-08-18 · spec-guardian I3 권고 · 아키텍트 승인).
  ///
  /// 필요 공간 산출식(`baselineBytes * 2 + spaceSafetyBufferBytes`) 자체는
  /// `SaveOp`/`GuardInput` 의미에 의존하므로 `DocumentRepository`에 남는다 —
  /// 상수만 여기로 옮긴다. 3주차 `pdf_compressor.dart`·편집 재저장도 같은
  /// 사전 점검을 할 때 이 상수를 참조한다(리터럴 복사 금지).
  static const int spaceSafetyBufferBytes = 20 * 1024 * 1024; // 20MB

  Future<void> ensureLayout(); // docs/ thumbs/ recent/ cache/ 생성

  String docDir(String docId); // <root>/docs/<docId>
  String docPdf(String docId); // <root>/docs/<docId>/document.pdf
  String sourcesDir(String docId);
  String sourcePdf(String docId, int n); // sources/src_<n>.pdf
  String sourceImage(String docId, int n); // sources/pages/<NNN>.jpg
  String thumb(String docId); // thumbs/<docId>.jpg
  String recentFile(String id); // recent/<id>.pdf
  String cacheFile(String key); // cache/<key>.jpg

  /// [2026-08-18 신설 · N2] 스테이징(`.tmp`) 스코프의 경로 3종. 경로 조립의
  /// 단일 소유자는 이 파일이다 — `DocumentRepository`가 `p.join`으로 스테이징
  /// 경로를 직접 조립하지 않는다. `sourcePdf`/`sourceImage`(최종 docDir 기준)와
  /// 파일명 규약(`src_<n>.pdf`, `pages/<NNN>.jpg`)이 정확히 대응해야 한다 —
  /// 한쪽만 바뀌면 커밋 후 DB 경로가 실제 파일과 어긋난다.
  String stagingDocPdf(String docId); // <root>/docs/<docId>.tmp/document.pdf
  String stagingSourcePdf(String docId, int n); // <docId>.tmp/sources/src_<n>.pdf
  String stagingSourceImage(String docId, int n); // <docId>.tmp/sources/pages/<NNN>.jpg

  /// 스테이징 디렉터리 생성. 저장은 항상 여기에 먼저 쓴다.
  /// 반환값은 스테이징 디렉터리 경로(`<root>/docs/<docId>.tmp`)다.
  /// `sources/pages/`까지 미리 만들어 둔다(§3.3 화이트리스트 대상 경로).
  Future<String> beginStaging(String docId); // <root>/docs/<docId>.tmp

  /// 원자적 반영: 기존 docDir이 있으면 `.old`로 옮긴 뒤 스테이징을 최종 경로로
  /// rename하고 `.old`를 지운다. **주의(설계 질의 04-A 참조)**: `createDocument`처럼
  /// docId가 이번에 새로 발급된 경우 기존 docDir이 없으므로 `.old` 경로는 만들어지지
  /// 않는다 — 재저장(edit resave) 흐름에서 DB 기록 실패 후 `.old` 복원이 필요한
  /// 경우는 이 구현만으로 완전하지 않다. 산출물 노트에 설계 질의로 남긴다.
  Future<void> commitStaging(String docId);

  Future<void> rollbackStaging(String docId); // 스테이징 삭제

  Future<int> freeSpaceBytes();
  Future<void> clearCache();
}

class AppWorkspace implements Workspace {
  AppWorkspace(this.root);

  /// 앱 전용 저장소 루트. 보통 `getApplicationDocumentsDirectory()` 경로.
  final String root;

  static const _storageChannel = MethodChannel(
    'com.kamanbi.pdf_daeri/storage',
  );

  static Future<AppWorkspace> create() async {
    final dir = await getApplicationDocumentsDirectory();
    return AppWorkspace(dir.path);
  }

  String get _docsRoot => p.join(root, 'docs');
  String get _thumbsRoot => p.join(root, 'thumbs');
  String get _recentRoot => p.join(root, 'recent');
  String get _cacheRoot => p.join(root, 'cache');

  @override
  Future<void> ensureLayout() async {
    for (final dir in [_docsRoot, _thumbsRoot, _recentRoot, _cacheRoot]) {
      await Directory(dir).create(recursive: true);
    }
    // 앱 시작 시 이전 세션의 .tmp/.old 크래시 잔재 정리 (설계 §7.3).
    // Workspace 인터페이스(§2.9)에는 별도 메서드로 확정되어 있지 않아
    // ensureLayout()에 포함시켰다 — 앱 시작 시 정확히 한 번 호출되는 지점이
    // 여기뿐이라 자연스럽다고 판단했다. 인터페이스 변경이 필요하면 통지 바람.
    await _cleanupStaleStaging();
  }

  Future<void> _cleanupStaleStaging() async {
    final docsDir = Directory(_docsRoot);
    if (!await docsDir.exists()) return;
    await for (final entry in docsDir.list()) {
      final name = p.basename(entry.path);
      if (name.endsWith('.tmp') || name.endsWith('.old')) {
        try {
          await entry.delete(recursive: true);
        } catch (_) {
          // 삭제 실패는 앱 기동을 막지 않는다. 다음 시작 때 다시 시도한다.
        }
      }
    }
  }

  @override
  String docDir(String docId) => p.join(_docsRoot, docId);

  @override
  String docPdf(String docId) => p.join(docDir(docId), 'document.pdf');

  @override
  String sourcesDir(String docId) => p.join(docDir(docId), 'sources');

  @override
  String sourcePdf(String docId, int n) =>
      p.join(sourcesDir(docId), 'src_$n.pdf');

  @override
  String sourceImage(String docId, int n) => p.join(
    sourcesDir(docId),
    'pages',
    '${n.toString().padLeft(3, '0')}.jpg',
  );

  @override
  String thumb(String docId) => p.join(_thumbsRoot, '$docId.jpg');

  @override
  String recentFile(String id) => p.join(_recentRoot, '$id.pdf');

  @override
  String cacheFile(String key) => p.join(_cacheRoot, '$key.jpg');

  String _stagingDir(String docId) => p.join(_docsRoot, '$docId.tmp');
  String _oldDir(String docId) => p.join(_docsRoot, '$docId.old');
  String _stagingSourcesDir(String docId) => p.join(_stagingDir(docId), 'sources');

  @override
  String stagingDocPdf(String docId) => p.join(_stagingDir(docId), 'document.pdf');

  @override
  String stagingSourcePdf(String docId, int n) =>
      p.join(_stagingSourcesDir(docId), 'src_$n.pdf');

  @override
  String stagingSourceImage(String docId, int n) => p.join(
    _stagingSourcesDir(docId),
    'pages',
    '${n.toString().padLeft(3, '0')}.jpg',
  );

  @override
  Future<String> beginStaging(String docId) async {
    final staging = Directory(_stagingDir(docId));
    if (await staging.exists()) {
      // 동일 docId로 재시도하는 경우(이론상 새 uuid라 드물다) 잔재를 지우고 새로 시작.
      await staging.delete(recursive: true);
    }
    await staging.create(recursive: true);
    // §3.3 ImagePageRef 경로 화이트리스트가 스테이징 하위 sources/pages/도 허용하므로
    // 저장 조립 전에 미리 만들어 둔다.
    await Directory(
      p.join(staging.path, 'sources', 'pages'),
    ).create(recursive: true);
    return staging.path;
  }

  @override
  Future<void> commitStaging(String docId) async {
    final staging = Directory(_stagingDir(docId));
    final target = Directory(docDir(docId));
    final old = Directory(_oldDir(docId));

    if (!await staging.exists()) {
      throw StateError('commitStaging: 스테이징 디렉터리가 없습니다 (docId=$docId)');
    }

    if (await old.exists()) {
      await old.delete(recursive: true);
    }

    final hadExisting = await target.exists();
    if (hadExisting) {
      await target.rename(old.path);
    }

    try {
      await staging.rename(target.path);
    } catch (e) {
      // rename 실패: 기존 문서가 있었다면 원상 복구 시도.
      if (hadExisting && await old.exists() && !await target.exists()) {
        await old.rename(target.path);
      }
      rethrow;
    }

    if (await old.exists()) {
      await old.delete(recursive: true);
    }
  }

  @override
  Future<void> rollbackStaging(String docId) async {
    final staging = Directory(_stagingDir(docId));
    if (await staging.exists()) {
      await staging.delete(recursive: true);
    }
  }

  @override
  Future<int> freeSpaceBytes() async {
    // dart:io / path_provider에는 크로스플랫폼 여유공간 API가 없어
    // MainActivity.kt의 StatFs 채널을 호출한다(Android 전용, 절대 규칙에 부합).
    try {
      final free = await _storageChannel.invokeMethod<int>(
        'getFreeSpaceBytes',
      );
      return free ?? -1;
    } on PlatformException {
      // 실기기 확인 필요: 채널 실패 시 -1(확인 불가)을 반환한다.
      // 호출자는 -1을 "판단 불가"로 취급하고 저장을 막지 않되, 저장 실패(OutOfSpace)
      // 발생 시 명시적으로 안내해야 한다 — §7.3 "명시적 실패 처리, 무음 실패 금지".
      return -1;
    } on MissingPluginException {
      return -1;
    }
  }

  @override
  Future<void> clearCache() async {
    final dir = Directory(_cacheRoot);
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
    await dir.create(recursive: true);
  }
}
