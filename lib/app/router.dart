/// 앱의 **유일한** 화면 전환 지점. (설계 §1.5, 2주차 신설)
///
/// `screens.md`의 5개 화면(S1/S2/S2-b/S4/S5) 외의 라우트를 정의하지 않는다.
/// `features/**` 안에서 `MaterialPageRoute`를 직접 만들지 않는다 — 화면이
/// 늘어나는 것을 이 파일 하나로 감시하기 위함(§6.4 검사 25). S3(`/edit`)는
/// 3주차에 추가한다.
library;

import 'package:flutter/material.dart';

import '../features/home/home_screen.dart';
import '../features/scan/photo_to_pdf_screen.dart';
import '../features/scan/scan_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/viewer/open_pdf_screen.dart';
import '../features/viewer/viewer_screen.dart';

abstract final class AppRoutes {
  static const home = '/'; // S1
  static const scan = '/scan'; // S2
  static const photoToPdf = '/photo'; // S2 (Play 서비스 폴백)
  static const openPdf = '/open'; // S2-b
  static const viewer = '/viewer'; // S4
  static const settings = '/settings'; // S5
  // S3(/edit)는 3주차에 추가한다. 지금 정의하지 않는다.
}

/// S4 뷰어 화면 인자.
class ViewerArgs {
  const ViewerArgs({
    required this.pdfPath,
    required this.title,
    required this.pageCount,
    this.password,
    this.isEncrypted = false,
    this.recentId,
    this.docId,
  });

  /// 앱 작업공간 안의 복사본(또는 소유 문서) 경로. **외부 URI를 여기 넣지 않는다.**
  final String pdfPath;
  final String title;
  final int pageCount;

  /// 암호 PDF를 연 세션의 비밀번호. **메모리에만 존재한다** — DB·파일·로그
  /// 어디에도 쓰지 않는다. 화면이 파괴되면 함께 사라진다(§3.3).
  final String? password;

  /// true면 편집 진입을 차단한다(1주차 Q10 확정 정책 유지, §3.3). 이번
  /// 라운드에는 S3 진입점 자체가 없어 즉시 영향은 없지만, 3주차 구현자가
  /// 반드시 봐야 하는 계약이다.
  final bool isEncrypted;

  /// 최근 파일에서 열었으면 그 id. 뷰어 진입 시 `RecentRepository.touch(recentId)`는
  /// `open_pdf_flow.dart`가 임포트 단계에서 이미 처리한다(중복 호출하지 않는다).
  final String? recentId;

  /// [2026-08-19 신설, §31 M-E8] "내 문서"(`docs/<docId>/`)를 열었을 때만 채워진다.
  /// `recentId`와 상호 배타 — 홈의 "내 문서" 섹션에서 진입하면 이 값이, 최근 연 파일
  /// (또는 외부 인텐트)로 진입하면 `recentId`가 채워진다. 압축 결과 시트(§4.4)의
  /// [원본 삭제]/[앱에서 원본 제거] 라벨 분기가 이 두 필드로 출처를 판별한다.
  final String? docId;
}

Route<Object?>? onGenerateRoute(RouteSettings settings) {
  switch (settings.name) {
    case AppRoutes.home:
      return MaterialPageRoute(builder: (_) => const HomeScreen(), settings: settings);
    case AppRoutes.scan:
      return MaterialPageRoute(builder: (_) => const ScanScreen(), settings: settings);
    case AppRoutes.photoToPdf:
      return MaterialPageRoute(builder: (_) => const PhotoToPdfScreen(), settings: settings);
    case AppRoutes.openPdf:
      return MaterialPageRoute(builder: (_) => const OpenPdfScreen(), settings: settings);
    case AppRoutes.settings:
      return MaterialPageRoute(builder: (_) => const SettingsScreen(), settings: settings);
    case AppRoutes.viewer:
      final args = settings.arguments;
      if (args is! ViewerArgs) {
        // 인자 없이 뷰어 라우트가 요청되는 것은 호출부 결함이다. 크래시 대신
        // 홈으로 안전 착지한다.
        return MaterialPageRoute(builder: (_) => const HomeScreen());
      }
      return MaterialPageRoute(builder: (_) => ViewerScreen(args: args), settings: settings);
    default:
      return null;
  }
}
