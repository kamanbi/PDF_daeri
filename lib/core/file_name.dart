/// 파일명·문서 제목 정규화 단일 구현. (CLAUDE.md "중복 금지" §, 설계 §9.1)
///
/// 이 파일 밖에서 파일명/제목을 조립하지 않는다. 아래 지점은 반드시 이 클래스를 거친다.
/// ① 저장 다이얼로그 제목 확정 시  ② 공유·내보내기 파일명 생성 시
/// ③ SAF 임포트 표시명 저장 시    ④ 합치기·나누기·편집 저장의 파생 제목 생성 시
library;

import 'package:unorm_dart/unorm_dart.dart' as unorm;

abstract final class FileName {
  /// 파일명에 쓸 수 없는 문자. 저장 시 `_`로 치환한다.
  static const String forbidden = r'/\:*?"<>|';

  static const int maxLength = 100;

  static final RegExp _forbiddenPattern = RegExp(
    '[${RegExp.escape(forbidden)}]',
  );

  // 제어문자 U+0000–U+001F
  static final RegExp _controlChars = RegExp(r'[\x00-\x1F]');

  // 앞뒤에 남은 마침표·공백 정리(윈도우 예약 규칙 대응 겸 미관 정리)
  static final RegExp _leadTrailDotsAndSpaces = RegExp(r'^[.\s]+|[.\s]+$');

  /// trim → NFC 정규화 → 금지문자 치환 → 제어문자 제거 → 앞뒤 `.`/공백 제거
  /// → 100자 제한(문자 단위, 서로게이트 페어 분리 금지) → 빈 값이면 `문서_yyyyMMdd_HHmm`
  static String normalize(String raw, {DateTime? now}) {
    var s = raw.trim();
    s = unorm.nfc(s);
    s = s.replaceAll(_forbiddenPattern, '_');
    s = s.replaceAll(_controlChars, '');
    s = s.replaceAll(_leadTrailDotsAndSpaces, '');

    if (s.length > maxLength) {
      // 서로게이트 페어를 분리하지 않도록 코드유닛이 아닌 rune(코드포인트) 단위로 자른다.
      s = String.fromCharCodes(s.runes.take(maxLength));
    }

    if (s.isEmpty) {
      s = '문서_${_stamp(now ?? DateTime.now())}';
    }

    return s;
  }

  static String _stamp(DateTime dt) {
    String p2(int v) => v.toString().padLeft(2, '0');
    final y = dt.year.toString().padLeft(4, '0');
    return '$y${p2(dt.month)}${p2(dt.day)}_${p2(dt.hour)}${p2(dt.minute)}';
  }

  /// 합치기 결과 제목: `<첫 문서 제목> 외 N건`. [count]는 합쳐진 문서 총 개수.
  /// N = count - 1 (첫 문서를 제외한 나머지 건수).
  static String mergedTitle(String firstTitle, int count) {
    if (count <= 1) return firstTitle;
    return '$firstTitle 외 ${count - 1}건';
  }

  /// 나누기(발췌) 결과 제목.
  static String splitTitle(String originalTitle) => '$originalTitle (발췌)';

  /// 편집 저장 결과 제목.
  static String editedTitle(String originalTitle) => '$originalTitle (편집본)';

  /// 압축 결과 제목. `pipeline.md` 163행 확정(Q21, 2026-08-19) — `(압축본)`이
  /// 아니라 `(압축)`이다. 외부 PDF L2 압축(`_workspace/31_...md`)도 이 규칙을 그대로 쓴다.
  static String compressedTitle(String originalTitle) => '$originalTitle (압축)';

  /// 전자서명 결과 제목. `_workspace/79_architect_v1.1_v2_design.md` §3.4 확정.
  static String signedTitle(String originalTitle) => '$originalTitle (서명)';

  /// 주석(형광펜·텍스트) 결과 제목. `_workspace/79_architect_v1.1_v2_design.md`
  /// §6·§13 배치 4 항목 12 확정.
  static String annotatedTitle(String originalTitle) => '$originalTitle (주석)';

  /// OCR(텍스트 인식) 결과 제목. `_workspace/79_architect_v1.1_v2_design.md`
  /// §7·§13 배치 5 항목 16 확정.
  static String ocrTitle(String originalTitle) => '$originalTitle (텍스트 인식)';

  /// [existing]에 [title]이 이미 있으면 ` (2)`, ` (3)` ... 을 붙여 유일하게 만든다.
  static String dedupe(String title, Set<String> existing) {
    if (!existing.contains(title)) return title;
    var n = 2;
    while (existing.contains('$title ($n)')) {
      n++;
    }
    return '$title ($n)';
  }

  /// 공유·내보내기 직전 확장자를 부착한다. `.pdf`를 붙이는 지점은 여기뿐이다.
  /// [title]은 이미 [normalize]를 거친 값이어야 하며, 방어적으로 한 번 더
  /// 정규화한 뒤 기존 `.pdf`(대소문자 무관) 접미사가 있으면 중복 부착을 피한다.
  static String toFileName(String title) {
    var normalized = normalize(title);
    final lower = normalized.toLowerCase();
    if (lower.endsWith('.pdf')) {
      normalized = normalized.substring(0, normalized.length - 4);
      if (normalized.isEmpty) {
        normalized = normalize('');
      }
    }
    return '$normalized.pdf';
  }

  /// 제목 검색 질의어 정규화의 단일 구현(§76 §4.1). NFC 정규화 → trim → 소문자 변환
  /// → `LIKE` 와일드카드(`%`, `_`) 이스케이프 순으로 처리한다. `documents.title`은
  /// [normalize](NFC)를 거친 값이므로, 검색어도 같은 NFC를 거쳐야 한글 조합(NFD) 입력이
  /// 매칭된다. 이 함수 밖에서 검색어를 다시 정규화하지 않는다.
  static String normalizeForSearch(String raw) {
    var s = raw.trim();
    s = unorm.nfc(s);
    s = s.toLowerCase();
    // LIKE 패턴에서 `%`/`_`가 와일드카드로 해석되지 않도록 이스케이프한다.
    // 이스케이프 문자 자체(`\`)도 먼저 이스케이프해 이중 해석을 막는다.
    s = s
        .replaceAll(r'\', r'\\')
        .replaceAll('%', r'\%')
        .replaceAll('_', r'\_');
    return s;
  }

  /// 사진 보관함에 저장할 JPEG 파일명. 기존 확장자는 제거해 이중 확장자를 막는다.
  static String toJpegFileName(String title) {
    var normalized = normalize(title);
    final lower = normalized.toLowerCase();
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) {
      final extensionLength = lower.endsWith('.jpeg') ? 5 : 4;
      normalized = normalized.substring(0, normalized.length - extensionLength);
      if (normalized.isEmpty) normalized = normalize('');
    }
    return '$normalized.jpg';
  }
}
