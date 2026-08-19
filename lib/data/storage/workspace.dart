/// 앱 작업공간 경로 + 스테이징 저장 트랜잭션 단일 구현. (설계 §2.9, §7)
///
/// 레이아웃(모두 `root` 하위):
///   docs/`docId`/document.pdf         PdfEngine이 스테이징을 거쳐 쓴다
///   docs/`docId`/sources/             임포트·스캔 원본 복사본 (재편집용, 함부로 지우지 않는다)
///   docs/`docId`.tmp/                 저장 스테이징. 커밋 전까지만 존재
///   docs/`docId`.old/                 커밋 중 임시로만 존재
///   thumbs/`docId`.png                문서 대표 썸네일 (삭제해도 재생성 가능)
///                                     [2026-08-18 · 2주차] `.jpg` → `.png`로 변경.
///                                     `PdfRenderer`가 반환하는 것이 PNG 바이트라
///                                     확장자를 맞췄다(§1.4). 시그니처는 불변.
///   recent/`id`.pdf                   SAF/인텐트로 받은 외부 PDF 복사본
///   cache/`key`.jpg                   렌더 캐시. **항상 삭제해도 안전**
///   cache/share/`fileName`.pdf        [2026-08-20 · 3주차 T5] 시스템 공유 스테이징.
///                                     `cache/` 하위이므로 **항상 삭제해도 안전**
///                                     (`shareFile`/`clearShareStaging` 참조).
///                                     내부 경로(`docs/<uuid>/document.pdf`)가 아니라
///                                     한글 제목이 살아있는 파일명으로 공유하기 위한
///                                     사본이 여기 놓인다(`ShareExport`, 설계 §5.2).
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
  String thumb(String docId); // thumbs/<docId>.png
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

  /// [M-E7 신설 · `_workspace/31_architect_external_compress_l2.md` §2.2] L2-ext
  /// 3-패스 왕복(`PdfCompressor.compress`의 `embeddedImageStagingDir`)이 추출 JPEG·
  /// 치환 중간 PDF를 쓰는 임시 폴더. `<docId>.tmp` 트리 **안**에 둔다 — 압축 실패 시
  /// `rollbackStaging`이 이 폴더까지 함께 지우고, 성공 시 `commitStaging` 이전에
  /// 호출자가 직접 지워 최종 `docDir`에 남지 않게 한다(스테이징 폴더도 아니고
  /// `sources/`도 아니므로 별도 하위 경로로 둔다 — `sources/`·`cache/`·`recent/`
  /// 역할과 혼동하지 않는다).
  String stagingCompressImagesDir(String docId); // <docId>.tmp/_compress_staging

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

  /// [2026-08-20 · 3주차 T5] `<root>/cache/share/<fileName>`. `cache/` 아래이므로
  /// 언제 지워져도 기능에 영향이 없다(`clearShareStaging`이 존재하는 이유).
  /// [fileName]은 이미 `FileName.toFileName(title)`을 거친 값이어야 한다 — 이
  /// 메서드는 경로만 조립하고 파일명 정규화는 하지 않는다(단일 소유 원칙,
  /// `FileName`이 유일한 정규화 지점).
  String shareFile(String fileName);

  /// 공유 스테이징(`cache/share/`) 전체 삭제. 앱 시작 시 1회(`ensureLayout`이
  /// 호출하는 `_cleanupStaleStaging`과 같은 취지) + `clearCache()`에 포함된다.
  /// `cache/`가 이미 사라져도(경합) 조용히 성공해야 한다 — "항상 삭제해도 안전"
  /// 원칙을 지키려면 이 메서드 자체도 실패하지 않아야 한다.
  Future<void> clearShareStaging();
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
  String get _shareRoot => p.join(_cacheRoot, 'share');

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
    // [2026-08-20 · 3주차 T5] 공유 스테이징도 앱 시작 시 1회 정리한다
    // (`clearShareStaging` 문서 주석의 "앱 시작 시 1회" 계약).
    await clearShareStaging();
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
  String thumb(String docId) => p.join(_thumbsRoot, '$docId.png');

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
  String stagingCompressImagesDir(String docId) =>
      p.join(_stagingDir(docId), '_compress_staging');

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
    // clearCache()는 cache/ 전체를 지우므로 cache/share/도 함께 사라진다 —
    // 별도로 clearShareStaging()을 다시 부를 필요는 없지만, 하위 디렉터리를
    // 곧바로 다시 만들어 shareFile()이 반환한 경로의 부모가 항상 존재하도록
    // 보장하지는 않는다(그 책임은 ShareExport 구현체가 쓰기 직전에 진다 — 다른
    // 경로 조립 메서드와 동일한 계약).
  }

  @override
  String shareFile(String fileName) => p.join(_shareRoot, fileName);

  @override
  Future<void> clearShareStaging() async {
    final dir = Directory(_shareRoot);
    if (await dir.exists()) {
      try {
        await dir.delete(recursive: true);
      } catch (_) {
        // "항상 삭제해도 안전" 원칙 — 정리 실패로 앱 기동/작업을 막지 않는다.
        // 다음 clearCache()/앱 재시작 때 다시 시도된다.
      }
    }
  }
}
