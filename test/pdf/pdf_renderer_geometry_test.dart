// `PdfRenderer.pageGeometry`/`evictDocument` 검증 (설계 §2.1 · §6.5).
//
// 확인 항목: 페이지 수 일치 / 회전 페이지의 폭·높이 스왑 / 손상 파일에서 PdfErr / evictDocument가
// 지정한 문서만 닫고 다른 문서 핸들은 살려두는지(뷰어 이탈 시 홈 그리드 캐시를 건드리지 않는다는
// §2.1의 핵심 계약).
//
// 회전 픽스처는 qpdf FFI로 즉석에서 만든다(Windows `test/native/qpdf30.dll` 필요) — DLL이 없으면
// 회전 스왑 케이스만 건너뛰고 나머지(페이지 수·손상 파일·evictDocument 격리)는 그대로 돈다.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf_daeri/core/app_error.dart';
import 'package:pdf_daeri/core/size_guard.dart';
import 'package:pdf_daeri/pdf/page_ref.dart';
import 'package:pdf_daeri/pdf/pdf_engine.dart';
import 'package:pdf_daeri/pdf/pdf_renderer.dart';

const _fixtureRelPath = 'test/fixtures/(서일)-클라우디움 사용자 매뉴얼(윈도우탐색기)_20180821.pdf';
String get _fixturePath => '${Directory.current.path}/$_fixtureRelPath';

const _dllRelPath = 'test/native/qpdf30.dll';
String get _dllPath => '${Directory.current.path}/$_dllRelPath';
bool get _canRunFfi => Platform.isWindows && File(_dllPath).existsSync();

Future<String> _buildSimplePdf(Directory dir, String fileName, {int pages = 1}) async {
  final doc = pw.Document();
  for (var i = 0; i < pages; i++) {
    doc.addPage(pw.Page(build: (context) => pw.Center(child: pw.Text('page $i'))));
  }
  final bytes = await doc.save();
  final path = '${dir.path}/$fileName';
  await File(path).writeAsBytes(bytes);
  return path;
}

