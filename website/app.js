const visitorTokenKey = 'pdf-daeri-visitor-token-v2';
const languagePreferenceKey = 'pdf-daeri-language-v1';
const visitorCounter = document.querySelector('#visitor-count');
const originalPageTitle = document.title;
const originalMetaValues = new Map(
  [...document.querySelectorAll('meta[name="description"], meta[property="og:title"], meta[property="og:description"], meta[property="og:image"]')]
    .map((meta) => [meta, meta.content]),
);

const pageCopy = {
  'index.html': {
    title: 'PDF Daeri — Scan, Convert Photos to PDF, and Edit Pages',
    description: 'Scan documents, convert photos to PDF, and organize pages with PDF Daeri for Android.',
  },
  'guide.html': {
    title: 'PDF Daeri User Guide | Photos, Pages, and Compression',
    description: 'Learn to create a PDF from photos, organize pages, and compress files with PDF Daeri.',
  },
  'photo-pdf.html': {
    title: 'Convert Photos to PDF | PDF Daeri',
    description: 'Combine phone photos into one PDF and arrange page order and orientation.',
  },
  'pdf-pages.html': {
    title: 'Delete, Rotate, and Add PDF Pages | PDF Daeri',
    description: 'Organize PDF pages on your phone and insert photos where you need them.',
  },
  'privacy.html': { title: 'Privacy Policy | PDF Daeri', description: 'Privacy policy for the PDF Daeri app and website.' },
  'refund.html': { title: 'Refund Policy | PDF Daeri', description: 'Subscription cancellation and refund information for PDF Daeri.' },
  'contact.html': { title: 'Contact | PDF Daeri', description: 'Contact the PDF Daeri developer for help and feedback.' },
};

