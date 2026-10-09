import Flutter
import Photos
import UIKit
import VisionKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    PlatformChannels.register(messenger: engineBridge.applicationRegistrar.messenger())
  }
}

/// Android `MainActivity.kt`의 플랫폼 채널과 같은 이름·같은 계약을 iOS에서 구현한다.
/// Dart 쪽(`lib/`)은 채널 이름과 인자·오류 코드만 알고 플랫폼을 구분하지 않는다.
///
///  - storage: 여유 공간, 사진 보관함 저장, 민감 클립보드, 네이티브 캐시 정리
///  - saf: 파일 URL → 앱 작업공간 복사 (규칙 6: 원본은 읽기만 한다)
///  - intent: 다른 앱에서 "이 앱으로 열기"로 넘어온 PDF URL 수신
///  - update: iOS에는 인앱 업데이트가 없다 — 항상 false
///  - document_scanner: VisionKit 문서 카메라 (규칙 5: OS가 제공하는 완성된 스캔 플로우)
enum PlatformChannels {
  static let prefix = "com.kamanbi.pdf_daeri"
  static let maxImportedPdfBytes: Int64 = 100 * 1024 * 1024

  static var intentStream = IntentStreamHandler()
  static var pendingInitialUri: String?
  static let scanner = DocumentScanner()

  static func register(messenger: FlutterBinaryMessenger) {
    FlutterMethodChannel(name: "\(prefix)/storage", binaryMessenger: messenger)
      .setMethodCallHandler { call, result in handleStorage(call, result) }
    FlutterMethodChannel(name: "\(prefix)/saf", binaryMessenger: messenger)
      .setMethodCallHandler { call, result in handleSaf(call, result) }
    FlutterMethodChannel(name: "\(prefix)/update", binaryMessenger: messenger)
      .setMethodCallHandler { call, result in
        switch call.method {
        case "isImmediateUpdateAvailable", "startImmediateUpdate": result(false)
        default: result(FlutterMethodNotImplemented)
        }
      }
    FlutterMethodChannel(name: "\(prefix)/document_scanner", binaryMessenger: messenger)
      .setMethodCallHandler { call, result in
        if call.method == "start" { scanner.start(result) } else { result(FlutterMethodNotImplemented) }
      }
    FlutterMethodChannel(name: "\(prefix)/intent", binaryMessenger: messenger)
      .setMethodCallHandler { call, result in
        if call.method == "takeInitialUri" {
          let uri = pendingInitialUri
          pendingInitialUri = nil
          result(uri)
        } else {
          result(FlutterMethodNotImplemented)
        }
      }
    FlutterEventChannel(name: "\(prefix)/intent/stream", binaryMessenger: messenger)
      .setStreamHandler(intentStream)
  }

  // MARK: intent

  /// SceneDelegate가 URL을 받을 때마다 호출한다. 다른 앱 컨테이너·임시 Inbox의 파일 URL만 통과시킨다
  /// (M-2: 이 앱 자신의 작업공간 파일을 가리키는 URL은 거부).
  static func deliver(_ url: URL) {
    guard url.isFileURL else { return }
    let path = url.standardizedFileURL.path
    if path.hasPrefix(NSHomeDirectory()) && !path.contains("/Inbox/") { return }
    let uri = url.absoluteString
    if let sink = intentStream.sink {
      sink(uri)
    } else {
      pendingInitialUri = uri
    }
  }

  // MARK: storage

  private static func handleStorage(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any]
    switch call.method {
    case "getFreeSpaceBytes":
      do {
        let attrs = try FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory())
        result((attrs[.systemFreeSize] as? NSNumber)?.int64Value ?? 0)
      } catch {
        result(FlutterError(code: "STATFS_FAILED", message: "저장공간을 확인하지 못했습니다.", details: nil))
      }

    case "exportPdf":
      // iOS에는 공용 다운로드 폴더가 없다. 파일은 앱 보관함에 이미 있고 공유 시트의
      // "파일에 저장"으로 내보내므로 여기서는 원본 존재만 확인한다.
      guard let source = args?["sourcePdfPath"] as? String else {
        return result(FlutterError(code: "INVALID_ARGS", message: "sourcePdfPath required", details: nil))
      }
      if FileManager.default.fileExists(atPath: source) {
        result(source)
      } else {
        result(FlutterError(code: "NOT_FOUND", message: "저장한 PDF를 찾을 수 없습니다.", details: nil))
      }

    case "exportImage":
      guard let source = args?["sourceImagePath"] as? String,
        let displayName = args?["displayName"] as? String,
        let rotation = args?["rotationDegrees"] as? Int,
        let quality = args?["jpegQuality"] as? Int
      else {
        return result(FlutterError(code: "INVALID_ARGS", message: "sourceImagePath/displayName/rotationDegrees/jpegQuality required", details: nil))
      }
      exportImage(source: source, displayName: displayName, rotation: rotation, quality: quality, result: result)

