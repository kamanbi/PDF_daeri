/// 이미지 인코딩 전용 isolate 워커. §8.1/§8.3 개정(V-2).
///
/// **이 파일은 `pdfrx`/`pdfrx_engine`을 절대 import하지 않는다**(§8.4 규칙 1). 순수 Dart
/// (`package:image`, 이 파일이 감싸는 `image_pdf_builder.dart`)만 다룬다. PDF 문서·페이지 객체는
/// 이 파일 어디에도 없다 — PDF 핸들을 쥔 코드(`pdf_engine_isolate.dart`)와 이미지 코덱을 쥔 코드가
/// isolate 경계로 완전히 갈라진다(2-키 분리가 파일 규약에서 isolate 경계로 승격, §8.4 부수 효과).
///
/// `Isolate.spawn`은 이 파일에만 있다 — 프로세스 안에서 pdfrx를 건드리는 isolate는 메인 하나뿐이어야
/// 하므로(§8.4 불변식), pdfrx를 만지지 않는 이 워커만 별도 isolate로 돌려도 안전하다.
library;

import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import '../core/cancel_token.dart';
import 'image_pdf_builder.dart';
import 'page_ref.dart' show CropRect;

/// 인코딩 대상 1장. `(경로, 크롭)` 쌍이다 -- 같은 마스터 경로가 서로 다른 크롭으로 여러 번
/// 나올 수 있으므로(설계 §2.5) 경로 목록이 아니라 이 쌍의 목록을 받는다. [cropEncoded]는
/// `CropRect.encode()` 결과 또는 크롭 없음이면 null이다 -- isolate 경계는 원시 타입만 넘긴다.
class ImageEncodeItem {
  const ImageEncodeItem({required this.imagePath, required this.cropEncoded});
  final String imagePath;
  final String? cropEncoded;
}

/// 워커 스폰 인자. 전부 원시 타입 — isolate 경계를 넘긴다.
class ImageEncodeRequest {
  const ImageEncodeRequest({
    required this.items,
    required this.longEdgeMaxPx,
    required this.jpegQuality,
    required this.resultSendPort,
    required this.dataSendPort,
    required this.readySendPort,
  });

  /// `ImagePageRef.imagePath` 목록(순서대로, `sources/pages/NNN.jpg` 마스터 경로 -- A-3).
  final List<ImageEncodeItem> items;
  final int longEdgeMaxPx;
  final int jpegQuality;

  final SendPort resultSendPort;

  /// 이미지 1장 인코딩이 끝날 때마다 결과를 이 포트로 보낸다(§8.3 "1장씩").
  final SendPort dataSendPort;

  /// 워커가 취소 수신용 `SendPort`를 돌려보내는 핸드셰이크 포트.
  final SendPort readySendPort;
}

/// 워커 진입 함수. 순수 Dart 이미지 인코딩만 수행한다 -- PDF 문서를 열거나 만들지 않는다.
///
/// [dataSendPort]로 보내는 각 메시지: `{'index': int, 'bytes': Uint8List, 'boxW': double, 'boxH': double}`
/// [resultSendPort]로 보내는 최종 메시지: 성공 `{'ok': true}` / 실패 `{'error': <code>, 'detail': String?}`
Future<void> imageEncodeIsolateEntryPoint(ImageEncodeRequest args) async {
  final cancelReceivePort = ReceivePort();
  args.readySendPort.send(cancelReceivePort.sendPort);
  var cancelled = false;
  final cancelSub = cancelReceivePort.listen((_) => cancelled = true);

  try {
    for (var i = 0; i < args.items.length; i++) {
      if (cancelled) {
        args.resultSendPort.send({'error': 'cancelled'});
        return;
      }

      final item = args.items[i];
      final path = item.imagePath;
      if (!File(path).existsSync()) {
        args.resultSendPort.send({'error': 'missing', 'detail': path});
        return;
      }

      // A-3: 마스터 바이트를 그대로 읽는다. 인코딩 결과는 어디에도 쓰지 않고 메인으로 보낸 뒤
      // 이 워커의 메모리에서는 폐기한다 -- 세대 손실이 누적되지 않는다.
      final Uint8List masterBytes;
      try {
        masterBytes = await File(path).readAsBytes();
      } catch (e) {
        args.resultSendPort.send({'error': 'missing', 'detail': '$path: $e'});
        return;
      }

      final crop = CropRect.decode(item.cropEncoded);
      final Uint8List embedBytes;
      final (double, double) box;
      try {
        box = ImagePdfBuilder.pageBoxFor(masterBytes, crop: crop);
        embedBytes = ImagePdfBuilder.encodeForEmbed(
          masterBytes,
          longEdgeMaxPx: args.longEdgeMaxPx,
          jpegQuality: args.jpegQuality,
          crop: crop,
        );
      } catch (e) {
        args.resultSendPort.send({'error': 'corrupted', 'detail': '$path: $e'});
        return;
      }

      args.dataSendPort.send({'index': i, 'bytes': embedBytes, 'boxW': box.$1, 'boxH': box.$2});
    }
    args.resultSendPort.send({'ok': true});
  } catch (e) {
    args.resultSendPort.send({'error': 'unknown', 'detail': e.toString()});
  } finally {
    await cancelSub.cancel();
  }
}

