# ML Kit Text Recognition — 이 앱은 한국어(text-recognition-korean) + 라틴(플러그인 기본 번들)
# 스크립트만 쓴다(설계 §7.1·§7.6, v1.1/v2 라운드). 중국어·일본어·데바나가리 인식기는
# 의도적으로 번들하지 않았다(용량·범위 확정, APK 크기 절감). google_mlkit_text_recognition
# 플러그인의 Kotlin 브리지가 모든 스크립트의 TextRecognizerOptions를 참조하는 스위치문을
# 갖고 있어서, 실제로 쓰지 않는 스크립트라도 R8이 "참조는 있는데 클래스가 없다"고
# 빌드를 실패시킨다(missing_rules.txt로 확인됨). 우리 Dart 코드가 Korean/Latin 옵션만
# 요청하므로 런타임에 이 분기들은 실행되지 않는다 — 경고만 무시한다.
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**

# 실제로 쓰는 클래스는 -dontwarn만으로 부족하다 — ML Kit은 리플렉션/네이티브 JNI로
# 이 클래스들에 접근하므로, R8이 "안 쓰는 것처럼 보여" 이름을 바꾸거나(minify) 통째로
# 제거하면(shrink) 빌드는 성공해도 런타임에 ClassNotFoundException 등으로 조용히
# 실패한다(OCR 실행 시 "처리하지 못했습니다"로만 뜨고 원인이 안 보이는 증상의 유력 원인).
# 공식 ML Kit ProGuard 가이드대로 완전히 보존한다.
-keep class com.google.mlkit.vision.text.** { *; }
-keep class com.google.mlkit.vision.common.** { *; }
-keep class com.google_mlkit_text_recognition.** { *; }
-dontwarn com.google.mlkit.vision.text.korean.**

# com.google.mlkit.common.**(특히 sdkinternal 패키지)는 MlKitInitProvider가 앱 시작
# 시점(ContentProvider.attachInfo)에 리플렉션 DI 컨테이너로 초기화하는 핵심 클래스다.
# vision.text/vision.common만 keep하고 이걸 빠뜨리면 R8이 제거해버려서 OCR을 쓰지 않는
# 화면에서도 앱이 시작하자마자 크래시한다(2026-09-23 스토어 배포 실측: "Unsatisfied
# dependency ... com.google.mlkit.common.sdkinternal.d" ContentProvider.attachInfo에서 발생).
-keep class com.google.mlkit.common.** { *; }