    case "setSensitiveClip":
      guard let text = args?["text"] as? String else {
        return result(FlutterError(code: "INVALID_ARGS", message: "text required", details: nil))
      }
      UIPasteboard.general.setItems(
        [["public.utf8-plain-text": text]],
        options: [.localOnly: true, .expirationDate: Date().addingTimeInterval(120)]
      )
      result(true)

    case "clearNativeCache":
      result(clearNativeCache())

    case "nativeCacheBytes":
      result(nativeCacheBytes())

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private static func exportImage(
    source: String, displayName: String, rotation: Int, quality: Int, result: @escaping FlutterResult
  ) {
    guard FileManager.default.fileExists(atPath: source) else {
      return result(FlutterError(code: "NOT_FOUND", message: "저장할 사진을 찾을 수 없습니다.", details: nil))
    }
    PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
      guard status == .authorized || status == .limited else {
        DispatchQueue.main.async {
          result(FlutterError(code: "EXPORT_FAILED", message: "사진 보관함 접근 권한이 없습니다.", details: nil))
        }
        return
      }
      DispatchQueue.global(qos: .userInitiated).async {
        let normalized = ((rotation % 360) + 360) % 360
        var data: Data?
        if normalized == 0 {
          data = try? Data(contentsOf: URL(fileURLWithPath: source))
        } else if let image = UIImage(contentsOfFile: source) {
          data = rotated(image, degrees: normalized).jpegData(
            compressionQuality: CGFloat(min(max(quality, 1), 100)) / 100)
        }
        guard let jpeg = data, !jpeg.isEmpty else {
          DispatchQueue.main.async {
            result(FlutterError(code: "EXPORT_FAILED", message: "사진을 내보내지 못했습니다.", details: nil))
          }
          return
        }
        var placeholder: String?
        PHPhotoLibrary.shared().performChanges({
          let request = PHAssetCreationRequest.forAsset()
          let options = PHAssetResourceCreationOptions()
          options.originalFilename = displayName
          request.addResource(with: .photo, data: jpeg, options: options)
          placeholder = request.placeholderForCreatedAsset?.localIdentifier
        }) { success, _ in
          DispatchQueue.main.async {
            if success {
              result("ph://\(placeholder ?? "")")
            } else {
              result(FlutterError(code: "EXPORT_FAILED", message: "사진을 내보내지 못했습니다.", details: nil))
            }
          }
        }
      }
    }
  }

  private static func rotated(_ image: UIImage, degrees: Int) -> UIImage {
    let swap = degrees == 90 || degrees == 270
    let size = swap ? CGSize(width: image.size.height, height: image.size.width) : image.size
    let format = UIGraphicsImageRendererFormat()
    format.scale = image.scale
    format.opaque = true
    return UIGraphicsImageRenderer(size: size, format: format).image { context in
      let cg = context.cgContext
      cg.translateBy(x: size.width / 2, y: size.height / 2)
      cg.rotate(by: CGFloat(degrees) * .pi / 180)
      image.draw(in: CGRect(
        x: -image.size.width / 2, y: -image.size.height / 2,
        width: image.size.width, height: image.size.height))
    }
  }

  private static func inboxDirectory() -> URL {
    URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("Inbox")
  }

  private static func directoryBytes(_ dir: URL) -> Int64 {
    guard let files = FileManager.default.enumerator(
      at: dir, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
    var total: Int64 = 0
    for case let url as URL in files {
      total += Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
    }
    return total
  }

  /// 스캐너가 임시 폴더에 남기는 JPEG(`mlkit_scan_*`) — Android `cacheDir`의 같은 이름 파일과 같은 역할.
  private static func scanTempFiles() -> [URL] {
    let dir = URL(fileURLWithPath: NSTemporaryDirectory())
    let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
    return files.filter { $0.lastPathComponent.hasPrefix("mlkit_scan_") }
  }

  private static func nativeCacheBytes() -> Int64 {
    scanTempFiles().reduce(directoryBytes(inboxDirectory())) { total, url in
      total + Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
    }
  }

  private static func clearNativeCache() -> Int64 {
    let freed = nativeCacheBytes()
    try? FileManager.default.removeItem(at: inboxDirectory())
    for url in scanTempFiles() { try? FileManager.default.removeItem(at: url) }
    return freed
  }

  // MARK: saf

  private enum CopyError: Error { case invalidPdf, tooLarge }

  private static func handleSaf(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    guard call.method == "copyContentUri" else { return result(FlutterMethodNotImplemented) }
    let args = call.arguments as? [String: Any]
    guard let uri = args?["uri"] as? String, let destination = args?["destinationPath"] as? String else {
      return result(FlutterError(code: "INVALID_ARGS", message: "uri/destinationPath required", details: nil))
    }
    DispatchQueue.global(qos: .userInitiated).async {
      let outcome = copyFile(uri: uri, destination: destination)
      DispatchQueue.main.async { result(outcome) }
    }
  }

  /// 성공 시 [String: Any], 실패 시 FlutterError. 원본은 읽기만 한다.
  private static func copyFile(uri: String, destination: String) -> Any {
    guard let url = URL(string: uri), url.isFileURL else {
      return FlutterError(code: "INVALID_SCHEME", message: "파일 URL만 허용됩니다.", details: nil)
    }
    let scoped = url.startAccessingSecurityScopedResource()
    defer { if scoped { url.stopAccessingSecurityScopedResource() } }

    let destURL = URL(fileURLWithPath: destination)
    do {
      if let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize, Int64(size) > maxImportedPdfBytes {
        throw CopyError.tooLarge
      }
      try FileManager.default.createDirectory(
        at: destURL.deletingLastPathComponent(), withIntermediateDirectories: true)
      FileManager.default.createFile(atPath: destination, contents: nil)
      let input = try FileHandle(forReadingFrom: url)
      let output = try FileHandle(forWritingTo: destURL)
      defer {
        try? input.close()
        try? output.close()
      }
      guard let header = try input.read(upToCount: 5), header == Data("%PDF-".utf8) else {
        throw CopyError.invalidPdf
      }
      try output.write(contentsOf: header)
      var copied = Int64(header.count)
      while let chunk = try input.read(upToCount: 1 << 20), !chunk.isEmpty {
        copied += Int64(chunk.count)
        if copied > maxImportedPdfBytes { throw CopyError.tooLarge }
        try output.write(contentsOf: chunk)
      }
      return ["displayName": url.lastPathComponent, "bytes": copied]
    } catch {
      try? FileManager.default.removeItem(at: destURL)
      switch error {
      case CopyError.invalidPdf:
        return FlutterError(code: "INVALID_PDF", message: "올바른 PDF 파일이 아닙니다.", details: nil)
      case CopyError.tooLarge:
        return FlutterError(code: "FILE_TOO_LARGE", message: "PDF files must be 100MB or smaller", details: nil)
      default:
        let code = (error as NSError).code
        if code == NSFileReadNoSuchFileError || code == NSFileNoSuchFileError {
          return FlutterError(code: "NOT_FOUND", message: "파일을 찾을 수 없습니다.", details: nil)
        }
        if code == NSFileReadNoPermissionError {
          return FlutterError(code: "PERMISSION_DENIED", message: "파일 접근 권한이 없습니다.", details: nil)
        }
        return FlutterError(code: "IO_ERROR", message: "파일을 읽는 중 오류가 발생했습니다.", details: nil)
      }
    }
  }
}

