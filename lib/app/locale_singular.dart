/// English singular forms (n == 1) for count templates, keyed by the Korean
/// key used with appCount. Missing keys fall back to the plural entry.
const englishSingular = <String, String>{
  '{count}쪽': '{count} page',
  '{count}개 문서와 앱 안의 원본이 삭제됩니다.':
      'Delete {count} document and its source from the app.',
  '{count}개 문서를 삭제했습니다': 'Deleted {count} document',
  '{count}쪽 · {size} · {date}': '{count} page · {size} · {date}',
  '새 파일로 저장됨 — "{title}" ({count}쪽)':
      'Saved as a new file — "{title}" ({count} page)',
  '{count}장': '{count} photo',
};
