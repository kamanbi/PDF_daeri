/// 이미지 화질 프리셋 — 편집 저장(`pdf_engine.dart`)과 압축(`pdf_compressor.dart`) 양쪽이
/// 공유하는 타입이다. 이 타입 하나만을 위해 두 파일이 서로 import하게 되는 것을 막기 위해
/// (§6.4 자동 검사 19 — `pdf_compressor.dart` ↔ `pdf_engine.dart` 상호 import 금지) 별도
/// 파일로 뺐다.
///
/// `pdf_engine.dart`는 하위 호환을 위해 이 타입을 `export`한다 — 기존에
/// `import 'pdf_engine.dart'`로 `ImageQuality`를 쓰던 코드는 한 글자도 바뀌지 않는다
/// (§2.3/§2.6 공개 시그니처 무변경 원칙 유지).
library;

enum ImageQuality { high, standard, min }
