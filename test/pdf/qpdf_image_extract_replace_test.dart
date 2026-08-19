// M-E6(`_workspace/31_architect_external_compress_l2.md` §3.2, §8.3) — M-E2(`runImageExtractJob`)/
// M-E3(`runImageReplaceJob`) 저수준 검증. RO 원칙: 반환값만 보지 않는다 -- 치환 결과는 재오픈해서
// 확인하고, 추출 바이트는 원본 임베디드 바이트와 완전 동일성(바이트 단위, "SHA-256 동일성"과
// 동치 -- crypto 패키지를 새 의존성으로 추가하지 않기 위해 직접 바이트 비교로 검증한다. 해시
// 비교보다 엄격한 증명이다)을 단언한다.
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:pdf_daeri/pdf/qpdf_isolate.dart';

import 'raw_pdf_fixture.dart';

const _dllRelPath = 'test/native/qpdf30.dll';
String get _dllPath => p.join(Directory.current.path, _dllRelPath);
bool get _canRunFfi => Platform.isWindows && File(_dllPath).existsSync();

/// 실제 AC 계수가 있는 합성 "스캔형" JPEG(§32 스파이크와 같은 방식) -- 단색 이미지는 재인코딩
/// 전후 크기 차이가 없어 A-4/A-5 관련 회귀를 못 잡는다.
Uint8List _scanLikeJpeg(int width, int height, {int seed = 1, int quality = 90}) {
  final rand = Random(seed);
  final image = img.Image(width: width, height: height);
  img.fill(image, color: img.ColorRgb8(250, 248, 240));
  for (var y = 0; y < height; y += 8) {
    for (var x = 0; x < width; x += 3) {
      if (rand.nextDouble() < 0.4) {
        final v = 20 + rand.nextInt(60);
        image.setPixelRgb(x, y, v, v, v);
      }
    }
  }
  return Uint8List.fromList(img.encodeJpg(image, quality: quality));
}