const englishCopy = new Map(Object.entries({
  '주요 메뉴': 'Main menu', 'PDF 대리 처음으로': 'PDF Daeri home', 'PDF 대리 앱 아이콘': 'PDF Daeri app icon',
  'PDF 대리': 'PDF Daeri', '기능': 'Features', '텍스트 인식(OCR)': 'Text recognition (OCR)',
  '사진 → PDF': 'Photos to PDF', '페이지 편집': 'Page editing', '전체 기능': 'All features',
  '사용 방법': 'How it works', '문의하기': 'Contact', '설치하기': 'Install',
  '오늘 ': 'Today ', '누적 ': 'All time ', '문서 작업을, ': 'Your document tasks, ',
  '휴대폰 하나로.': 'on one phone.', '스캔하고, 사진을 PDF로 만들고, 필요한 페이지만 남기세요.': 'Scan documents, turn photos into PDFs, and keep only the pages you need.',
  '무료로 설치하기': 'Install for free', '기능 살펴보기': 'Explore features', '스캔한 문서, ': 'Scanned documents, ',
  '이제 검색됩니다.': 'now searchable.', '스캔·사진 문서와 이미지형 PDF에 OCR을 적용하면 글자를 선택·복사·검색할 수 있습니다. OCR 생성은 연간 구독 혜택이며, 이미 글자가 있는 PDF의 선택·검색은 무료입니다.': 'Run OCR on scans, photos, and image-based PDFs to select, copy, and search text. Creating OCR PDFs is included with the annual subscription. Selecting and searching existing PDF text is free.',
  '서명하고, 표시하고, ': 'Sign, mark up, ', '바로 공유.': 'and share.', '저장해둔 서명을 문서 위에 얹고, 형광펜과 메모로 중요한 부분을 표시하세요.': 'Add a saved signature to a document, then mark important sections with highlights and notes.',
  '용량은 줄이고, ': 'Reduce file size, ', '화질은 지키고.': 'keep it clear.', '원하는 용량을 정하면 그 기준에 맞춰 자동으로 압축합니다.': 'Choose a size preset and compress your PDF to match.',
  '그 밖에도 필요한 건 다 있습니다.': 'More tools for everyday documents.', '문서 스캔': 'Document scanning', '문서 가장자리를 맞추고 선명한 PDF로 저장합니다.': 'Adjust document edges and save a clear PDF.',
  'PDF 열기': 'Open PDF', '받은 PDF와 저장한 문서를 한곳에서 확인합니다.': 'View received PDFs and saved documents in one place.',
  '다크 모드': 'Dark mode', '화면 밝기에 맞춰 자동으로, 또는 직접 전환합니다.': 'Switch automatically with your device or set it yourself.',
  '문서함 검색': 'Find documents', '저장해둔 문서를 제목으로 빠르게 찾습니다.': 'Quickly find saved documents by title.',
  '페이지를 추가하고, 회전하고, 순서를 바꿉니다.': 'Add, rotate, and reorder pages.', '여러 장의 사진을 한 개의 정돈된 문서로 만듭니다.': 'Combine multiple photos into one organized document.',
  '모서리 확대 보정': 'Precise corner adjustment', '스캔 모서리를 확대해서 더 정교하게 조정합니다.': 'Zoom in to adjust scan corners more precisely.',
  '작업 자동 복구': 'Recover your work', '편집 중 앱이 꺼져도 마지막 상태 그대로 이어갑니다.': 'Continue from your last state if the app closes while you edit.',
  '까만비': 'Kamanbi', '까만비 스튜디오 홈페이지': 'Kamanbi Studio website', '까만비 스튜디오 아이콘': 'Kamanbi Studio icon', '기획부터 개발까지, ': 'From planning to development, ', '한 사람이 만듭니다.': 'made by one person.',
  'PDF 대리는 큰 회사가 아니라 까만비 스튜디오 한 사람이 기획하고 만드는 앱입니다. 제출용 서류를 스캔하고, 필요한 페이지만 골라 보내야 하는 일상의 번거로움에서 시작했습니다.': 'PDF Daeri is planned and built by one person at Kamanbi Studio. It began with the everyday hassle of scanning documents and selecting the right pages to send.',
  '문의를 남기면 직접 확인하고 답합니다. 기능 요청이나 오류 제보도 실제로 다음 업데이트에 반영됩니다.': 'Your message goes directly to the developer. Feature requests and bug reports help shape future updates.',
  'PDF 작업, 이제 ': 'PDF work, ', 'PDF 대리 하나로 끝내세요.': 'made simple with PDF Daeri.',
  'Google Play에서 설치': 'Get it on Google Play', 'QR 코드를 스캔하면 휴대폰에서 바로 설치할 수 있습니다.': 'Scan the QR code to install it on your phone.',
  'PDF 보기·스캔·편집은 무료로 사용할 수 있습니다.': 'PDF viewing, scanning, and editing are free.',
  '연간 구독으로 광고를 없애고 OCR PDF를 만들 수 있습니다.': 'The annual subscription removes ads and lets you create OCR PDFs.',
  '연간 자동 갱신 구독으로 광고를 없애고 OCR PDF를 만들 수 있습니다.': 'The annual auto-renewing subscription removes ads and lets you create OCR PDFs.',
  '결제 금액은 앱의 Google Play 구매 화면에서 확인해 주세요.': 'See the price on the Google Play purchase screen in the app.',
  'Google Play에서 언제든 관리하거나 취소할 수 있습니다.': 'Manage or cancel your subscription anytime on Google Play.',
  '저장': 'Save', '압축': 'Compress', '공유': 'Share', '페이지 추가': 'Add pages',
  'Google Play에서 해지할 수 있으며 결제한 기간까지 이용할 수 있습니다.': 'Cancel on Google Play. Benefits continue through the paid period.',
  '개인정보처리방침': 'Privacy policy', '환불 규정': 'Refund policy', '까만비 스튜디오 (kamanbi studio) · 대표 김광우 · 사업자등록번호 525-36-01749': 'Kamanbi Studio · Owner: Kwangwoo Kim · Business registration no. 525-36-01749',
  '까만비 스튜디오 · 대표 김광우 · 사업자등록번호 525-36-01749': 'Kamanbi Studio · Owner: Kwangwoo Kim · Business registration no. 525-36-01749',
  '인천광역시 부평구 충선로209번길 41, 8층 801-03호(삼산동, 주영어린타운) · 전화 ': 'Suite 801-03, 8F, 41 Chungseon-ro 209beon-gil, Bupyeong-gu, Incheon, South Korea · Phone ',
  ' · 이메일 ': ' · Email ', '까만비 스튜디오 · 앱 기획 · UI/UX 설계 · 개발 · 소개 홈페이지 제작': 'Kamanbi Studio · App planning · UI/UX design · Development · Website creation',
  'PDF 대리 문서 작업 소개': 'PDF Daeri document tools', 'PDF 대리 앱의 스캔, PDF 열기, 사진 PDF, PDF 수정 기능 소개': 'PDF Daeri features: scan, open PDFs, convert photos, and edit pages',
  'PDF 대리 텍스트 인식 기능이 적용되는 문서 화면': 'PDF Daeri text recognition screen', 'PDF 대리 서명과 형광펜 기능이 적용된 문서 화면': 'PDF Daeri signature and highlighting screen',
  'PDF 대리 압축 기능이 적용된 문서 화면': 'PDF Daeri compression screen', '사진 여러 장을 PDF 하나로 만들기 앱 화면': 'PDF Daeri photos-to-PDF screen',
  '사진 PDF 만들기 화면': 'Create a photo PDF', 'PDF 페이지 삭제·회전·추가하기 앱 화면': 'PDF Daeri page editing screen', 'PDF 페이지 정리 화면': 'Organize PDF pages',
  'PDF 용량 줄이고 공유하기 앱 화면': 'Compress and share a PDF', 'PDF 대리 Google Play 설치 QR 코드': 'QR code to install PDF Daeri from Google Play',
  'Google Play 설치 QR 코드': 'Google Play installation QR code', '휴대폰으로 바로 설치': 'Install on your phone', 'PDF 대리 설치 QR 코드': 'PDF Daeri installation QR code',
  'PDF 대리 · 사진 여러 장을 PDF 하나로 만들기': 'PDF Daeri · Photos to PDF', 'PDF 대리 · PDF 페이지 삭제·회전·추가하기': 'PDF Daeri · Organize PDF pages',
  'PDF 대리 · 사진 → PDF': 'PDF Daeri · Photos to PDF', 'PDF 대리 · 페이지 삭제·회전·추가': 'PDF Daeri · Delete, rotate, and add pages',
  'PDF 대리 · 사진 PDF': 'PDF Daeri · Photos to PDF', 'PDF 대리 · 페이지 편집': 'PDF Daeri · Page editing',
  '사진에서 PDF까지.': 'From photos to PDF.', '순서대로, 간단하게.': 'Step by step, made simple.',
  '사진을 한 파일로 만들고, 필요한 페이지만 정리하세요.': 'Combine photos into one file and keep the pages you need.', 'PDF 대리의 사용 방법을 안내합니다.': 'Learn how to use PDF Daeri.',
  '사용 방법 보기': 'View the guide', '홈페이지': 'Home', '사용 안내 목차': 'Guide contents', '지금 필요한 작업을 선택하세요.': 'Choose what you want to do.',
  '여러 장의 사진을 한 파일로.': 'Combine multiple photos into one file.', '페이지 정리': 'Organize pages', '추가하고, 회전하고, 순서대로.': 'Add, rotate, and reorder.',
  '압축과 공유': 'Compress and share', '용량을 확인하고 필요한 곳으로.': 'Check the file size and send it where you need.', '무료 이용·구독 안내': 'Free features and subscription',
  '기본 기능은 무료, OCR 생성과 광고 제거는 구독 혜택.': 'Core features are free. OCR PDF creation and ad removal are subscription benefits.',
  '사진 여러 장을 PDF 하나로 만들기': 'Create one PDF from multiple photos', '안내문이나 제출할 서류를 이미 사진으로 찍었다면 다시 스캔할 필요가 없습니다.': 'If you already took photos of a notice or document, there is no need to scan it again.',
  '홈에서 ': 'On the home screen, tap ', '를 누르고 필요한 사진을 선택합니다.': ' and choose the photos you need.', '편집 화면에서 사진 순서를 확인하고, 방향이 틀린 사진은 회전합니다. 불필요한 부분은 자릅니다.': 'Check the photo order in the editor, rotate images if needed, and crop unwanted areas.',
  '을 누르고 제목과 화질을 확인합니다.': ', then check the title and quality.', '완성된 PDF를 열어 누락된 페이지가 없는지 확인한 뒤 공유합니다.': 'Open the finished PDF to check for missing pages, then share it.',
  '작은 글씨가 있는 서류는 고화질을 선택하고 결과를 확대해 읽어보세요. 흐린 원본 사진은 화질 옵션만으로 선명해지지 않습니다.': 'For documents with small print, choose high quality and zoom in to check the result. A quality setting cannot sharpen a blurry original photo.',
  'PDF 페이지 삭제·회전·추가하기': 'Delete, rotate, and add PDF pages', '받은 PDF에서 필요 없는 페이지를 지우거나, 빠진 서류 사진을 페이지 사이에 넣을 수 있습니다.': 'Delete pages you do not need from a PDF, or insert a missing document photo between pages.',
  '에서 문서를 열고 편집 화면으로 이동합니다.': ' to open a document and enter the editor.', '페이지를 선택해 회전하거나 삭제합니다. 필요한 페이지만 별도 문서로 저장할 수도 있습니다.': 'Select pages to rotate or delete. You can also save selected pages as a separate document.',
  '에서 사진 또는 스캔을 선택하고, 선택 페이지의 앞·뒤 또는 마지막에 삽입합니다.': ', choose a photo or scan, and insert it before or after the selected page, or at the end.',
  'PDF 대리의 편집은 페이지 정리 기능입니다. 기존 PDF 본문 글자를 워드처럼 직접 수정하는 기능은 제공하지 않습니다.': 'PDF Daeri edits page order and content. It does not directly edit existing PDF text like a word processor.',
  'PDF 용량 줄이고 공유하기': 'Compress and share a PDF', '메일이나 메신저에 첨부하기 전에 압축 기능으로 용량을 줄일 수 있습니다. 문서에 따라 압축 효과는 다릅니다.': 'Reduce a PDF file size before attaching it to email or a messenger. Results vary by document.',
  '문서의 작업 메뉴에서 ': 'In the document actions, choose ', '을 선택합니다.': '.', '작은 글씨는 고화질, 일반 문서는 기본, 용량을 우선하면 최소 옵션의 설명을 확인합니다.': 'Choose High quality for small print, Standard for typical documents, or review the Small option when file size matters most.',
  '압축한 결과의 크기와 글자 선명도를 확인합니다.': 'Check the compressed file size and text clarity.', '를 눌러 휴대폰에 설치된 메신저·메일 등으로 전달합니다.': ' to send the file through a messenger or email app on your phone.',
  '이미 최적화된 PDF는 크게 줄지 않을 수 있습니다. 특정 감소율이나 첨부 용량을 보장하지 않습니다. 공유 대상은 휴대폰에 설치된 앱에 따라 달라집니다.': 'Already optimized PDFs may not shrink much. A specific reduction or final size is not guaranteed. Available sharing destinations depend on the apps installed on your phone.',
  '필요한 기능을 부담 없이.': 'The tools you need, without the fuss.', '기본 기능은 무료. OCR은 구독 혜택.': 'Core features are free. OCR is a subscription benefit.',
  'PDF 보기·텍스트 선택, 스캔, 사진 PDF, 페이지 편집, 합치기·나누기·압축·공유는 구독 없이 사용할 수 있습니다. 이미지형 PDF에 새로 글자를 인식시켜 선택·검색 가능한 PDF로 만드는 OCR과 광고 제거는 연간 구독에 포함됩니다. 문서 변환·편집은 기기에서 처리하며 광고·구독 확인에는 네트워크가 사용됩니다. ': 'View PDFs and select text, scan, create photo PDFs, edit pages, merge, split, compress, and share without a subscription. The annual subscription includes OCR that makes image-based PDFs searchable and selectable, plus ad removal. Document conversion and editing happen on your device. Network access is used for ads and subscription checks. ',
  '개인정보처리방침 보기': 'Read the privacy policy', '문서 작업, 이제 ': 'Document work, ', '직접 시작해 보세요.': 'get started today.',
  'PDF 페이지를 정리하는 PDF 대리 앱 화면': 'PDF Daeri page organizer', '사진을 PDF로 만드는 PDF 대리 앱 화면': 'PDF Daeri photos-to-PDF screen',
  '사진 여러 장을 PDF로 만들기': 'Turn multiple photos into a PDF', '휴대폰 사진 여러 장을 하나의 PDF로 만들고 페이지 순서와 방향을 정리하는 방법. Android PDF 대리 사용 안내입니다.': 'Learn how to combine phone photos into one PDF and arrange page order and orientation with PDF Daeri for Android.',
  '서류 사진을 하나의 PDF로 만들고 바로 공유하세요.': 'Combine document photos into one PDF and share it.', '사진 여러 장을 ': 'Combine multiple photos into ', 'PDF 하나로.': 'one PDF.',
  '촬영해 둔 서류 사진을 한 파일로 만들고, 순서와 방향까지 정리하세요.': 'Combine document photos into one file, then arrange their order and orientation.',
  '만드는 방법': 'How to create one', '사진에서 PDF까지, 네 단계면 됩니다.': 'Four steps from photos to PDF.',
  '페이지 순서와 방향을 확인하고 필요한 사진만 남깁니다.': 'Check page order and orientation, and keep only the photos you need.',
  '제목과 화질을 선택해 새 PDF로 저장합니다.': 'Choose a title and quality, then save a new PDF.', '완성된 파일을 열어 확인한 뒤 필요한 앱으로 공유합니다.': 'Open the finished file to check it, then share it with an app of your choice.',
  '작은 글씨가 있는 서류는 고화질로 저장한 뒤 결과 파일을 확대해 확인하세요.': 'For documents with small print, save in high quality and zoom in to check the result.',
  '전체 사용 가이드 보기': 'View the full user guide', '사진을 정리했다면, ': 'Photos organized? ', 'PDF로 바로 저장하세요.': 'Save them as a PDF.',
  'PDF 페이지를 삭제하고 회전하며 사진 또는 PDF 페이지를 원하는 위치에 추가하는 방법을 안내합니다.': 'Learn how to delete and rotate PDF pages and insert photos or PDF pages where you need them.',
  '받은 PDF의 필요 없는 장을 지우고, 페이지 순서와 방향을 정리하세요.': 'Remove pages you do not need and arrange the order and orientation of a PDF.',
  '필요 없는 페이지는 지우고, ': 'Remove pages you do not need, ', '문서는 순서대로.': 'and keep documents in order.',
  '돌아간 페이지를 바로잡고, 빠진 서류는 필요한 위치에 추가할 수 있습니다.': 'Fix rotated pages and add missing documents where they belong.', '정리 방법': 'How to organize pages',
  '받은 PDF도 휴대폰에서 정리합니다.': 'Organize received PDFs on your phone.', '제출 전 PDF, ': 'Before you submit a PDF, ', '필요한 페이지만 남기세요.': 'keep only the pages you need.',
  '문의하기 | PDF 대리': 'Contact | PDF Daeri', '문의하기': 'Contact',
  '앱 사용 중 불편한 점, 오류, 광고 제거 구매 관련 문의를 남겨 주세요. 확인 후 답변드리겠습니다.': 'Contact us about app issues, bugs, or ad-removal purchases. We will review your message and reply.',
  '이메일: ': 'Email: ', '개발자 웹사이트': 'Developer website', '이름': 'Name', '답변 받을 이메일': 'Email for reply', '문의 내용': 'Message',
  '문의 양식은 Netlify Forms를 통해 처리·보관될 수 있습니다. 이름·이메일·문의 내용은 답변 목적으로만 처리합니다. 자세한 내용은 ': 'The contact form may be processed and stored through Netlify Forms. Your name, email, and message are used only to respond. See the ',
  '개인정보처리방침': 'privacy policy',
  '을 확인해 주세요. 결제 수단 번호나 비밀번호는 입력하지 마세요.': '. Do not include payment card numbers or passwords.',
  '문의 보내기': 'Send message', '← PDF 대리 홈페이지': '← PDF Daeri home', '개인정보처리방침 | PDF 대리': 'Privacy policy | PDF Daeri',
  '시행일: 2026년 8월 28일 (2026년 9월 30일 개정)': 'Effective: August 28, 2026 (revised September 30, 2026)',
  '1. 처리하는 정보': '1. Information we process',
  'PDF 대리 앱은 계정 가입을 요구하지 않으며, 문서와 사진은 사용자의 기기에서 처리합니다. 앱 개발자는 사용자가 선택한 PDF·사진의 내용을 별도 서버로 전송하거나 보관하지 않습니다.': 'The PDF Daeri app does not require an account. Documents and photos are processed on your device. The developer does not send or store the contents of your selected PDFs or photos on a separate server.',
  '이 홈페이지는 오늘 방문자와 누적 방문자를 집계하기 위해 브라우저의 로컬 저장소에 무작위 방문자 식별자를 저장합니다. 서버에는 이 식별자를 해시한 값, 한국 시간 기준 방문 날짜, 집계 숫자만 보관합니다. 이름·이메일·IP 주소는 방문 수 계산 목적으로 저장하지 않습니다. 브라우저 데이터를 삭제하거나 기기를 바꾸면 새 방문자로 집계될 수 있습니다.': 'This website stores a random visitor identifier in your browser storage to count daily and all-time visits. The server stores only a hash of that identifier, the visit date in Korea Standard Time, and aggregate counts. Names, email addresses, and IP addresses are not stored for visit counting. Clearing browser data or changing devices may count you as a new visitor.',
  '2. 광고와 결제': '2. Ads and payments',
  '앱의 무료 버전에는 Google Mobile Ads 광고가 표시될 수 있습니다. 광고 제공사는 광고 식별자 등 필요한 정보를 자체 정책에 따라 처리할 수 있습니다. 광고 제거와 OCR PDF 생성은 연간 자동 갱신 구독 혜택이며 Google Play 결제 시스템을 통해 처리됩니다. 실제 금액은 앱의 Google Play 구매 화면에서 확인할 수 있습니다. 결제 수단 정보는 개발자에게 전달되지 않습니다. 구독 상태 확인을 위해 앱은 Google Play가 발급한 구매 토큰(결제 수단·개인 식별 정보 없음)을 개발자가 운영하는 서버(Netlify Functions)로 전송해 Google Play 서버에 실제 구독 상태를 조회합니다. 이 토큰은 구독 상태 확인 목적으로만 사용하고 보관하지 않습니다. 남용 방지를 위해 서버는 IP 기준으로 짧은 시간 동안의 요청 횟수를 제한합니다.': 'The free version of the app may display Google Mobile Ads. The ad provider may process information such as the advertising ID under its own policies. Ad removal and OCR PDF creation are benefits of the annual auto-renewing subscription, processed through Google Play Billing. Check the current price on the Google Play purchase screen in the app. Payment method details are not shared with the developer. To verify subscription status, the app sends a Google Play purchase token (which contains no payment method or personal identity details) to the developer-operated server (Netlify Functions), which checks the status with Google Play. The token is used only for this check and is not retained. The server limits request rates by IP address to prevent abuse.',
  '3. 문의하기': '3. Contact inquiries',
  '문의 양식으로 이름, 이메일 주소, 문의 내용을 보내면 답변을 위해 해당 정보를 처리합니다. 문의 양식은 Netlify Forms 서비스를 이용하며, 제출 내용은 Netlify 서비스 환경과 사이트 관리 화면에서 처리·확인될 수 있습니다. Netlify의 서비스 및 데이터 처리 관련 안내는 ': 'If you submit your name, email address, and message through the contact form, we process it to respond. The form uses Netlify Forms, and submissions may be processed and viewed in Netlify’s service environment and site dashboard. For information about Netlify’s services and data processing, see ',
  'Netlify 개인정보·데이터 처리 정보': 'Netlify privacy and data processing information',
  '를 확인해 주세요. 문의 해결 후 보관이 필요하지 않은 제출 내용은 Netlify 사이트 관리 화면에서 삭제합니다.': '. After resolving an inquiry, we delete submissions that are no longer needed from the Netlify site dashboard.',
  '4. 제3자 제공과 보안': '4. Sharing and security',
  '법령상 요구되는 경우를 제외하고 문의 정보를 판매하거나 광고 목적으로 제공하지 않습니다. 문서 원본은 앱 외부 서버로 전송하지 않습니다.': 'We do not sell inquiry information or share it for advertising, except when required by law. Original documents are not sent to servers outside the app.',
  '5. 이용자 권리와 문의': '5. Your rights and contact',
  '개인정보 관련 열람·정정·삭제 요청은 ': 'To request access to, correction of, or deletion of personal information, use ', '를 이용해 접수할 수 있습니다.': '.',
  '환불 규정 | PDF 대리': 'Refund policy | PDF Daeri', '환불 규정': 'Refund policy', '시행일: 2026년 8월 28일': 'Effective: August 28, 2026',
  '1. 적용 대상': '1. What this policy covers',
  'PDF 대리의 유료 항목은 광고 제거와 OCR PDF 생성을 제공하는 연간 자동 갱신 구독입니다. 실제 결제 금액은 앱의 Google Play 구매 화면에서 확인할 수 있습니다. 구독 결제와 환불은 Google Play 결제 시스템을 통해 처리됩니다.': 'PDF Daeri offers an annual auto-renewing subscription that includes ad removal and OCR PDF creation. Check the current price on the Google Play purchase screen in the app. Subscription payments and refunds are handled through Google Play Billing.',
  '2. 환불 요청': '2. Requesting a refund',
  '환불 가능 여부와 절차는 구매 시점의 Google Play 환불 정책 및 관련 법령을 따릅니다. Google Play 주문 내역에서 환불을 요청하거나 Google Play 고객센터의 안내를 이용할 수 있습니다.': 'Refund eligibility and procedures follow the Google Play refund policy in effect at the time of purchase and applicable law. Request a refund from your Google Play order history or follow the instructions from Google Play support.',
  '3. 구독 관리와 취소': '3. Manage or cancel your subscription', 'Google Play 구독 관리': 'Google Play subscription settings',
  '에서 관리하거나 취소할 수 있습니다. 취소 후에도 이미 결제한 기간이 끝날 때까지 광고 제거와 OCR 생성 혜택이 유지되며, 기간이 끝나면 광고가 다시 표시되고 새 OCR 생성은 사용할 수 없습니다. 이미 만든 PDF는 계속 열 수 있습니다.': ' to manage or cancel your subscription. After cancellation, ad removal and OCR creation remain available until the paid period ends. Ads will then return and you will no longer be able to create new OCR PDFs. You can still open PDFs you already created.',
  '4. 앱 사용 문제': '4. App issues',
  '구독이 반영되지 않거나 광고 제거 기능에 문제가 있으면 앱 설정의 구독 상태 갱신을 먼저 시도해 주세요. 해결되지 않으면 ': 'If your subscription does not appear or ad removal is not working, first refresh the subscription status in the app settings. If the issue continues, contact us through ',
  '에 주문 번호, 기기 정보, 문제 상황을 보내 주세요. 결제 수단 번호나 비밀번호는 보내지 마세요.': ' with your order number, device information, and a description of the issue. Do not send payment card numbers or passwords.',
  '5. 처리 결과': '5. Resolution',
  '개발자는 기능 오류 확인과 안내를 지원하며, 최종 환불 승인과 결제 처리는 Google Play 및 관련 결제 정책에 따릅니다.': 'The developer can help investigate app issues and provide guidance. Final refund approval and payment processing follow Google Play policies and applicable payment rules.',
  'PDF 대리 홈페이지': 'PDF Daeri home',
}).map(([koreanText, englishText]) => [normalizeText(koreanText), englishText]));

