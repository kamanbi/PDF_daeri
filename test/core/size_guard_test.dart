import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_daeri/core/size_guard.dart';

void main() {
  group('SaveOp.deletePages — result <= baseline * 1.00', () {
    const baseline = 1000000;

    test('exact limit passes', () {
      final input = GuardInput(op: SaveOp.deletePages, baselineBytes: baseline);
      final result = SizeGuard.check(input: input, resultBytes: baseline);
      expect(result, isA<GuardPass>());
    });

    test('limit + 1 byte is blocked', () {
      final input = GuardInput(op: SaveOp.deletePages, baselineBytes: baseline);
      final result = SizeGuard.check(input: input, resultBytes: baseline + 1);
      expect(result, isA<GuardBlocked>());
    });

    test('smaller than baseline passes', () {
      final input = GuardInput(op: SaveOp.deletePages, baselineBytes: baseline);
      final result = SizeGuard.check(input: input, resultBytes: baseline - 100);
      expect(result, isA<GuardPass>());
    });
  });

  group('SaveOp.reorderOrRotate — result <= baseline * 1.05', () {
    const baseline = 1000000;

    test('exact limit passes', () {
      final input = GuardInput(op: SaveOp.reorderOrRotate, baselineBytes: baseline);
      final limit = SizeGuard.limitFor(input);
      final result = SizeGuard.check(input: input, resultBytes: limit);
      expect(result, isA<GuardPass>());
    });

    test('limit + 1 byte is blocked', () {
      final input = GuardInput(op: SaveOp.reorderOrRotate, baselineBytes: baseline);
      final limit = SizeGuard.limitFor(input);
      final result = SizeGuard.check(input: input, resultBytes: limit + 1);
      expect(result, isA<GuardBlocked>());
    });

    test('limit equals floor(baseline * 1.05)', () {
      final input = GuardInput(op: SaveOp.reorderOrRotate, baselineBytes: baseline);
      expect(SizeGuard.limitFor(input), 1050000);
    });
  });

  group('SaveOp.split — result <= baseline * (selected/total) * 1.2', () {
    test('computed limit above floor passes at exact limit', () {
      // baseline large enough that computed limit exceeds the 4096-byte floor.
      const baseline = 10000000; // 10MB, 100 pages, select 10 -> ratio 0.1
      final input = GuardInput(op: SaveOp.split, baselineBytes: baseline, totalPages: 100, selectedPages: 10);
      final limit = SizeGuard.limitFor(input);
      expect(limit, (baseline * 0.1 * 1.2).floor());
      expect(SizeGuard.check(input: input, resultBytes: limit), isA<GuardPass>());
      expect(SizeGuard.check(input: input, resultBytes: limit + 1), isA<GuardBlocked>());
    });

    test('tiny selection is clamped to the 4KB floor', () {
      const baseline = 1000; // computed limit would be far below 4096
      final input = GuardInput(op: SaveOp.split, baselineBytes: baseline, totalPages: 100, selectedPages: 1);
      final limit = SizeGuard.limitFor(input);
      expect(limit, SizeGuard.splitMinLimitBytes);
    });

    test('missing totalPages/selectedPages throws ArgumentError', () {
      final input = GuardInput(op: SaveOp.split, baselineBytes: 1000);
      expect(() => SizeGuard.limitFor(input), throwsArgumentError);
    });

    test('selectedPages > totalPages throws ArgumentError', () {
      final input = GuardInput(op: SaveOp.split, baselineBytes: 1000, totalPages: 5, selectedPages: 10);
      expect(() => SizeGuard.limitFor(input), throwsArgumentError);
    });
  });

  group('SaveOp.merge — result <= sum(originals) * 1.05', () {
    test('exact limit passes, limit+1 blocked', () {
      const sumBaseline = 5000000; // caller sums originals into baselineBytes
      final input = GuardInput(op: SaveOp.merge, baselineBytes: sumBaseline);
      final limit = SizeGuard.limitFor(input);
      expect(limit, (sumBaseline * 1.05).floor());
      expect(SizeGuard.check(input: input, resultBytes: limit), isA<GuardPass>());
      expect(SizeGuard.check(input: input, resultBytes: limit + 1), isA<GuardBlocked>());
    });
  });

  group('GuardBlocked carries the offending op', () {
    test('deletePages block reports its op', () {
      final input = GuardInput(op: SaveOp.deletePages, baselineBytes: 100);
      final result = SizeGuard.check(input: input, resultBytes: 101);
      expect(result, isA<GuardBlocked>());
      expect((result as GuardBlocked).op, SaveOp.deletePages);
    });
  });
}
