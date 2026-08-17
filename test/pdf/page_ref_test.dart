import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_daeri/pdf/page_ref.dart';

void main() {
  group('PageRef toMap/fromMap round trip', () {
    test('ImagePageRef round trips', () {
      const ref = ImagePageRef(imagePath: 'docs/abc/sources/pages/001.jpg', rotation: 90);
      final map = ref.toMap();
      final restored = PageRef.fromMap(map);

      expect(restored, isA<ImagePageRef>());
      restored as ImagePageRef;
      expect(restored.imagePath, ref.imagePath);
      expect(restored.rotation, ref.rotation);
    });

    test('PdfPageRef round trips', () {
      const ref = PdfPageRef(sourcePath: 'docs/abc/sources/src_1.pdf', sourceIndex: 3, rotation: 180);
      final map = ref.toMap();
      final restored = PageRef.fromMap(map);

      expect(restored, isA<PdfPageRef>());
      restored as PdfPageRef;
      expect(restored.sourcePath, ref.sourcePath);
      expect(restored.sourceIndex, ref.sourceIndex);
      expect(restored.rotation, ref.rotation);
    });

    test('ImagePageRef with rotation 0 round trips', () {
      const ref = ImagePageRef(imagePath: 'docs/x/sources/pages/000.jpg', rotation: 0);
      final restored = PageRef.fromMap(ref.toMap());
      expect(restored, isA<ImagePageRef>());
      expect((restored as ImagePageRef).rotation, 0);
    });

    test('PdfPageRef with rotation 270 round trips', () {
      const ref = PdfPageRef(sourcePath: 'recent/uuid.pdf', sourceIndex: 0, rotation: 270);
      final restored = PageRef.fromMap(ref.toMap());
      expect(restored, isA<PdfPageRef>());
      expect((restored as PdfPageRef).rotation, 270);
    });

    test('fromMap throws on unknown kind', () {
      expect(() => PageRef.fromMap({'kind': 'unknown'}), throwsStateError);
    });
  });

  group('PageRef rotation invariant', () {
    test('invalid rotation triggers assertion', () {
      expect(() => ImagePageRef(imagePath: 'a', rotation: 45), throwsA(isA<AssertionError>()));
    });
  });
}