function getPreferredLanguage() {
  const savedLanguage = localStorage.getItem(languagePreferenceKey);
  if (savedLanguage === 'ko' || savedLanguage === 'en') return savedLanguage;
  return navigator.language?.toLowerCase().startsWith('ko') ? 'ko' : 'en';
}

function normalizeText(value) {
  return value.trim().replace(/\s+/g, ' ');
}

function addLanguageSelector() {
  const header = document.querySelector('.site-header');
  if (!header || header.querySelector('.language-select')) return;

  const selector = document.createElement('select');
  selector.className = 'language-select';
  selector.setAttribute('aria-label', 'Language / 언어');
  selector.add(new Option('한국어', 'ko'));
  selector.add(new Option('English', 'en'));
  selector.value = getPreferredLanguage();
  selector.addEventListener('change', () => {
    localStorage.setItem(languagePreferenceKey, selector.value);
    applyLanguage(selector.value);
  });
  header.insertBefore(selector, header.querySelector('.header-install'));
}

function addFeatureMenuBehavior() {
  const menuItems = [...document.querySelectorAll('.nav-item')];
  if (menuItems.length === 0) return;

  for (const item of menuItems) {
    const button = item.querySelector('button');
    if (!button) continue;
    button.setAttribute('aria-expanded', 'false');
    button.addEventListener('click', (event) => {
      event.stopPropagation();
      const shouldOpen = !item.classList.contains('is-open');
      for (const otherItem of menuItems) {
        otherItem.classList.remove('is-open');
        otherItem.querySelector('button')?.setAttribute('aria-expanded', 'false');
      }
      if (!shouldOpen) return;
      item.classList.add('is-open');
      button.setAttribute('aria-expanded', 'true');
    });
  }

  document.addEventListener('click', () => {
    for (const item of menuItems) {
      item.classList.remove('is-open');
      item.querySelector('button')?.setAttribute('aria-expanded', 'false');
    }
  });
  document.addEventListener('keydown', (event) => {
    if (event.key !== 'Escape') return;
    for (const item of menuItems) {
      item.classList.remove('is-open');
      item.querySelector('button')?.setAttribute('aria-expanded', 'false');
    }
  });
}

