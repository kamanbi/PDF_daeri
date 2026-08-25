// 3주차 T7 실기기 검증. `_workspace/44_build-runner_week3_device.md` 산출용.
//
// 판단은 하지 않는다 — 측정값을 있는 그대로 기록한다. 이 파일은 build-runner가
// 리더 승인 없이 실행 가능한 `flutter test integration_test/... -d <deviceId>`
// 범위 안에 있다(정식 빌드·설치는 별도로 실행하지 않았다).
//
// 픽스처: /data/local/tmp/fixture_korean.pdf (원본은
// test/fixtures/(서일)-... 그대로 보존, adb push 사본만 사용).
import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf_daeri/core/app_error.dart';
import 'package:pdf_daeri/core/cancel_token.dart';
import 'package:pdf_daeri/core/progress.dart';
import 'package:pdf_daeri/core/size_guard.dart';
import 'package:pdf_daeri/data/db/app_database.dart';
import 'package:pdf_daeri/data/repository/document_repository.dart';
import 'package:pdf_daeri/data/storage/share_export.dart';
import 'package:pdf_daeri/data/storage/workspace.dart';
import 'package:pdf_daeri/pdf/image_quality.dart';
import 'package:pdf_daeri/pdf/page_ref.dart';
import 'package:pdf_daeri/pdf/pdf_engine.dart';
import 'package:pdf_daeri/pdf/pdf_renderer.dart';
import 'package:pdfrx/pdfrx.dart' as pdfrx;
import 'package:share_plus/share_plus.dart';

const _fixturePath = '/data/local/tmp/fixture_korean.pdf';
const _fixturePageCount = 116; // qpdf_device_smoke_test.dart에서 확인된 값

// 저장 경로 테스트 전용 게이트 무력화(RO 정확성만 볼 때) — roundtrip 테스트와 동일 원칙.
GuardInput _generousGuard(SaveOp op, {int? total, int? selected}) => GuardInput(
  op: op,
  baselineBytes: 1 << 30,
  totalPages: total,
  selectedPages: selected,
);

/// [count]페이지짜리 텍스트 PDF를 만든다(합성 픽스처, 사용자 원본과 별개).
Future<String> _buildTextPdf(String path, int count, {String prefix = 'PAGE'}) async {
  final doc = pw.Document();
  for (var i = 0; i < count; i++) {
    doc.addPage(pw.Page(build: (context) => pw.Center(child: pw.Text('${prefix}_${i}_END'))));
  }
  final bytes = await doc.save();
  await File(path).writeAsBytes(bytes);
  return path;
}