/// 이미지 인코딩 결과 1장.
class EncodedImage {
  const EncodedImage({required this.bytes, required this.boxWidthPt, required this.boxHeightPt});
  final Uint8List bytes;
  final double boxWidthPt;
  final double boxHeightPt;
}

/// `pdf_engine_isolate.dart`(호출한 isolate, 보통 메인)에서 부르는 진입점. isolate 스폰·3포트
/// 배선을 전부 이 함수 안에 캡슐화한다. [items]가 비어 있으면 스폰하지 않고 즉시 반환한다
/// (§8.1: "ImagePageRef가 없는 저장은 isolate를 아예 스폰하지 않는다"와 대칭 -- 이미지가 0장이면
/// 인코딩 워커도 낼 필요가 없다).
///
/// [items]는 **경로 목록이 아니라 (경로, 크롭) 쌍의 목록**이다(설계 §2.5) -- 같은 마스터 경로가
/// 서로 다른 크롭으로 여러 번 나올 수 있으므로 경로 기준 dedupe를 하지 않는다. 입력 순서 그대로
/// 인덱스로 결과를 대응시킨다.
///
/// 반환: 성공 시 `{'ok': true, 'images': List<EncodedImage>}`(입력 순서 보존),
/// 실패 시 `{'error': <code>, 'detail': String?}`.
Future<Map<String, Object?>> runImageEncodeBatch({
  required List<ImageEncodeItem> items,
  required int longEdgeMaxPx,
  required int jpegQuality,
  CancelToken? cancelToken,
}) async {
  if (items.isEmpty) {
    return {'ok': true, 'images': const <EncodedImage>[]};
  }

  final resultPort = ReceivePort();
  final dataPort = ReceivePort();
  final readyPort = ReceivePort();

  final results = List<EncodedImage?>.filled(items.length, null);
  SendPort? cancelSendPort;
  void Function()? cancelListener;
  StreamSubscription<dynamic>? readySub;
  StreamSubscription<dynamic>? dataSub;

  try {
    await Isolate.spawn(
      imageEncodeIsolateEntryPoint,
      ImageEncodeRequest(
        items: items,
        longEdgeMaxPx: longEdgeMaxPx,
        jpegQuality: jpegQuality,
        resultSendPort: resultPort.sendPort,
        dataSendPort: dataPort.sendPort,
        readySendPort: readyPort.sendPort,
      ),
    );

    readySub = readyPort.listen((message) {
      cancelSendPort = message as SendPort;
      if (cancelToken?.isCancelled ?? false) {
        cancelSendPort!.send('cancel');
      }
    });

    dataSub = dataPort.listen((message) {
      final map = message as Map<String, Object?>;
      final index = map['index']! as int;
      results[index] = EncodedImage(
        bytes: map['bytes']! as Uint8List,
        boxWidthPt: map['boxW']! as double,
        boxHeightPt: map['boxH']! as double,
      );
    });

    cancelListener = () => cancelSendPort?.send('cancel');
    cancelToken?.addListener(cancelListener);

    final result = await resultPort.first as Map<String, Object?>;
    if (result['ok'] != true) return result;
    return {'ok': true, 'images': results.map((e) => e!).toList(growable: false)};
  } finally {
    final listener = cancelListener;
    if (listener != null) cancelToken?.removeListener(listener);
    await readySub?.cancel();
    await dataSub?.cancel();
    resultPort.close();
    dataPort.close();
    readyPort.close();
  }
}
