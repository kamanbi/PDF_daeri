/// 설정 화면 — 1주차 최소 홈(`home_screen.dart`)에 없던 진입점을 M-Q7에서 신설한다.
///
/// 이 파일이 다루는 범위는 **오픈소스 라이선스 고지 하나뿐**이다(R10, §3.2 위험 등록부).
/// 다른 설정 항목(테마·정렬 등)은 스펙에 없으므로 선제적으로 만들지 않는다(pdf-core.md 원칙).
library;

import 'package:flutter/foundation.dart' show LicenseEntryWithLineBreaks, LicenseRegistry;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

/// 앱 부팅 시 1회 호출한다(`main.dart`). `LicenseRegistry.addLicense`에 등록된 항목은
/// Flutter 표준 `showLicensePage`/`LicensePage`(이 화면이 여는 것과 동일 위젯, 그리고
/// Flutter가 기본 제공하는 `AboutDialog`의 "라이선스 보기" 버튼)에 자동으로 나타난다.
///
/// 대상(R10 — qpdf 마이그레이션이 새로 끌어들인 네이티브 의존성 + 기존 폰트):
/// - qpdf 12.4.0 — Apache License 2.0 (`tool/qpdf_build_manifest.md`)
/// - libjpeg-turbo 3.0.4 — IJG License + Modified(3-clause) BSD License(공식 LICENSE.md
///   원문을 그대로 자산에 포함, `tool/qpdf_build_manifest.md`가 버전 확인 근거)
/// - zlib(Android NDK 제공, qpdf에 정적 링크) — zlib License
/// - Noto Sans KR — SIL Open Font License 1.1(이미 `assets/fonts/OFL.txt`로 번들돼 있었으나
///   라이선스 화면에는 아직 반영되지 않았던 것을 이번에 연결한다)
void registerOpenSourceLicenses() {
  LicenseRegistry.addLicense(() async* {
    final apache2 = await rootBundle.loadString('assets/licenses/apache-2.0.txt');
    yield LicenseEntryWithLineBreaks(const ['qpdf'], apache2);

    final libjpegTurbo = await rootBundle.loadString('assets/licenses/libjpeg-turbo-LICENSE.md');
    yield LicenseEntryWithLineBreaks(const ['libjpeg-turbo'], libjpegTurbo);

    final zlib = await rootBundle.loadString('assets/licenses/zlib.txt');
    yield LicenseEntryWithLineBreaks(const ['zlib'], zlib);

    final notoSansKr = await rootBundle.loadString('assets/fonts/OFL.txt');
    yield LicenseEntryWithLineBreaks(const ['Noto Sans KR'], notoSansKr);
  });
}

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('설정')),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('오픈소스 라이선스'),
            subtitle: const Text('qpdf · libjpeg-turbo · zlib · Noto Sans KR'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => showLicensePage(
              context: context,
              applicationName: 'PDF 대리',
              applicationLegalese: '이 앱은 오픈소스 소프트웨어를 사용합니다. 각 항목을 눌러 전문을 확인하세요.',
            ),
          ),
        ],
      ),
    );
  }
}