function translateTextNodes(language) {
  const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
  for (let node = walker.nextNode(); node; node = walker.nextNode()) {
    if (!node.__koreanText) node.__koreanText = node.nodeValue;
    if (language === 'ko') {
      node.nodeValue = node.__koreanText;
      continue;
    }

    const sourceText = normalizeText(node.__koreanText);
    const translatedText = englishCopy.get(sourceText);
    if (!translatedText) continue;
    const leadingWhitespace = node.__koreanText.match(/^\s*/)?.[0] ?? '';
    const trailingWhitespace = node.__koreanText.match(/\s*$/)?.[0] ?? '';
    node.nodeValue = `${leadingWhitespace}${translatedText}${trailingWhitespace}`;
  }
}

function translateAccessibleLabels(language) {
  document.querySelectorAll('[aria-label], img[alt]').forEach((element) => {
    const attributeName = element.hasAttribute('aria-label') ? 'aria-label' : 'alt';
    const originalValue = `korean${attributeName === 'alt' ? 'Alt' : 'Label'}`;
    if (!element.dataset[originalValue]) element.dataset[originalValue] = element.getAttribute(attributeName);
    const koreanValue = element.dataset[originalValue];
    element.setAttribute(
      attributeName,
      language === 'en' ? englishCopy.get(koreanValue) ?? koreanValue : koreanValue,
    );
  });
}