Future<int> _reopenPageCount(String path) async {
  final doc = await pdfrx.PdfDocument.openFile(path);
  try {
    return doc.pages.length;
  } finally {
    await doc.dispose();
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('3주차 T7 실기기 검증', () {
    late AppWorkspace workspace;
    late AppDatabase db;
    late QpdfPdfEngine engine;
    late DriftDocumentRepository repo;
    late Directory scratch;

    setUpAll(() async {
      workspace = await AppWorkspace.create();
      await workspace.ensureLayout();
      db = AppDatabase.open(workspace.root);
      engine = QpdfPdfEngine(appRoot: workspace.root);
      repo = DriftDocumentRepository(
        db: db,
        workspace: workspace,
        engine: engine,
        renderer: PdfxRenderer(),
      );
      scratch = await Directory.systemTemp.createTemp('week3_device_');
      expect(File(_fixturePath).existsSync(), true, reason: '픽스처 사본 없음: $_fixturePath');
    });

    tearDownAll(() async {
      if (scratch.existsSync()) await scratch.delete(recursive: true);
    });

    // ── 부트스트랩: 픽스처를 앱 소유 문서로 1회 도입(측정 대상 SaveOp 아님, 게이트 무력화) ──
    late DocumentSummary baseDoc;
    late DocumentSummary baseDoc2; // merge용 두 번째 문서

    test('부트스트랩 A: 픽스처 전체를 "내 문서"로 도입 (게이트 무력화, 측정 대상 아님)', () async {
      final pages = [
        for (var i = 0; i < _fixturePageCount; i++)
          PdfPageRef(sourcePath: _fixturePath, sourceIndex: i, rotation: 0),
      ];
      final result = await repo.createDocument(
        title: 'T7-부트스트랩-A',
        origin: DocOrigin.imported,
        pages: pages,
        quality: ImageQuality.standard,
        guardInput: _generousGuard(SaveOp.reorderOrRotate),
      );
      expect(result, isA<PdfOk<DocumentSummary>>(), reason: '부트스트랩 A 실패: $result');
      baseDoc = (result as PdfOk<DocumentSummary>).value;
      print('[BOOTSTRAP-A] docId=${baseDoc.id} pageCount=${baseDoc.pageCount} fileSize=${baseDoc.fileSize}');
      expect(baseDoc.pageCount, _fixturePageCount);
    });

    test('부트스트랩 B: 픽스처 앞 20페이지로 두 번째 문서 생성 (merge용, 측정 대상 아님)', () async {
      final pages = [
        for (var i = 0; i < 20; i++) PdfPageRef(sourcePath: _fixturePath, sourceIndex: i, rotation: 0),
      ];
      final result = await repo.createDocument(
        title: 'T7-부트스트랩-B',
        origin: DocOrigin.imported,
        pages: pages,
        quality: ImageQuality.standard,
        guardInput: _generousGuard(SaveOp.reorderOrRotate),
      );
      expect(result, isA<PdfOk<DocumentSummary>>(), reason: '부트스트랩 B 실패: $result');
      baseDoc2 = (result as PdfOk<DocumentSummary>).value;
      print('[BOOTSTRAP-B] docId=${baseDoc2.id} pageCount=${baseDoc2.pageCount} fileSize=${baseDoc2.fileSize}');
      expect(baseDoc2.pageCount, 20);
    });

    // ── 1. deletePages ──
    test('SaveOp.deletePages 실측 (baseDoc에서 1페이지 삭제)', () async {
      final beforeLoad = await repo.load(baseDoc.id);
      final beforePages = (beforeLoad as PdfOk<DocumentDetail>).value.pages;
      final afterPages = [...beforePages]..removeAt(50);

      final guard = GuardInput(op: SaveOp.deletePages, baselineBytes: baseDoc.fileSize);
      final result = await repo.createDocument(
        title: 'T7-delete',
        origin: DocOrigin.imported,
        pages: afterPages,
        quality: ImageQuality.standard,
        guardInput: guard,
      );
      final limit = SizeGuard.limitFor(guard);
      print('[MEASURE:deletePages] baseline=${baseDoc.fileSize} limit=$limit result=${result is PdfOk<DocumentSummary> ? (result).value.fileSize : result}');
      expect(result, isA<PdfOk<DocumentSummary>>(), reason: 'deletePages 실패: $result');
      final summary = (result as PdfOk<DocumentSummary>).value;
      expect(summary.fileSize <= limit, true, reason: '게이트 미통과: ${summary.fileSize} > $limit');
      expect(summary.pageCount, _fixturePageCount - 1);

      // RO: 재오픈
      final reopened = await repo.load(summary.id);
      expect(reopened, isA<PdfOk<DocumentDetail>>());
      expect((reopened as PdfOk<DocumentDetail>).value.pages.length, _fixturePageCount - 1);
      final physicalCount = await _reopenPageCount(workspace.docPdf(summary.id));
      expect(physicalCount, _fixturePageCount - 1, reason: 'RO: 물리 파일 재오픈 페이지 수 불일치');
    });

    // ── 2. reorderOrRotate ──
    test('SaveOp.reorderOrRotate 실측 (0번·1번 순서 교체 + 0번 90도 회전)', () async {
      final beforeLoad = await repo.load(baseDoc.id);
      final beforePages = List<PageRef>.from((beforeLoad as PdfOk<DocumentDetail>).value.pages);
      final p0 = beforePages[0] as PdfPageRef;
      final p1 = beforePages[1] as PdfPageRef;
      beforePages[0] = PdfPageRef(sourcePath: p1.sourcePath, sourceIndex: p1.sourceIndex, rotation: 0);
      beforePages[1] = PdfPageRef(sourcePath: p0.sourcePath, sourceIndex: p0.sourceIndex, rotation: 90);

      final guard = GuardInput(op: SaveOp.reorderOrRotate, baselineBytes: baseDoc.fileSize);
      final result = await repo.createDocument(
        title: 'T7-reorder-rotate',
        origin: DocOrigin.imported,
        pages: beforePages,
        quality: ImageQuality.standard,
        guardInput: guard,
      );
      final limit = SizeGuard.limitFor(guard);
      print('[MEASURE:reorderOrRotate] baseline=${baseDoc.fileSize} limit=$limit result=${result is PdfOk<DocumentSummary> ? (result).value.fileSize : result}');
      expect(result, isA<PdfOk<DocumentSummary>>(), reason: 'reorderOrRotate 실패: $result');
      final summary = (result as PdfOk<DocumentSummary>).value;
      expect(summary.fileSize <= limit, true, reason: '게이트 미통과: ${summary.fileSize} > $limit');
      expect(summary.pageCount, _fixturePageCount);

      // RO: 재오픈 + 회전값 확인(pdfrx, 쓴 엔진과 다른 라이브러리로 확인)
      final doc = await pdfrx.PdfDocument.openFile(workspace.docPdf(summary.id));
      try {
        expect(doc.pages.length, _fixturePageCount, reason: 'RO-1 페이지 수');
        expect(doc.pages[1].rotation.index * 90, 90, reason: 'RO-4 위치1 회전값(90도 기대)');
      } finally {
        await doc.dispose();
      }
    });

    // ── 3. split ──
    test('SaveOp.split 실측 (비연속 4페이지 발췌)', () async {
      final selectedIdx = <int>[0, 10, 55, 90];
      final pages = [
        for (final i in selectedIdx) PdfPageRef(sourcePath: _fixturePath, sourceIndex: i, rotation: 0),
      ];
      final guard = GuardInput(
        op: SaveOp.split,
        baselineBytes: baseDoc.fileSize,
        totalPages: _fixturePageCount,
        selectedPages: selectedIdx.length,
      );
      final result = await repo.createDocument(
        title: 'T7-split',
        origin: DocOrigin.imported,
        pages: pages,
        quality: ImageQuality.standard,
        guardInput: guard,
      );
      final limit = SizeGuard.limitFor(guard);
      print('[MEASURE:split] baseline=${baseDoc.fileSize} total=$_fixturePageCount selected=${selectedIdx.length} limit=$limit result=${result is PdfOk<DocumentSummary> ? (result).value.fileSize : result}');
      expect(result, isA<PdfOk<DocumentSummary>>(), reason: 'split 실패: $result');
      final summary = (result as PdfOk<DocumentSummary>).value;
      expect(summary.fileSize <= limit, true, reason: '게이트 미통과: ${summary.fileSize} > $limit');
      expect(summary.pageCount, selectedIdx.length);

      final physicalCount = await _reopenPageCount(workspace.docPdf(summary.id));
      expect(physicalCount, selectedIdx.length, reason: 'RO: 물리 파일 재오픈 페이지 수 불일치');
    });

    // ── 4. merge ──
    test('SaveOp.merge 실측 (부트스트랩 A + B 합치기)', () async {
      final loadA = await repo.load(baseDoc.id);
      final loadB = await repo.load(baseDoc2.id);
      final pagesA = (loadA as PdfOk<DocumentDetail>).value.pages;
      final pagesB = (loadB as PdfOk<DocumentDetail>).value.pages;
      final merged = [...pagesA, ...pagesB];

      final baselineSum = baseDoc.fileSize + baseDoc2.fileSize;
      final guard = GuardInput(op: SaveOp.merge, baselineBytes: baselineSum);
      // 진단용(48번 라운드): onProgress 호출 시각을 원문 로그로 남긴다. 테스트 파일 한정 수정.
      final result = await repo.createDocument(
        title: 'T7-merge',
        origin: DocOrigin.imported,
        pages: merged,
        quality: ImageQuality.standard,
        guardInput: guard,
        onProgress: (p) {
          print('[PROGRESS:merge] wallClock=${DateTime.now().toIso8601String()} p=$p');
        },
      );
      final limit = SizeGuard.limitFor(guard);
      print('[MEASURE:merge] baselineSum=$baselineSum limit=$limit result=${result is PdfOk<DocumentSummary> ? (result).value.fileSize : result}');
      expect(result, isA<PdfOk<DocumentSummary>>(), reason: 'merge 실패: $result');
      final summary = (result as PdfOk<DocumentSummary>).value;
      expect(summary.fileSize <= limit, true, reason: '게이트 미통과: ${summary.fileSize} > $limit');
      expect(summary.pageCount, _fixturePageCount + 20);

      final physicalCount = await _reopenPageCount(workspace.docPdf(summary.id));
      expect(physicalCount, _fixturePageCount + 20, reason: 'RO: 물리 파일 재오픈 페이지 수 불일치');
    });

    // ── 5. compose (페이지 추가, 1.15배 규칙) — 최소 1건 ──
    test('SaveOp.compose 실측 (원본 PDF 3페이지 + 이미지 2장 추가)', () async {
      // 최소 합성 텍스트 PDF(3p) + 단색 JPEG 2장으로 compose 시나리오를 만든다.
      final textPdfPath = '${scratch.path}/compose_base.pdf';
      await _buildTextPdf(textPdfPath, 3, prefix: 'COMPOSE');

      // 1x1 JPEG를 코드 없이 만들 수 없으므로 최소 유효 JPEG 바이트를 파일로 기록한다.
      // package:image 미사용(2-키 분리 규칙은 lib/**에만 해당하지만 여기선 굳이 피할 이유가
      // 없어도, 테스트 의존성 최소화를 위해 미리 준비된 방식을 쓰지 않고 pdf 패키지의
      // 부산물이 없으므로 간단한 순수 JPEG 바이트 생성 루틴을 쓴다.)
      final img1Path = '${scratch.path}/img1.jpg';
      final img2Path = '${scratch.path}/img2.jpg';
      await _writeSolidJpeg(img1Path, 400, 300, 200, 50, 50);
      await _writeSolidJpeg(img2Path, 400, 300, 50, 200, 50);
      final addedBytes = File(img1Path).lengthSync() + File(img2Path).lengthSync();

      final basePages = [
        for (var i = 0; i < 3; i++) PdfPageRef(sourcePath: textPdfPath, sourceIndex: i, rotation: 0),
      ];
      final baseSize = File(textPdfPath).lengthSync();

      final composedPages = [
        ...basePages,
        ImagePageRef(imagePath: img1Path, rotation: 0),
        ImagePageRef(imagePath: img2Path, rotation: 0),
      ];

      final guard = GuardInput(op: SaveOp.compose, baselineBytes: baseSize, addedImageBytes: addedBytes);
      final result = await repo.createDocument(
        title: 'T7-compose',
        origin: DocOrigin.imported,
        pages: composedPages,
        quality: ImageQuality.standard,
        guardInput: guard,
      );
      final limit = SizeGuard.limitFor(guard);
      print('[MEASURE:compose] baseline=$baseSize addedImageBytes=$addedBytes limit=$limit result=${result is PdfOk<DocumentSummary> ? (result).value.fileSize : result}');
      expect(result, isA<PdfOk<DocumentSummary>>(), reason: 'compose 실패: $result');
      final summary = (result as PdfOk<DocumentSummary>).value;
      expect(summary.fileSize <= limit, true, reason: '게이트 미통과: ${summary.fileSize} > $limit');
      expect(summary.pageCount, 5);

      final physicalCount = await _reopenPageCount(workspace.docPdf(summary.id));
      expect(physicalCount, 5, reason: 'RO: 물리 파일 재오픈 페이지 수 불일치');
    });

    // ── 취소 지연: 현실적 크기(수십 페이지) ──
    test('저장 취소 반응 시간 실측 (현실적 크기, 픽스처 40페이지 발췌)', () async {
      final pages = [
        for (var i = 0; i < 40; i++) PdfPageRef(sourcePath: _fixturePath, sourceIndex: i, rotation: 0),
      ];
      final cancelToken = CancelToken();
      final guard = _generousGuard(SaveOp.reorderOrRotate);

      final sw = Stopwatch()..start();
      Duration? cancelRequestedAt;
      Duration? actualEndAt;
      final future = repo.createDocument(
        title: 'T7-cancel',
        origin: DocOrigin.imported,
        pages: pages,
        quality: ImageQuality.standard,
        guardInput: guard,
        onProgress: (p) {
          // 잡이 시작되면(첫 진행률 콜백) 바로 취소 요청 — 실사용의 "취소 버튼 탭"에 대응.
          if (cancelRequestedAt == null) {
            cancelRequestedAt = sw.elapsed;
            cancelToken.cancel();
          }
        },
        cancelToken: cancelToken,
      );
      final result = await future;
      actualEndAt = sw.elapsed;
      sw.stop();

      final reactionMs = cancelRequestedAt == null
          ? -1
          : (actualEndAt.inMilliseconds - cancelRequestedAt!.inMilliseconds);
      print('[MEASURE:cancel-latency] totalElapsedMs=${actualEndAt.inMilliseconds} '
          'cancelRequestedAtMs=${cancelRequestedAt?.inMilliseconds} reactionMs=$reactionMs '
          'result=${result.runtimeType}');
      // 취소가 실제로 반영됐는지(성공이 아니라 취소/실패로 끝났는지)만 기록 — 판정은 안 함.
      expect(result is PdfErr, true, reason: '취소 요청 후에도 성공으로 끝남: $result');
    });

    // ── 한글 제목 공유 확인 ──
    test('한글 제목 공유: cache/share/ 사본 파일명 확인 (실제 SharePlus 호출은 대체 콜백)', () async {
      // 실제 SharePlus.instance.share는 시스템 공유 시트를 띄우고 사용자 액션까지
      // Future가 완료되지 않는다(폰 화면 자동화 도구 없음 — 조작 불가). 인텐트 파라미터
      // 조립과 cache/share/ 사본 생성(실기기 파일시스템 경로·한글 인코딩)은 실제로
      // 수행하고, 마지막 SharePlus 호출부만 대체 콜백으로 갈음한다.
      ShareParams? captured;
      final export = SharePlusExport(
        workspace,
        share: (params) async {
          captured = params;
          return ShareResult('', ShareResultStatus.success);
        },
      );

      final title = '(서일) 클라우디움 사용자 매뉴얼 - 공유 테스트';
      final result = await export.sharePdf(pdfPath: workspace.docPdf(baseDoc.id), title: title);
      expect(result, isA<PdfOk<void>>(), reason: '공유 실패: $result');
      expect(captured, isNotNull, reason: 'SharePlus 콜백이 호출되지 않음(인텐트 조립 실패)');

      final sharedFile = captured!.files!.single;
      print('[MEASURE:share] sharedPath=${sharedFile.path} sharedName=${sharedFile.name}');
      expect(sharedFile.path.contains('cache${Platform.pathSeparator}share'), true,
          reason: '공유 사본이 cache/share/ 밖에 있음: ${sharedFile.path}');
      expect(sharedFile.path.endsWith('$title.pdf'), true,
          reason: '공유 파일명에 한글 제목이 살아있지 않음: ${sharedFile.path}');
      // 정리 후에도 사본이 남지 않아야 한다(항상 삭제해도 안전 계약).
      expect(File(sharedFile.path).existsSync(), false, reason: '공유 후 cache/share/ 잔재가 남음');
    });
  });
}

/// 최소 유효 단색 JPEG를 [path]에 쓴다. `package:image`가 이미 dev_dependencies에
/// 있으므로(roundtrip 테스트가 이미 씀) 그대로 재사용한다.
Future<void> _writeSolidJpeg(String path, int w, int h, int r, int g, int b) async {
  final image = img.Image(width: w, height: h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      image.setPixelRgb(x, y, r, g, b);
    }
  }
  final bytes = img.encodeJpg(image, quality: 85);
  await File(path).writeAsBytes(bytes);
}
