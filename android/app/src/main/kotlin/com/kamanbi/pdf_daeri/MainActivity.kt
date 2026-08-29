package com.kamanbi.pdf_daeri

import android.content.Intent
import android.content.ContentValues
import android.database.Cursor
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import android.net.Uri
import android.os.Bundle
import android.os.Build
import android.os.StatFs
import android.os.Environment
import android.provider.MediaStore
import android.provider.OpenableColumns
import com.google.android.play.core.appupdate.AppUpdateManager
import com.google.android.play.core.appupdate.AppUpdateManagerFactory
import com.google.android.play.core.install.model.AppUpdateType
import com.google.android.play.core.install.model.UpdateAvailability
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileNotFoundException

/**
 * 플랫폼 채널 3종. 새 패키지 없이 Android SDK 표준 API만 쓴다.
 *
 * 1) storage — 여유 저장공간 조회(StatFs). `Workspace.freeSpaceBytes()`.
 * 2) saf — `content://` URI를 앱 작업공간 경로로 복사 + 표시명(display name) 추출.
 *    `lib/data/storage/saf_import.dart`의 `SafImporter.importToPath`.
 * 3) intent — `application/pdf` VIEW 인텐트로 전달된 `content://` URI 수신
 *    (콜드 스타트 + 앱이 이미 떠 있는 상태 양쪽). 감사 B5 대응.
 *    `lib/data/storage/saf_import.dart`의 `SafImporter.takeInitialUri`/`onNewIntentUri`.
 *
 * 절대 규칙 6(원본 미수정) 관련: 이 파일은 `content://` URI에 대해 읽기(복사)만
 * 하며 `takePersistableUriPermission` 등 지속 권한을 요청하지 않는다. 인텐트가
 * 부여한 일회성 grant로 복사가 끝나면 그걸로 충분하다.
 *
 * `shouldHandleDeeplinking()` = false 관련 (2026-08-19, _workspace/29 근거):
 * `FlutterActivity`는 `AndroidManifest.xml`에 `flutter_deeplinking_enabled`
 * 메타데이터가 없으면 **기본값 true**로 동작한다(flutter/engine
 * `FlutterActivityLaunchConfigs.deepLinkEnabled`). 이 상태에서는 `onNewIntent`가
 * 호출될 때마다(그리고 cold start의 `getInitialRoute()`에서도) 엔진이 intent의
 * `data`(URI)를 **자체적으로** `flutter/navigation` 채널의 `pushRouteInformation`으로
 * Dart Navigator에 밀어넣는다. 이 앱은 인텐트 URI를 `IncomingIntentService`
 * (EventChannel, 아래 `intentEventChannel`)로 **직접** 소비하므로, 저 자동 동작은
 * 불필요할 뿐 아니라 실제로 파일 경로가 라우트 이름으로 잘못 해석돼
 * "Could not find a generator for route" 예외를 유발한다(실기기 확인,
 * `_workspace/28_build-runner_intent_device.md`). 그래서 명시적으로 끈다.
 */
class MainActivity : FlutterActivity() {
    companion object {
        private const val IMMEDIATE_UPDATE_REQUEST_CODE = 4102
    }

    override fun shouldHandleDeeplinking(): Boolean = false
    private val storageChannel = "com.kamanbi.pdf_daeri/storage"
    private val updateChannel = "com.kamanbi.pdf_daeri/update"
    private val safChannel = "com.kamanbi.pdf_daeri/saf"
    private val intentMethodChannel = "com.kamanbi.pdf_daeri/intent"
    private val intentEventChannel = "com.kamanbi.pdf_daeri/intent/stream"

