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

    test('ImagePageRef with crop round trips', () {
      const crop = CropRect(left: 0.1, top: 0.2, right: 0.9, bottom: 0.8);
      const ref = ImagePageRef(imagePath: 'docs/abc/sources/pages/002.jpg', rotation: 0, crop: crop);
      final map = ref.toMap();
      expect(map['crop'], '0.1,0.2,0.9,0.8');

      final restored = PageRef.fromMap(map);
      expect(restored, isA<ImagePageRef>());
      restored as ImagePageRef;
      expect(restored.imagePath, ref.imagePath);
      expect(restored.crop, crop);
    });

    test('ImagePageRef without crop round trips as null (crop optional field 하위 호환)', () {
      const ref = ImagePageRef(imagePath: 'docs/abc/sources/pages/003.jpg', rotation: 0);
      final map = ref.toMap();
      expect(map['crop'], isNull);

      final restored = PageRef.fromMap(map);
      expect((restored as ImagePageRef).crop, isNull);
    });
  });

  group('PageRef rotation invariant', () {
    test('invalid rotation triggers assertion', () {
      expect(() => ImagePageRef(imagePath: 'a', rotation: 45), throwsA(isA<AssertionError>()));
    });
  });

  group('CropRect', () {
    test('encode/decode round trips', () {
      const crop = CropRect(left: 0.0, top: 0.125, right: 1.0, bottom: 0.875);
      final decoded = CropRect.decode(crop.encode());
      expect(decoded, crop);
    });

    test('decode(null) returns null', () {
      expect(CropRect.decode(null), isNull);
    });

    test('isFull is true only for the full-region rect', () {
      expect(const CropRect(left: 0, top: 0, right: 1, bottom: 1).isFull, isTrue);
      expect(const CropRect(left: 0.1, top: 0, right: 1, bottom: 1).isFull, isFalse);
    });

    test('equality is value-based', () {
      const a = CropRect(left: 0.1, top: 0.2, right: 0.9, bottom: 0.8);
      const b = CropRect(left: 0.1, top: 0.2, right: 0.9, bottom: 0.8);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('invalid rect (right <= left) triggers assertion', () {
      expect(() => CropRect(left: 0.5, top: 0, right: 0.5, bottom: 1), throwsA(isA<AssertionError>()));
    });

    test('invalid rect (out of 0..1 range) triggers assertion', () {
      expect(() => CropRect(left: -0.1, top: 0, right: 1, bottom: 1), throwsA(isA<AssertionError>()));
    });
  });
}
