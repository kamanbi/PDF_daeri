// 3주차 T7 실기기 크래시 원인 조사 -- 계층 이분(bisection) 실험 1.
// `_workspace/45_pdf-core_split_merge_crash.md` §5 5번 항목:
// `SaveOp.split`이 게이트로 막힌 직후 `SaveOp.merge`를 실행하는 순서를,
// Repository/DB(`DriftDocumentRepository`, `path_provider`)를 거치지 않고
// `QpdfPdfEngine`을 실기기에서 직접 호출해 재현 시도한다.
//
// week3_device_verification_test.dart(Repository 경유)와 정확히 같은 픽스처,
// 같은 split 인덱스(0,10,55,90), 같은 baseline(부트스트랩 없이 원본 픽스처 그대로)을 쓴다.
// 판단은 하지 않는다 -- 크래시 여부(프로세스 생존)만 기록한다.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pdf_daeri/core/app_error.dart';
import 'package:pdf_daeri/pdf/pdf_engine.dart';

const _fixturePath = '/data/local/tmp/fixture_korean.pdf';
const _fixturePageCount = 116;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('3주차 T7 계층 이분 -- QpdfPdfEngine 직접 호출 (Repository/DB 미경유)', () {
    late Directory root;
    late QpdfPdfEngine engine;

    setUpAll(() async {
      root = await Directory.systemTemp.createTemp('week3_engine_direct_');
      engine = QpdfPdfEngine(appRoot: root.path);
      expect(File(_fixturePath).existsSync(), true, reason: '픽스처 사본 없음: $_fixturePath');
    });

    tearDownAll(() async {
      if (root.existsSync()) await root.delete(recursive: true);
    });

    test('split(GuardBlocked 유도) 직후 merge -- 엔진 직접 호출, 프로세스 생존 확인', () async {
      final splitOutDir = Directory('${root.path}/docs/split1.tmp')..createSync(recursive: true);
      final splitOutputPath = '${splitOutDir.path}/document.pdf';

      // Repository 경로와 동일 인덱스(0,10,55,90). 게이트가 실제로 막히는지는
      // split() 내부에서 baselineBytes를 info.bytes(원본 실제 바이트)로 재계산하므로
      // 원 설계값 그대로도 4/116 선택 시 한계(baseline*(4/116)*1.2)를 반드시 넘는다
      // (116p 전체 구조 오버헤드를 포함한 4페이지 출력이 원본의 ~4.1%보다 항상 크다).
      final splitResult = await engine.split(
        sourcePdfPath: _fixturePath,
        pageIndices: const [0, 10, 55, 90],
        outputPath: splitOutputPath,
      );
      print('[ENGINE-DIRECT:split] result=$splitResult');
      expect(
        splitResult,
        isA<PdfErr<SaveOutcome>>(),
        reason: 'split이 게이트를 통과함 -- 재현 전제가 깨짐: $splitResult',
      );

      // 곧바로 merge -- 같은 engine 인스턴스, Repository/DB 없이.
      final mergeOutDir = Directory('${root.path}/docs/merge1.tmp')..createSync(recursive: true);
      final mergeOutputPath = '${mergeOutDir.path}/document.pdf';

      final mergeResult = await engine.merge(
        sourcePdfPaths: [_fixturePath, _fixturePath],
        outputPath: mergeOutputPath,
      );
      print('[ENGINE-DIRECT:merge] result=$mergeResult');
      // 여기 도달했다는 것 자체가 이미 크래시가 아니라는 증거(크래시면 이 테스트 프로세스가 죽는다).
      expect(mergeResult, isA<PdfOk<SaveOutcome>>(), reason: 'merge 실패: $mergeResult');
    });
  });
}