    // 콜드 스타트로 앱을 연 VIEW 인텐트의 URI. takeInitialUri() 1회 호출로 소비된다
    // (그 이후 재조회하면 null — 화면 재구성 시 같은 문서를 중복 임포트하지 않기 위함).
    private var pendingInitialUri: String? = null
    private var intentEventSink: EventChannel.EventSink? = null
    private lateinit var appUpdateManager: AppUpdateManager

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // onCreate 시점에는 시스템이 이미 intent를 attach 해 둔 상태다(생성자
        // 필드 초기화 시점에는 아직 없다).
        pendingInitialUri = extractViewUri(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val uri = extractViewUri(intent) ?: return
        val sink = intentEventSink
        if (sink != null) {
            sink.success(uri)
        } else {
            // Dart 쪽이 아직 스트림을 구독하지 않은 상태(예: 엔진 재초기화 중) —
            // 다음 콜드 스타트 조회에서라도 놓치지 않도록 보관해 둔다.
            pendingInitialUri = uri
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        appUpdateManager = AppUpdateManagerFactory.create(this)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            storageChannel,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "getFreeSpaceBytes" -> {
                    try {
                        val stat = StatFs(filesDir.path)
                        result.success(stat.availableBytes)
                    } catch (e: Exception) {
                        result.error("STATFS_FAILED", e.message, null)
                    }
                }
                "exportPdf" -> {
                    val sourcePdfPath = call.argument<String>("sourcePdfPath")
                    val displayName = call.argument<String>("displayName")
                    val folder = call.argument<String>("folder")
                    if (sourcePdfPath == null || displayName == null || folder == null) {
                        result.error("INVALID_ARGS", "sourcePdfPath/displayName/folder required", null)
                        return@setMethodCallHandler
                    }
                    exportPdfToDocuments(sourcePdfPath, displayName, folder, result)
                }
                "exportImage" -> {
                    val sourceImagePath = call.argument<String>("sourceImagePath")
                    val displayName = call.argument<String>("displayName")
                    val rotationDegrees = call.argument<Int>("rotationDegrees")
                    val jpegQuality = call.argument<Int>("jpegQuality")
                    if (sourceImagePath == null || displayName == null || rotationDegrees == null || jpegQuality == null) {
                        result.error("INVALID_ARGS", "sourceImagePath/displayName/rotationDegrees/jpegQuality required", null)
                        return@setMethodCallHandler
                    }
                    exportImageToPictures(sourceImagePath, displayName, rotationDegrees, jpegQuality, result)
                }
                "clearNativeCache" -> {
                    try {
                        result.success(clearNativeCache())
                    } catch (e: Exception) {
                        result.error("CLEAR_FAILED", e.message, null)
                    }
                }
                "nativeCacheBytes" -> {
                    try {
                        result.success(nativeCacheBytes())
                    } catch (e: Exception) {
                        result.error("USAGE_FAILED", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            updateChannel,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "isImmediateUpdateAvailable" -> checkImmediateUpdate(result)
                "startImmediateUpdate" -> startImmediateUpdate(result)
                else -> result.notImplemented()
            }
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            safChannel,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "copyContentUri" -> {
                    val uriString = call.argument<String>("uri")
                    val destinationPath = call.argument<String>("destinationPath")
                    if (uriString == null || destinationPath == null) {
                        result.error("INVALID_ARGS", "uri/destinationPath required", null)
                        return@setMethodCallHandler
                    }
                    copyContentUriToPath(uriString, destinationPath, result)
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            intentMethodChannel,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "takeInitialUri" -> {
                    val uri = pendingInitialUri
                    pendingInitialUri = null
                    result.success(uri)
                }
                else -> result.notImplemented()
            }
        }

        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            intentEventChannel,
        ).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    intentEventSink = events
                }

                override fun onCancel(arguments: Any?) {
                    intentEventSink = null
                }
            },
        )
    }

    private fun extractViewUri(intent: Intent?): String? {
        if (intent == null) return null
        if (intent.action != Intent.ACTION_VIEW) return null
        val uri = intent.data ?: return null
        if (!isAcceptableContentUri(uri)) return null
        return uri.toString()
    }

    /**
     * M-2 대응(`_workspace/64_security_review_full_app.md`): `content://`가
     * 아닌 스킴(`file://` 등)은 같은 기기의 악성 앱이 자기 UID 권한으로 열리는
     * 임의 경로를 넘겨 앱이 스스로 내부 파일을 복사하게 만들 수 있어 거부한다.
     * 자기 자신의 authority를 되받는 경우도 방어적으로 거부한다.
     */
    private fun isAcceptableContentUri(uri: Uri): Boolean {
        if (uri.scheme != android.content.ContentResolver.SCHEME_CONTENT) return false
        if (uri.authority?.startsWith(packageName) == true) return false
        return true
    }

    private fun checkImmediateUpdate(result: MethodChannel.Result) {
        appUpdateManager.appUpdateInfo
            .addOnSuccessListener { info ->
                val available = info.updateAvailability() == UpdateAvailability.UPDATE_AVAILABLE &&
                    info.isUpdateTypeAllowed(AppUpdateType.IMMEDIATE)
                result.success(available)
            }
            .addOnFailureListener { result.success(false) }
    }

    private fun startImmediateUpdate(result: MethodChannel.Result) {
        appUpdateManager.appUpdateInfo
            .addOnSuccessListener { info ->
                val available = info.updateAvailability() == UpdateAvailability.UPDATE_AVAILABLE &&
                    info.isUpdateTypeAllowed(AppUpdateType.IMMEDIATE)
                if (!available) {
                    result.success(false)
                    return@addOnSuccessListener
                }
                @Suppress("DEPRECATION")
                val started = appUpdateManager.startUpdateFlowForResult(
                    info,
                    AppUpdateType.IMMEDIATE,
                    this,
                    IMMEDIATE_UPDATE_REQUEST_CODE,
                )
                result.success(started)
            }
            .addOnFailureListener { result.success(false) }
    }

    private fun exportPdfToDocuments(
        sourcePdfPath: String,
        displayName: String,
        folder: String,
        result: MethodChannel.Result,
    ) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            result.error("UNSUPPORTED", "Android 10 이상이 필요합니다.", null)
            return
        }
        val source = File(sourcePdfPath)
        if (!source.exists()) {
            result.error("NOT_FOUND", "저장한 PDF를 찾을 수 없습니다.", null)
            return
        }
        val values = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, displayName)
            put(MediaStore.MediaColumns.MIME_TYPE, "application/pdf")
            put(
                MediaStore.MediaColumns.RELATIVE_PATH,
                "${Environment.DIRECTORY_DOWNLOADS}/PDF 대리/$folder",
            )
            put(MediaStore.MediaColumns.IS_PENDING, 1)
        }
        val resolver = contentResolver
        val uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
        if (uri == null) {
            result.error("CREATE_FAILED", "기본 폴더를 만들 수 없습니다.", null)
            return
        }
        try {
            resolver.openOutputStream(uri)?.use { output ->
                source.inputStream().use { input -> input.copyTo(output) }
            } ?: throw FileNotFoundException("공용 PDF 출력 스트림을 열 수 없습니다.")
            values.clear()
            values.put(MediaStore.MediaColumns.IS_PENDING, 0)
            resolver.update(uri, values, null, null)
            result.success(uri.toString())
        } catch (e: Exception) {
            resolver.delete(uri, null, null)
            result.error("EXPORT_FAILED", e.message, null)
        }
    }

    private fun exportImageToPictures(
        sourceImagePath: String,
        displayName: String,
        rotationDegrees: Int,
        jpegQuality: Int,
        result: MethodChannel.Result,
    ) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            result.error("UNSUPPORTED", "Android 10 이상이 필요합니다.", null)
            return
        }
        val source = File(sourceImagePath)
        if (!source.exists()) {
            result.error("NOT_FOUND", "저장할 사진을 찾을 수 없습니다.", null)
            return
        }

        val resolver = contentResolver
        var uri: Uri? = null
        try {
            val values = ContentValues().apply {
                put(MediaStore.MediaColumns.DISPLAY_NAME, displayName)
                put(MediaStore.MediaColumns.MIME_TYPE, "image/jpeg")
                put(
                    MediaStore.MediaColumns.RELATIVE_PATH,
                    "${Environment.DIRECTORY_PICTURES}/PDF 대리/스캔 문서",
                )
                put(MediaStore.MediaColumns.IS_PENDING, 1)
            }
            uri = resolver.insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, values)
            if (uri == null) {
                result.error("CREATE_FAILED", "사진 보관함을 만들 수 없습니다.", null)
                return
            }
            resolver.openOutputStream(uri)?.use { output ->
                writeJpeg(source, rotationDegrees, jpegQuality, output)
            } ?: throw FileNotFoundException("공용 사진 출력 스트림을 열 수 없습니다.")
            values.clear()
            values.put(MediaStore.MediaColumns.IS_PENDING, 0)
            resolver.update(uri, values, null, null)
            result.success(uri.toString())
        } catch (e: Exception) {
            uri?.let { resolver.delete(it, null, null) }
            result.error("EXPORT_FAILED", e.message, null)
        }
    }

    private fun writeJpeg(
        source: File,
        rotationDegrees: Int,
        jpegQuality: Int,
        output: java.io.OutputStream,
    ) {
        val normalizedRotation = ((rotationDegrees % 360) + 360) % 360
        if (normalizedRotation == 0) {
            source.inputStream().use { input -> input.copyTo(output) }
            return
        }
        val decoded = BitmapFactory.decodeFile(source.path)
            ?: throw FileNotFoundException("저장할 사진을 읽을 수 없습니다.")
        val rotated = Bitmap.createBitmap(
            decoded,
            0,
            0,
            decoded.width,
            decoded.height,
            Matrix().apply { postRotate(normalizedRotation.toFloat()) },
            true,
        )
        try {
            if (!rotated.compress(Bitmap.CompressFormat.JPEG, jpegQuality.coerceIn(1, 100), output)) {
                throw IllegalStateException("사진 JPEG 인코딩에 실패했습니다.")
            }
        } finally {
            if (rotated !== decoded) rotated.recycle()
            decoded.recycle()
        }
    }

    private fun copyContentUriToPath(uriString: String, destinationPath: String, result: MethodChannel.Result) {
        try {
            val uri = Uri.parse(uriString)
            // M-2 대응: 진입점 2곳(`extractViewUri`도 검증) 모두 방어한다 — 이
            // 채널은 SAF 피커에서도 호출되지만 스킴 검증 자체는 항상 유효하다.
            if (!isAcceptableContentUri(uri)) {
                result.error("INVALID_SCHEME", "content:// URI만 허용됩니다: $uriString", null)
                return
            }
            val displayName = queryDisplayName(uri)

            val destFile = File(destinationPath)
            destFile.parentFile?.mkdirs()

            val input = contentResolver.openInputStream(uri)
            if (input == null) {
                result.error("NOT_FOUND", "openInputStream returned null for $uriString", null)
                return
            }
            input.use { streamIn ->
                destFile.outputStream().use { streamOut ->
                    streamIn.copyTo(streamOut)
                }
            }

            result.success(
                mapOf(
                    "displayName" to displayName,
                    "bytes" to destFile.length(),
                ),
            )
        } catch (e: FileNotFoundException) {
            result.error("NOT_FOUND", e.message, null)
        } catch (e: SecurityException) {
            result.error("PERMISSION_DENIED", e.message, null)
        } catch (e: Exception) {
            result.error("IO_ERROR", e.message, null)
        }
    }

    /**
     * M-3 대응(`_workspace/64_security_review_full_app.md`): `third_party/doclens`가
     * `cacheDir`(및 `File.createTempFile` 기본 임시 디렉터리 — Android에서는
     * `cacheDir`와 동일)에 `fnds_*` 접두사로 남기는 스캔 원본·보정 JPEG과
     * `share_plus`의 `cacheDir/share_plus/` 공유 스테이징을 정리한다.
     * doclens 소스 자체는 벤더링된 외부 코드라 고치지 않고(2026-08-26 확정),
     * 이 네이티브 채널에서 대신 치운다. Dart 쪽은
     * `lib/data/storage/workspace.dart`의 `clearCache()`/`ensureLayout()`에서
     * 이 메서드를 호출한다.
     */
    private fun clearNativeCache(): Long {
        var freed = 0L
        val cache = cacheDir ?: return 0L
        cache.listFiles()?.forEach { f ->
            if (f.isFile && f.name.startsWith("fnds_")) {
                val len = f.length()
                if (f.delete()) freed += len
            }
        }
        val sharePlusDir = File(cache, "share_plus")
        if (sharePlusDir.exists()) {
            freed += dirBytes(sharePlusDir)
            sharePlusDir.deleteRecursively()
        }
        return freed
    }

    private fun nativeCacheBytes(): Long {
        val cache = cacheDir ?: return 0L
        var bytes = 0L
        cache.listFiles()?.forEach { f ->
            if (f.isFile && f.name.startsWith("fnds_")) bytes += f.length()
        }
        bytes += dirBytes(File(cache, "share_plus"))
        return bytes
    }

    private fun dirBytes(dir: File): Long {
        if (!dir.exists()) return 0L
        var bytes = 0L
        dir.listFiles()?.forEach { f ->
            bytes += if (f.isDirectory) dirBytes(f) else f.length()
        }
        return bytes
    }

    private fun queryDisplayName(uri: Uri): String? {
        var cursor: Cursor? = null
        try {
            cursor = contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)
            if (cursor != null && cursor.moveToFirst()) {
                val idx = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                if (idx >= 0) {
                    return cursor.getString(idx)
                }
            }
        } catch (e: Exception) {
            // 표시명 조회 실패는 치명적이지 않다 — null 반환, 파일명 폴백은
            // Dart 쪽 FileName.normalize가 담당한다.
        } finally {
            cursor?.close()
        }
        return null
    }
}