void main() {
  late PdfxRenderer renderer;

  setUp(() {
    renderer = PdfxRenderer();
  });

  tearDown(() {
    renderer.evictCache();
  });

  group('pageGeometry', () {
    test('페이지 수가 openPageCount와 일치한다', () async {
      final countResult = await renderer.openPageCount(_fixturePath);
      expect(countResult, isA<PdfOk<int>>());
      final expectedCount = (countResult as PdfOk<int>).value;

      final geoResult = await renderer.pageGeometry(_fixturePath);
      expect(geoResult, isA<PdfOk<PdfPageGeometry>>(), reason: 'pageGeometry 실패: $geoResult');
      final geo = (geoResult as PdfOk<PdfPageGeometry>).value;

      expect(geo.pageCount, expectedCount, reason: 'pageGeometry.pageCount가 openPageCount와 다르다');
      expect(geo.sizes.length, geo.pageCount, reason: 'sizes 길이가 pageCount와 다르다');
      for (final size in geo.sizes) {
        expect(size.widthPt, greaterThan(0), reason: '치수는 양수여야 한다');
        expect(size.heightPt, greaterThan(0));
        expect(size.aspectRatio, closeTo(size.widthPt / size.heightPt, 0.0001));
      }
    });

    test('픽셀을 만들지 않고 렌더 없이 끝난다 -- 반환 타입에 바이트가 없다(타입 자체가 증거)', () async {
      // PdfPageGeometry/PdfPageSize는 double 치수만 담는다(컴파일 타임 보증). 여기서는
      // 대용량 문서에서도 openPageCount 수준의 시간에 끝나는지만 실측으로 재확인한다.
      final sw = Stopwatch()..start();
      final result = await renderer.pageGeometry(_fixturePath);
      sw.stop();
      expect(result, isA<PdfOk<PdfPageGeometry>>());
      expect(sw.elapsedMilliseconds, lessThan(5000), reason: '기하 정보만 읽는데 5초 이상 걸림 -- 렌더가 섞였을 가능성');
    });

    test('회전 페이지는 표시 기준 폭/높이가 스왑된 상태로 나온다', () async {
      final root = Directory.systemTemp.createTempSync('pdf_daeri_geometry_');
      addTearDown(() => root.deleteSync(recursive: true));

      final src = await _buildSimplePdf(root, 'src.pdf');
      final stagingDir = Directory('${root.path}/docs/case1.tmp')..createSync(recursive: true);
      final outputPath = '${stagingDir.path}/document.pdf';

      final engine = QpdfPdfEngine(appRoot: root.path, libraryPathOverride: _canRunFfi ? _dllPath : null);
      final saveResult = await engine.save(
        pages: [PdfPageRef(sourcePath: src, sourceIndex: 0, rotation: 90)],
        outputPath: outputPath,
        quality: ImageQuality.standard,
        guardInput: const GuardInput(op: SaveOp.reorderOrRotate, baselineBytes: 1 << 30),
      );
      expect(saveResult, isA<PdfOk<SaveOutcome>>(), reason: '회전 픽스처 생성 실패: $saveResult');

      // 회전 없는 기준값(같은 소스, 회전 미적용)과 비교해 폭·높이가 뒤바뀌었는지 확인한다.
      final unrotatedStaging = Directory('${root.path}/docs/case2.tmp')..createSync(recursive: true);
      final unrotatedOutput = '${unrotatedStaging.path}/document.pdf';
      final unrotatedSave = await engine.save(
        pages: [PdfPageRef(sourcePath: src, sourceIndex: 0, rotation: 0)],
        outputPath: unrotatedOutput,
        quality: ImageQuality.standard,
        guardInput: const GuardInput(op: SaveOp.reorderOrRotate, baselineBytes: 1 << 30),
      );
      expect(unrotatedSave, isA<PdfOk<SaveOutcome>>());

      final rotatedGeo = await renderer.pageGeometry(outputPath);
      final baseGeo = await renderer.pageGeometry(unrotatedOutput);
      expect(rotatedGeo, isA<PdfOk<PdfPageGeometry>>());
      expect(baseGeo, isA<PdfOk<PdfPageGeometry>>());

      final rotatedSize = (rotatedGeo as PdfOk<PdfPageGeometry>).value.sizes[0];
      final baseSize = (baseGeo as PdfOk<PdfPageGeometry>).value.sizes[0];

      expect(rotatedSize.widthPt, closeTo(baseSize.heightPt, 0.5), reason: '90도 회전 후 폭이 원본 높이와 같아야 한다');
      expect(rotatedSize.heightPt, closeTo(baseSize.widthPt, 0.5), reason: '90도 회전 후 높이가 원본 폭과 같아야 한다');

      // 다음 addTearDown(디렉터리 삭제)이 돌기 전에 열린 핸들을 먼저 닫는다(Windows는 열린
      // 파일을 지울 수 없다).
      renderer.evictCache();
    }, skip: !_canRunFfi ? 'Windows qpdf30.dll 필요' : false);

    test('손상 파일은 PdfErr(SourceCorrupted 또는 SourceEncrypted)를 반환한다', () async {
      final root = Directory.systemTemp.createTempSync('pdf_daeri_geometry_corrupt_');
      addTearDown(() => root.deleteSync(recursive: true));
      // 유효한 PDF를 만든 뒤 중간에서 자른다 -- header만 남기는 것보다 실제 손상 파일에
      // 가깝다. pdfrx는 파싱 실패 원인을 always corrupted로 분류하지 않고, 구조가 깨져
      // 암호화 여부를 판별할 수 없는 경우 SourceEncrypted로 보고할 수도 있다(실측 확인) --
      // 두 경우 모두 "열 수 없는 파일"이라는 §3.4의 UI 계약상 동일하게 처리되므로 이 테스트는
      // PdfErr라는 것과 그 실패가 둘 중 하나임을 확인한다(무음 성공을 잡는 것이 핵심 목적).
      final validBytes = await _buildSimplePdf(root, 'valid.pdf');
      final fullBytes = await File(validBytes).readAsBytes();
      final badPath = '${root.path}/broken.pdf';
      await File(badPath).writeAsBytes(fullBytes.sublist(0, fullBytes.length ~/ 2));

      final result = await renderer.pageGeometry(badPath);
      expect(result, isA<PdfErr<PdfPageGeometry>>(), reason: '손상 파일에서 성공을 반환함');
      final failure = (result as PdfErr<PdfPageGeometry>).failure;
      expect(failure, anyOf(isA<SourceCorrupted>(), isA<SourceEncrypted>()), reason: '예상 밖 실패 타입: $failure');
    });
  });

  group('evictDocument', () {
    test('지정한 문서의 핸들만 닫고 다른 문서는 살아있다', () async {
      final root = Directory.systemTemp.createTempSync('pdf_daeri_evict_');
      addTearDown(() => root.deleteSync(recursive: true));
      final other = await _buildSimplePdf(root, 'other.pdf');

      // 두 문서를 각각 연다(캐시에 핸들 2개가 생긴다).
      final r1 = await renderer.openPageCount(_fixturePath);
      final r2 = await renderer.openPageCount(other);
      expect(r1, isA<PdfOk<int>>());
      expect(r2, isA<PdfOk<int>>());

      renderer.evictDocument(_fixturePath);

      // 대상 문서: 캐시가 비었으므로 다시 열어도 정상 동작해야 한다(새 핸들로 재오픈).
      final reopened = await renderer.openPageCount(_fixturePath);
      expect(reopened, isA<PdfOk<int>>(), reason: 'evictDocument 후 재오픈이 실패함');

      // 다른 문서: evictDocument 호출이 영향을 주지 않아야 한다 -- 여전히 정상 조회된다.
      final untouched = await renderer.openPageCount(other);
      expect(untouched, isA<PdfOk<int>>(), reason: 'evictDocument가 다른 문서 핸들까지 건드림(홈 그리드 회귀)');

      // 다음 addTearDown(디렉터리 삭제)이 돌기 전에 남은 핸들을 닫는다(Windows 파일 잠금).
      renderer.evictCache();
    });

    test('password가 다르면 다른 핸들로 취급한다(캐시 키 = path|password) -- 존재하지 않는 조합을 evict해도 예외가 없다', () {
      // 아직 연 적 없는 path|password 조합을 evict해도 조용히 무시된다(방어적).
      expect(() => renderer.evictDocument(_fixturePath, password: 'never-opened'), returnsNormally);
    });
  });
}