function applyLanguage(language) {
  const pageName = location.pathname.split('/').pop() || 'index.html';
  document.documentElement.lang = language;
  translateTextNodes(language);
  translateAccessibleLabels(language);

  const selector = document.querySelector('.language-select');
  if (selector) selector.value = language;

  if (language === 'en') {
    const page = pageCopy[pageName] ?? pageCopy['index.html'];
    document.title = page.title;
    document.querySelector('meta[name="description"]')?.setAttribute('content', page.description);
    document.querySelector('meta[property="og:title"]')?.setAttribute('content', page.title);
    document.querySelector('meta[property="og:description"]')?.setAttribute('content', page.description);
    document.querySelectorAll('img').forEach((image) => {
      if (!image.dataset.koreanAlt) image.dataset.koreanAlt = image.alt;
      if (image.alt) image.alt = englishCopy.get(image.dataset.koreanAlt) ?? image.dataset.koreanAlt;
    });
  } else {
    document.title = originalPageTitle;
    for (const [meta, originalContent] of originalMetaValues) meta.content = originalContent;
    document.querySelectorAll('img[data-korean-alt]').forEach((image) => {
      image.alt = image.dataset.koreanAlt;
    });
  }
  if (visitorCounter) {
    visitorCounter.querySelectorAll('strong').forEach((element) => {
      element.textContent = new Intl.NumberFormat(language === 'en' ? 'en-US' : 'ko-KR')
        .format(Number(element.textContent.replace(/,/g, '')) || 0);
    });
  }
}

