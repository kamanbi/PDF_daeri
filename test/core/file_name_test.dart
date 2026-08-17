import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_daeri/core/file_name.dart';
import 'package:unorm_dart/unorm_dart.dart' as unorm;

void main() {
  group('FileName.normalize', () {
    test('고정 테스트 데이터: NFC 정규화 후에도 원문 유지', () {
      const fixed = '2026년 8월 보고서 (최종).pdf';
      // NFD로 분해된 입력이 들어와도 NFC로 정규화되어 동일 문자열이 나와야 한다.
      final nfdInput = unorm.nfd(fixed);
      expect(FileName.normalize(nfdInput), fixed);
      expect(FileName.normalize(fixed), fixed);
    });

    test('trim: 앞뒤 공백 제거', () {
      expect(FileName.normalize('  제목  '), '제목');
    });

    test('금지문자(/ \\ : * ? " < > |)를 _로 치환', () {
      const raw = 'a/b\\c:d*e?f"g<h>i|j';
      expect(FileName.normalize(raw), 'a_b_c_d_e_f_g_h_i_j');
    });

    test('제어문자 제거', () {
      final raw = '제목끝';
      expect(FileName.normalize(raw), '제목끝');
    });

    test('100자 초과 시 100자로 자른다 (서로게이트 페어 보존)', () {
      final raw = 'A' * 150;
      final result = FileName.normalize(raw);
      expect(result.length, FileName.maxLength);
      expect(result, 'A' * 100);
    });

    test('100자 제한: 서로게이트 페어(이모지)를 분리하지 않는다', () {
      // 이모지 1개 = surrogate pair 2 code unit. 99개 'A' + 이모지 1개 = 101 code unit.
      final raw = 'A' * 99 + '😀';
      final result = FileName.normalize(raw);
      // rune 단위로는 100개(99 A + 1 emoji rune)이므로 잘리지 않고 그대로 남는다.
      expect(result.runes.length, 100);
      expect(result, raw);
    });

    test('빈 값이면 문서_yyyyMMdd_HHmm 로 대체', () {
      final now = DateTime(2026, 8, 17, 23, 5);
      expect(FileName.normalize('   ', now: now), '문서_20260817_2305');
    });

    test('공백/마침표만 있는 입력도 빈 값으로 취급', () {
      final now = DateTime(2026, 1, 2, 3, 4);
      expect(FileName.normalize(' . . ', now: now), '문서_20260102_0304');
    });
  });

  group('파생 제목', () {
    test('mergedTitle: 합치기 결과 제목', () {
      expect(FileName.mergedTitle('2026년 8월 보고서 (최종)', 3), '2026년 8월 보고서 (최종) 외 2건');
      expect(FileName.mergedTitle('단독 문서', 1), '단독 문서');
    });

    test('splitTitle: 나누기(발췌) 결과 제목', () {
      expect(FileName.splitTitle('2026년 8월 보고서 (최종)'), '2026년 8월 보고서 (최종) (발췌)');
    });

    test('editedTitle: 편집 저장 결과 제목', () {
      expect(FileName.editedTitle('2026년 8월 보고서 (최종)'), '2026년 8월 보고서 (최종) (편집본)');
    });
  });

  group('FileName.dedupe', () {
    test('중복 없으면 그대로 반환', () {
      expect(FileName.dedupe('제목', {}), '제목');
    });

    test('동일 제목 존재 시 (2) 부여', () {
      expect(FileName.dedupe('제목', {'제목'}), '제목 (2)');
    });

    test('(2)도 존재하면 (3)으로', () {
      expect(FileName.dedupe('제목', {'제목', '제목 (2)'}), '제목 (3)');
    });
  });

  group('FileName.toFileName', () {
    test('제목에 확장자를 부착한다', () {
      expect(FileName.toFileName('2026년 8월 보고서 (최종)'), '2026년 8월 보고서 (최종).pdf');
    });

    test('이미 .pdf로 끝나면 중복 부착하지 않는다', () {
      expect(FileName.toFileName('보고서.pdf'), '보고서.pdf');
      expect(FileName.toFileName('보고서.PDF'), '보고서.pdf');
    });
  });
}
