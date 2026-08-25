import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pdf_daeri/core/app_error.dart';
import 'package:pdf_daeri/data/storage/share_export.dart';
import 'package:pdf_daeri/data/storage/workspace.dart';
import 'package:share_plus/share_plus.dart';

void main() {
  late Directory tempRoot;
  late AppWorkspace workspace;

  setUp(() async {
    tempRoot = await Directory.systemTemp.createTemp('pdf_daeri_share_test_');
    workspace = AppWorkspace(tempRoot.path);
    await workspace.ensureLayout();
  });

  tearDown(() async {
    if (await tempRoot.exists()) {
      await tempRoot.delete(recursive: true);
    }
  });

  test('한글 제목 문서를 공유하면 cache/share/에 한글 파일명 사본이 만들어진다', () async {
    final srcPath = p.join(tempRoot.path, 'docs', 'abc-uuid', 'document.pdf');
    await Directory(p.dirname(srcPath)).create(recursive: true);
    await File(srcPath).writeAsBytes([1, 2, 3]);

    ShareParams? captured;
    final export = SharePlusExport(
      workspace,
      share: (params) async {
        captured = params;
        return const ShareResult('ok', ShareResultStatus.success);
      },
    );

    final result = await export.sharePdf(
      pdfPath: srcPath,
      title: '2026년 8월 보고서 (최종)',
    );

    expect(result, isA<PdfOk<void>>());
    expect(captured, isNotNull);
    final sharedFile = captured!.files!.single;
    expect(p.basename(sharedFile.path), '2026년 8월 보고서 (최종).pdf');
    expect(p.dirname(sharedFile.path), p.join(tempRoot.path, 'cache', 'share'));
  });

  test('공유 완료 후 cache/share/ 스테이징이 정리된다', () async {
    final srcPath = p.join(tempRoot.path, 'docs', 'doc2', 'document.pdf');
    await Directory(p.dirname(srcPath)).create(recursive: true);
    await File(srcPath).writeAsBytes([9]);

    final export = SharePlusExport(
      workspace,
      share: (params) async => const ShareResult('ok', ShareResultStatus.success),
    );

    await export.sharePdf(pdfPath: srcPath, title: '문서');

    expect(await Directory(p.join(tempRoot.path, 'cache', 'share')).exists(), isFalse);
  });

  test('공유 시트가 예외를 던져도(취소 포함) cache/share/가 정리된다', () async {
    final srcPath = p.join(tempRoot.path, 'docs', 'doc3', 'document.pdf');
    await Directory(p.dirname(srcPath)).create(recursive: true);
    await File(srcPath).writeAsBytes([9]);

    final export = SharePlusExport(
      workspace,
      share: (params) async => throw Exception('boom'),
    );

    final result = await export.sharePdf(pdfPath: srcPath, title: '문서');

    expect(result, isA<PdfErr<void>>());
    expect(await Directory(p.join(tempRoot.path, 'cache', 'share')).exists(), isFalse);
  });

  test('원본 파일이 없으면 SourceMissing으로 실패한다', () async {
    final export = SharePlusExport(
      workspace,
      share: (params) async => const ShareResult('ok', ShareResultStatus.success),
    );

    final result = await export.sharePdf(
      pdfPath: p.join(tempRoot.path, 'docs', 'nope', 'document.pdf'),
      title: '문서',
    );

    expect(result, isA<PdfErr<void>>());
    final failure = (result as PdfErr<void>).failure;
    expect(failure, isA<SourceMissing>());
  });

  test('제목에 파일명 금지문자가 있어도 FileName.toFileName으로 정규화된다', () async {
    final srcPath = p.join(tempRoot.path, 'docs', 'doc4', 'document.pdf');
    await Directory(p.dirname(srcPath)).create(recursive: true);
    await File(srcPath).writeAsBytes([1]);

    ShareParams? captured;
    final export = SharePlusExport(
      workspace,
      share: (params) async {
        captured = params;
        return const ShareResult('ok', ShareResultStatus.success);
      },
    );

    await export.sharePdf(pdfPath: srcPath, title: '2026/8월*보고서?');

    final sharedFile = captured!.files!.single;
    expect(p.basename(sharedFile.path), '2026_8월_보고서_.pdf');
  });
}