document.querySelector('#year')?.append(new Date().getFullYear());
addLanguageSelector();
addFeatureMenuBehavior();
applyLanguage(getPreferredLanguage());

if (visitorCounter) loadVisitCount();

async function loadVisitCount() {
  try {
    const response = await fetch('/.netlify/functions/visit-count', {
      method: 'POST',
      headers: { Accept: 'application/json', 'Content-Type': 'application/json' },
      body: JSON.stringify({ visitorToken: getVisitorToken() }),
    });
    if (!response.ok) return;
    const { todayCount, totalCount } = await response.json();
    updateVisitCount('today', todayCount);
    updateVisitCount('total', totalCount);
    visitorCounter.hidden = false;
  } catch {
    // Keep the page usable when visit counting is unavailable.
  }
}

function getVisitorToken() {
  const savedToken = localStorage.getItem(visitorTokenKey);
  if (savedToken) return savedToken;
  const visitorToken = crypto.randomUUID();
  localStorage.setItem(visitorTokenKey, visitorToken);
  return visitorToken;
}

function updateVisitCount(type, count) {
  const element = visitorCounter.querySelector(`[data-visit-count="${type}"]`);
  if (!element) return;
  element.textContent = new Intl.NumberFormat(
    document.documentElement.lang === 'en' ? 'en-US' : 'ko-KR',
  ).format(count);
}

const revealTargets = document.querySelectorAll('.reveal');
if (revealTargets.length && 'IntersectionObserver' in window) {
  const observer = new IntersectionObserver((entries, currentObserver) => {
    for (const entry of entries) {
      if (!entry.isIntersecting) continue;
      entry.target.classList.add('is-visible');
      currentObserver.unobserve(entry.target);
    }
  }, { threshold: 0.3 });
  revealTargets.forEach((target) => observer.observe(target));
} else {
  revealTargets.forEach((target) => target.classList.add('is-visible'));
}