final class IntentStreamHandler: NSObject, FlutterStreamHandler {
  var sink: FlutterEventSink?

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    sink = events
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    sink = nil
    return nil
  }
}

/// VisionKit 문서 카메라. Android 계약과 같게 첫 페이지 JPEG 경로 한 장만 돌려준다
/// (스캔 화면이 한 장씩 받는다). 취소는 nil, 사용 불가는 UNAVAILABLE.
final class DocumentScanner: NSObject, VNDocumentCameraViewControllerDelegate {
  private var pending: FlutterResult?

  func start(_ result: @escaping FlutterResult) {
    guard pending == nil else {
      return result(FlutterError(code: "IN_PROGRESS", message: "문서 스캔이 이미 진행 중입니다.", details: nil))
    }
    guard VNDocumentCameraViewController.isSupported, let presenter = Self.topViewController() else {
      return result(FlutterError(code: "UNAVAILABLE", message: "이 기기에서는 문서 스캔을 사용할 수 없습니다.", details: nil))
    }
    pending = result
    let controller = VNDocumentCameraViewController()
    controller.delegate = self
    presenter.present(controller, animated: true)
  }

  private func finish(_ controller: VNDocumentCameraViewController, _ value: Any?) {
    let result = pending
    pending = nil
    controller.dismiss(animated: true) { result?(value) }
  }

  func documentCameraViewController(
    _ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan
  ) {
    guard scan.pageCount > 0, let jpeg = scan.imageOfPage(at: 0).jpegData(compressionQuality: 0.95) else {
      return finish(controller, nil)
    }
    let path = NSTemporaryDirectory() + "mlkit_scan_\(Int(Date().timeIntervalSince1970 * 1000)).jpg"
    do {
      try jpeg.write(to: URL(fileURLWithPath: path), options: .atomic)
      finish(controller, path)
    } catch {
      finish(controller, FlutterError(code: "COPY_FAILED", message: "스캔 결과를 가져오지 못했습니다.", details: nil))
    }
  }

  func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
    finish(controller, nil)
  }

  func documentCameraViewController(
    _ controller: VNDocumentCameraViewController, didFailWithError error: Error
  ) {
    finish(controller, FlutterError(code: "UNAVAILABLE", message: error.localizedDescription, details: nil))
  }

  private static func topViewController() -> UIViewController? {
    let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
      .first { $0.activationState == .foregroundActive }
    var top = scene?.windows.first(where: \.isKeyWindow)?.rootViewController
    while let presented = top?.presentedViewController { top = presented }
    return top
  }
}