void main() {
  group('M-E2 runImageExtractJob — 적격 규칙 6종(§2.3)', () {
    test('텍스트 PDF(이미지 XObject 없음) -- 후보 정확히 0개', () async {
      final tempDir = await Directory.systemTemp.createTemp('extract_text_');
      addTearDown(() => tempDir.delete(recursive: true));
      final bytes = buildTextOnlyPdf();
      final srcPath = p.join(tempDir.path, 'text.pdf');
      await File(srcPath).writeAsBytes(bytes);

      final result = await runImageExtractJob(
        pdfPath: srcPath,
        stagingDir: tempDir.path,
        longEdgeMaxPx: 100,
        libraryPathOverride: _dllPath,
      );
      expect(result['ok'], true, reason: '${result['error']}: ${result['detail']}');
      expect((result['images'] as List), isEmpty);
    }, skip: !_canRunFfi ? 'Windows qpdf30.dll 필요' : false);

    test('DCTDecode + DeviceRGB, 상한 초과 -- 적격(추출됨), 추출 바이트가 원본 임베디드 바이트와 완전 동일', () async {
      final tempDir = await Directory.systemTemp.createTemp('extract_dct_');
      addTearDown(() => tempDir.delete(recursive: true));
      final jpeg = _scanLikeJpeg(2000, 1500, seed: 1);
      final pdfBytes = buildSinglePageImagePdf(
        streamBytes: jpeg,
        width: 2000,
        height: 1500,
        filter: '/DCTDecode',
        colorSpace: '/DeviceRGB',
      );
      final srcPath = p.join(tempDir.path, 'scan.pdf');
      await File(srcPath).writeAsBytes(pdfBytes);

      final result = await runImageExtractJob(
        pdfPath: srcPath,
        stagingDir: tempDir.path,
        longEdgeMaxPx: 100,
        libraryPathOverride: _dllPath,
      );
      expect(result['ok'], true, reason: '${result['error']}: ${result['detail']}');
      final images = (result['images'] as List).cast<Map<String, Object?>>();
      expect(images.length, 1);
      expect(images.first['w'], 2000);
      expect(images.first['h'], 1500);
      expect(images.first['comps'], 3);

      final extractedPath = images.first['path']! as String;
      final extractedBytes = await File(extractedPath).readAsBytes();
      // 완전 바이트 동일성(§8.1 M-E1 미검증 항목의 해소, §8.3 "SHA-256 동일성" 요구를 직접 바이트
      // 비교로 만족 -- 해시 충돌 여지가 없는 더 엄격한 증명이다).
      expect(extractedBytes, equals(jpeg), reason: 'qpdf_dl_none은 필터를 전혀 풀지 않아야 한다(원시 바이트 = 원본 JPEG)');
    }, skip: !_canRunFfi ? 'Windows qpdf30.dll 필요' : false);

    test('긴 변이 상한 이하 -- 규칙6에 의해 스킵(추출 I/O 자체를 하지 않는다)', () async {
      final tempDir = await Directory.systemTemp.createTemp('extract_belowmax_');
      addTearDown(() => tempDir.delete(recursive: true));
      final jpeg = _scanLikeJpeg(500, 400, seed: 2);
      final pdfBytes = buildSinglePageImagePdf(
        streamBytes: jpeg,
        width: 500,
        height: 400,
        filter: '/DCTDecode',
        colorSpace: '/DeviceRGB',
      );
      final srcPath = p.join(tempDir.path, 'small.pdf');
      await File(srcPath).writeAsBytes(pdfBytes);

      final result = await runImageExtractJob(
        pdfPath: srcPath,
        stagingDir: tempDir.path,
        longEdgeMaxPx: 2000, // 500 <= 2000이므로 스킵.
        libraryPathOverride: _dllPath,
      );
      expect(result['ok'], true);
      expect((result['images'] as List), isEmpty);
    }, skip: !_canRunFfi ? 'Windows qpdf30.dll 필요' : false);

    test('JPXDecode(JPEG2000) -- 색공간/필터 화이트리스트에 의해 거부(추출 대상 아님)', () async {
      final tempDir = await Directory.systemTemp.createTemp('extract_jpx_');
      addTearDown(() => tempDir.delete(recursive: true));
      final pdfBytes = buildSinglePageImagePdf(
        streamBytes: [0, 1, 2, 3, 4], // 실제 JP2 코덱 데이터가 아니어도 된다 -- 필터명만으로 거부된다.
        width: 2000,
        height: 1500,
        filter: '/JPXDecode',
        colorSpace: '/DeviceRGB',
      );
      final srcPath = p.join(tempDir.path, 'jpx.pdf');
      await File(srcPath).writeAsBytes(pdfBytes);

      final result = await runImageExtractJob(
        pdfPath: srcPath,
        stagingDir: tempDir.path,
        longEdgeMaxPx: 100,
        libraryPathOverride: _dllPath,
      );
      expect(result['ok'], true, reason: '${result['error']}: ${result['detail']}');
      expect((result['images'] as List), isEmpty, reason: 'JPXDecode는 명시적 제외 목록(§2.3)이다');
    }, skip: !_canRunFfi ? 'Windows qpdf30.dll 필요' : false);

    test('CCITTFaxDecode + BitsPerComponent 1(2치 스캔) -- 화이트리스트에 의해 거부', () async {
      final tempDir = await Directory.systemTemp.createTemp('extract_ccitt_');
      addTearDown(() => tempDir.delete(recursive: true));
      final pdfBytes = buildSinglePageImagePdf(
        streamBytes: [0xFF, 0x00, 0xFF, 0x00],
        width: 2000,
        height: 1500,
        filter: '/CCITTFaxDecode',
        colorSpace: '/DeviceGray',
        bitsPerComponent: 1,
      );
      final srcPath = p.join(tempDir.path, 'ccitt.pdf');
      await File(srcPath).writeAsBytes(pdfBytes);

      final result = await runImageExtractJob(
        pdfPath: srcPath,
        stagingDir: tempDir.path,
        longEdgeMaxPx: 100,
        libraryPathOverride: _dllPath,
      );
      expect(result['ok'], true, reason: '${result['error']}: ${result['detail']}');
      expect((result['images'] as List), isEmpty, reason: 'CCITTFaxDecode(2치 스캔)는 명시적 제외 목록(§2.3)이다 -- /DCTDecode가 아니다');
    }, skip: !_canRunFfi ? 'Windows qpdf30.dll 필요' : false);

    test('/ImageMask true -- 규칙4에 의해 거부(DCTDecode·DeviceRGB라도)', () async {
      final tempDir = await Directory.systemTemp.createTemp('extract_mask_');
      addTearDown(() => tempDir.delete(recursive: true));
      final jpeg = _scanLikeJpeg(2000, 1500, seed: 3);
      final pdfBytes = buildSinglePageImagePdf(
        streamBytes: jpeg,
        width: 2000,
        height: 1500,
        filter: '/DCTDecode',
        colorSpace: null,
        imageMask: true,
      );
      final srcPath = p.join(tempDir.path, 'mask.pdf');
      await File(srcPath).writeAsBytes(pdfBytes);

      final result = await runImageExtractJob(
        pdfPath: srcPath,
        stagingDir: tempDir.path,
        longEdgeMaxPx: 100,
        libraryPathOverride: _dllPath,
      );
      expect(result['ok'], true, reason: '${result['error']}: ${result['detail']}');
      expect((result['images'] as List), isEmpty);
    }, skip: !_canRunFfi ? 'Windows qpdf30.dll 필요' : false);

    test('스캔 PDF(N페이지, 각 페이지 서로 다른 이미지) -- 후보 수가 페이지 수와 정확히 일치', () async {
      final tempDir = await Directory.systemTemp.createTemp('extract_multipage_');
      addTearDown(() => tempDir.delete(recursive: true));
      const pageCount = 5;
      final jpegs = [for (var i = 0; i < pageCount; i++) _scanLikeJpeg(1800, 1400, seed: 10 + i)];
      final pdfBytes = buildMultiPageImagePdf(jpegPagesBytes: jpegs, width: 1800, height: 1400);
      final srcPath = p.join(tempDir.path, 'multi.pdf');
      await File(srcPath).writeAsBytes(pdfBytes);

      final result = await runImageExtractJob(
        pdfPath: srcPath,
        stagingDir: tempDir.path,
        longEdgeMaxPx: 100,
        libraryPathOverride: _dllPath,
      );
      expect(result['ok'], true, reason: '${result['error']}: ${result['detail']}');
      expect((result['images'] as List).length, pageCount, reason: '§8.3 강화: 0개가 아니라 정확한 수치 일치를 확인한다');
    }, skip: !_canRunFfi ? 'Windows qpdf30.dll 필요' : false, timeout: const Timeout(Duration(minutes: 1)));

    test('같은 이미지를 2개 페이지가 공유 -- 방문 집합으로 dedup되어 1회만 처리된다', () async {
      final tempDir = await Directory.systemTemp.createTemp('extract_dedup_');
      addTearDown(() => tempDir.delete(recursive: true));
      final jpeg = _scanLikeJpeg(2000, 1500, seed: 5);
      final pdfBytes = buildTwoPageSharedImagePdf(jpegBytes: jpeg, width: 2000, height: 1500);
      final srcPath = p.join(tempDir.path, 'shared.pdf');
      await File(srcPath).writeAsBytes(pdfBytes);

      final result = await runImageExtractJob(
        pdfPath: srcPath,
        stagingDir: tempDir.path,
        longEdgeMaxPx: 100,
        libraryPathOverride: _dllPath,
      );
      expect(result['ok'], true, reason: '${result['error']}: ${result['detail']}');
      expect((result['images'] as List).length, 1, reason: '2페이지가 같은 오브젝트를 참조하므로 1회만 추출돼야 한다');
    }, skip: !_canRunFfi ? 'Windows qpdf30.dll 필요' : false);

    test('Form XObject 안에 중첩된 이미지 -- 재귀 순회로 발견된다', () async {
      final tempDir = await Directory.systemTemp.createTemp('extract_form_');
      addTearDown(() => tempDir.delete(recursive: true));
      final jpeg = _scanLikeJpeg(2000, 1500, seed: 6);
      final pdfBytes = buildFormNestedImagePdf(jpegBytes: jpeg, width: 2000, height: 1500);
      final srcPath = p.join(tempDir.path, 'form.pdf');
      await File(srcPath).writeAsBytes(pdfBytes);

      final result = await runImageExtractJob(
        pdfPath: srcPath,
        stagingDir: tempDir.path,
        longEdgeMaxPx: 100,
        libraryPathOverride: _dllPath,
      );
      expect(result['ok'], true, reason: '${result['error']}: ${result['detail']}');
      expect((result['images'] as List).length, 1, reason: 'Form XObject의 /Resources/XObject까지 재귀해야 한다');
    }, skip: !_canRunFfi ? 'Windows qpdf30.dll 필요' : false);
  });

  group('M-E3 runImageReplaceJob — 재검증 가드 + 개별 스킵 + 재오픈 확인', () {
    test('정상 치환 -- replaced=1, 재오픈 성공, Width/Height 갱신됨', () async {
      final tempDir = await Directory.systemTemp.createTemp('replace_ok_');
      addTearDown(() => tempDir.delete(recursive: true));
      final original = _scanLikeJpeg(2000, 1500, seed: 7);
      final srcBytes = buildSinglePageImagePdf(
        streamBytes: original,
        width: 2000,
        height: 1500,
        filter: '/DCTDecode',
        colorSpace: '/DeviceRGB',
      );
      final srcPath = p.join(tempDir.path, 'src.pdf');
      await File(srcPath).writeAsBytes(srcBytes);

      final extractResult = await runImageExtractJob(
        pdfPath: srcPath,
        stagingDir: tempDir.path,
        longEdgeMaxPx: 100,
        libraryPathOverride: _dllPath,
      );
      final manifest = (extractResult['images'] as List).cast<Map<String, Object?>>();
      expect(manifest.length, 1);
      final entry = manifest.first;

      final smaller = _scanLikeJpeg(800, 600, seed: 7, quality: 60);
      final outputPath = p.join(tempDir.path, 'out.pdf');
      final replaceResult = await runImageReplaceJob(
        sourcePath: srcPath,
        outputPath: outputPath,
        replacements: [
          ImageReplacement(
            objid: entry['objid']! as int,
            gen: entry['gen']! as int,
            newBytes: smaller,
            newWidth: 800,
            newHeight: 600,
            expectedWidth: entry['w']! as int,
            expectedHeight: entry['h']! as int,
          ),
        ],
        libraryPathOverride: _dllPath,
      );
      expect(replaceResult['ok'], true, reason: '${replaceResult['error']}: ${replaceResult['detail']}');
      expect(replaceResult['replaced'], 1);
      expect(replaceResult['skipped'], 0);
      expect(replaceResult['pageCount'], 1, reason: 'M-E3 완료 판정: 치환 후 재오픈 성공(페이지 수 유지)');

      // RO: 재추출해 새 Width/Height/바이트가 실제로 반영됐는지 재확인(반환값만 신뢰하지 않는다).
      final reExtractDir = await Directory.systemTemp.createTemp('replace_ok_reextract_');
      addTearDown(() => reExtractDir.delete(recursive: true));
      final reExtract = await runImageExtractJob(
        pdfPath: outputPath,
        stagingDir: reExtractDir.path,
        longEdgeMaxPx: 100,
        libraryPathOverride: _dllPath,
      );
      final reManifest = (reExtract['images'] as List).cast<Map<String, Object?>>();
      expect(reManifest.length, 1);
      expect(reManifest.first['w'], 800);
      expect(reManifest.first['h'], 600);
      final reBytes = await File(reManifest.first['path']! as String).readAsBytes();
      expect(reBytes, equals(smaller), reason: '치환된 스트림 바이트가 실제로 새 JPEG과 동일해야 한다');
    }, skip: !_canRunFfi ? 'Windows qpdf30.dll 필요' : false);

    test('재검증 가드 실패(expectedWidth/Height 불일치) -- 이 이미지만 스킵, 나머지는 계속 진행(문서 전체 실패 아님)', () async {
      final tempDir = await Directory.systemTemp.createTemp('replace_guard_');
      addTearDown(() => tempDir.delete(recursive: true));
      final original = _scanLikeJpeg(2000, 1500, seed: 8);
      final srcBytes = buildSinglePageImagePdf(
        streamBytes: original,
        width: 2000,
        height: 1500,
        filter: '/DCTDecode',
        colorSpace: '/DeviceRGB',
      );
      final srcPath = p.join(tempDir.path, 'src.pdf');
      await File(srcPath).writeAsBytes(srcBytes);

      final extractResult = await runImageExtractJob(
        pdfPath: srcPath,
        stagingDir: tempDir.path,
        longEdgeMaxPx: 100,
        libraryPathOverride: _dllPath,
      );
      final entry = (extractResult['images'] as List).cast<Map<String, Object?>>().first;

      final outputPath = p.join(tempDir.path, 'out.pdf');
      final replaceResult = await runImageReplaceJob(
        sourcePath: srcPath,
        outputPath: outputPath,
        replacements: [
          ImageReplacement(
            objid: entry['objid']! as int,
            gen: entry['gen']! as int,
            newBytes: _scanLikeJpeg(800, 600, seed: 8),
            newWidth: 800,
            newHeight: 600,
            expectedWidth: 9999, // 고의로 틀린 기대값(재검증 가드가 잡아야 한다).
            expectedHeight: 9999,
          ),
        ],
        libraryPathOverride: _dllPath,
      );
      expect(replaceResult['ok'], true, reason: '전체 잡은 성공해야 한다(개별 이미지 스킵일 뿐)');
      expect(replaceResult['replaced'], 0);
      expect(replaceResult['skipped'], 1);
      expect(replaceResult['pageCount'], 1, reason: '치환이 0건이어도 문서는 정상적으로 재작성·재오픈된다');

      // RO: 원본 이미지가 그대로 남아있는지(스킵됐으니 원본 바이트 그대로) 재확인.
      final reExtractDir = await Directory.systemTemp.createTemp('replace_guard_reextract_');
      addTearDown(() => reExtractDir.delete(recursive: true));
      final reExtract = await runImageExtractJob(
        pdfPath: outputPath,
        stagingDir: reExtractDir.path,
        longEdgeMaxPx: 100,
        libraryPathOverride: _dllPath,
      );
      final reEntry = (reExtract['images'] as List).cast<Map<String, Object?>>().first;
      final reBytes = await File(reEntry['path']! as String).readAsBytes();
      expect(reBytes, equals(original), reason: '재검증 가드가 스킵시켰으니 원본 바이트가 그대로여야 한다');
    }, skip: !_canRunFfi ? 'Windows qpdf30.dll 필요' : false);

    test('여러 이미지 중 1개만 재검증 실패 -- 그 이미지만 스킵, 나머지는 정상 치환', () async {
      final tempDir = await Directory.systemTemp.createTemp('replace_partial_');
      addTearDown(() => tempDir.delete(recursive: true));
      final jpegs = [_scanLikeJpeg(1800, 1400, seed: 20), _scanLikeJpeg(1800, 1400, seed: 21)];
      final srcBytes = buildMultiPageImagePdf(jpegPagesBytes: jpegs, width: 1800, height: 1400);
      final srcPath = p.join(tempDir.path, 'src.pdf');
      await File(srcPath).writeAsBytes(srcBytes);

      final extractResult = await runImageExtractJob(
        pdfPath: srcPath,
        stagingDir: tempDir.path,
        longEdgeMaxPx: 100,
        libraryPathOverride: _dllPath,
      );
      final manifest = (extractResult['images'] as List).cast<Map<String, Object?>>();
      expect(manifest.length, 2);

      final outputPath = p.join(tempDir.path, 'out.pdf');
      final replacements = [
        ImageReplacement(
          objid: manifest[0]['objid']! as int,
          gen: manifest[0]['gen']! as int,
          newBytes: _scanLikeJpeg(700, 550, seed: 20),
          newWidth: 700,
          newHeight: 550,
          expectedWidth: manifest[0]['w']! as int,
          expectedHeight: manifest[0]['h']! as int,
        ),
        ImageReplacement(
          objid: manifest[1]['objid']! as int,
          gen: manifest[1]['gen']! as int,
          newBytes: _scanLikeJpeg(700, 550, seed: 21),
          newWidth: 700,
          newHeight: 550,
          expectedWidth: 1, // 고의로 틀림 -- 두 번째 이미지만 스킵돼야 한다.
          expectedHeight: 1,
        ),
      ];
      final replaceResult = await runImageReplaceJob(
        sourcePath: srcPath,
        outputPath: outputPath,
        replacements: replacements,
        libraryPathOverride: _dllPath,
      );
      expect(replaceResult['ok'], true, reason: '${replaceResult['error']}: ${replaceResult['detail']}');
      expect(replaceResult['replaced'], 1);
      expect(replaceResult['skipped'], 1);
      expect(replaceResult['pageCount'], 2);
    }, skip: !_canRunFfi ? 'Windows qpdf30.dll 필요' : false);

    test('존재하지 않는 objid/gen -- 스킵(예외 없음, 전체 잡은 계속 진행)', () async {
      final tempDir = await Directory.systemTemp.createTemp('replace_noobj_');
      addTearDown(() => tempDir.delete(recursive: true));
      final original = _scanLikeJpeg(2000, 1500, seed: 9);
      final srcBytes = buildSinglePageImagePdf(
        streamBytes: original,
        width: 2000,
        height: 1500,
        filter: '/DCTDecode',
        colorSpace: '/DeviceRGB',
      );
      final srcPath = p.join(tempDir.path, 'src.pdf');
      await File(srcPath).writeAsBytes(srcBytes);
      final outputPath = p.join(tempDir.path, 'out.pdf');

      final replaceResult = await runImageReplaceJob(
        sourcePath: srcPath,
        outputPath: outputPath,
        replacements: [
          ImageReplacement(
            objid: 9999,
            gen: 0,
            newBytes: _scanLikeJpeg(800, 600, seed: 9),
            newWidth: 800,
            newHeight: 600,
            expectedWidth: 2000,
            expectedHeight: 1500,
          ),
        ],
        libraryPathOverride: _dllPath,
      );
      expect(replaceResult['ok'], true);
      expect(replaceResult['skipped'], 1);
      expect(replaceResult['replaced'], 0);
    }, skip: !_canRunFfi ? 'Windows qpdf30.dll 필요' : false);
  });
}
