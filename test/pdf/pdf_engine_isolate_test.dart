// singleInPlaceSource 분기 조건 회귀 테스트 (아키텍트 판정 9x_architect_verdict.md §2.5).
//
// 판정이 틀리면 두 가지 실패 모드가 있다:
// - 인플레이스로 가면 안 되는 입력(merge/혼합 문서)을 인플레이스로 잘못 보내면, 서로 다른 원본을
//   억지로 한 문서인 척 다뤄 무손실이 깨진다.
// - 인플레이스로 가야 할 입력(단일 원본 삭제/순서/회전/발췌)을 기존 경로로 보내면, §2.2가 규명한
//   압축 해제·리소스 중복 팽창이 그대로 재발한다(이번 라운드의 출발점).
// 이 두 실패 모드를 각각 고정한다.
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_daeri/pdf/page_ref.dart';
import 'package:pdf_daeri/pdf/pdf_engine_isolate.dart';

void main() {
  group('singleInPlaceSource — 인플레이스 경로로 보내야 하는 입력(non-null 기대)', () {
    test('단일 원본에서 페이지 1장 삭제(나머지만 남김)', () {
      final pages = [
        const PdfPageRef(sourcePath: '/a.pdf', sourceIndex: 0, rotation: 0),
        const PdfPageRef(sourcePath: '/a.pdf', sourceIndex: 2, rotation: 0), // idx 1 삭제됨
      ];
      expect(singleInPlaceSource(pages), '/a.pdf');
    });

    test('단일 원본에서 순서만 변경', () {
      final pages = [
        const PdfPageRef(sourcePath: '/a.pdf', sourceIndex: 2, rotation: 0),
        const PdfPageRef(sourcePath: '/a.pdf', sourceIndex: 0, rotation: 0),
        const PdfPageRef(sourcePath: '/a.pdf', sourceIndex: 1, rotation: 0),
      ];
      expect(singleInPlaceSource(pages), '/a.pdf');
    });

    test('단일 원본에서 일부 페이지만 회전', () {
      final pages = [
        const PdfPageRef(sourcePath: '/a.pdf', sourceIndex: 0, rotation: 90),
        const PdfPageRef(sourcePath: '/a.pdf', sourceIndex: 1, rotation: 0),
      ];
      expect(singleInPlaceSource(pages), '/a.pdf');
    });

    test('단일 원본에서 1페이지만 발췌(split)', () {
      final pages = [const PdfPageRef(sourcePath: '/a.pdf', sourceIndex: 49, rotation: 0)];
      expect(singleInPlaceSource(pages), '/a.pdf');
    });

    test('단일 원본에서 페이지를 두 번 참조해도(복제 페이지) 여전히 인플레이스', () {
      final pages = [
        const PdfPageRef(sourcePath: '/a.pdf', sourceIndex: 0, rotation: 0),
        const PdfPageRef(sourcePath: '/a.pdf', sourceIndex: 0, rotation: 0),
      ];
      expect(singleInPlaceSource(pages), '/a.pdf');
    });
  });

  group('singleInPlaceSource — 기존 합성(createNew+import) 경로를 유지해야 하는 입력(null 기대)', () {
    test('빈 목록', () {
      expect(singleInPlaceSource(const []), isNull);
    });

    test('서로 다른 두 원본(merge)', () {
      final pages = [
        const PdfPageRef(sourcePath: '/a.pdf', sourceIndex: 0, rotation: 0),
        const PdfPageRef(sourcePath: '/b.pdf', sourceIndex: 0, rotation: 0),
      ];
      expect(singleInPlaceSource(pages), isNull);
    });

    test('ImagePageRef가 하나라도 섞이면(혼합 문서) null — 원본이 1개뿐이어도', () {
      final pages = [
        const PdfPageRef(sourcePath: '/a.pdf', sourceIndex: 0, rotation: 0),
        const ImagePageRef(imagePath: '/docs/x/sources/pages/000.jpg', rotation: 0),
      ];
      expect(singleInPlaceSource(pages), isNull);
    });

    test('전부 ImagePageRef(신규 이미지 문서)도 null', () {
      final pages = [
        const ImagePageRef(imagePath: '/docs/x/sources/pages/000.jpg', rotation: 0),
        const ImagePageRef(imagePath: '/docs/x/sources/pages/001.jpg', rotation: 0),
      ];
      expect(singleInPlaceSource(pages), isNull);
    });

    test('두 원본이 대소문자만 다른 경로여도(문자열 불일치) 별개 원본으로 취급해 null', () {
      final pages = [
        const PdfPageRef(sourcePath: '/A.pdf', sourceIndex: 0, rotation: 0),
        const PdfPageRef(sourcePath: '/a.pdf', sourceIndex: 0, rotation: 0),
      ];
      expect(singleInPlaceSource(pages), isNull);
    });

    test('세 번째 페이지에서만 원본이 갈리는 경우도 잡는다(뒤쪽 불일치)', () {
      final pages = [
        const PdfPageRef(sourcePath: '/a.pdf', sourceIndex: 0, rotation: 0),
        const PdfPageRef(sourcePath: '/a.pdf', sourceIndex: 1, rotation: 0),
        const PdfPageRef(sourcePath: '/b.pdf', sourceIndex: 0, rotation: 0),
      ];
      expect(singleInPlaceSource(pages), isNull);
    });
  });
}
