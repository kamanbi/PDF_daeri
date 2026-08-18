package com.kamanbi.pdf_daeri

import android.content.Intent
import android.database.Cursor
import android.net.Uri
import android.os.Bundle
import android.os.StatFs
import android.provider.OpenableColumns
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
    override fun shouldHandleDeeplinking(): Boolean = false
    private val storageChannel = "com.kamanbi.pdf_daeri/storage"
    private val safChannel = "com.kamanbi.pdf_daeri/saf"
    private val intentMethodChannel = "com.kamanbi.pdf_daeri/intent"
    private val intentEventChannel = "com.kamanbi.pdf_daeri/intent/stream"

    // 콜드 스타트로 앱을 연 VIEW 인텐트의 URI. takeInitialUri() 1회 호출로 소비된다
    // (그 이후 재조회하면 null — 화면 재구성 시 같은 문서를 중복 임포트하지 않기 위함).
    private var pendingInitialUri: String? = null
    private var intentEventSink: EventChannel.EventSink? = null

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
        return intent.data?.toString()
    }

    private fun copyContentUriToPath(uriString: String, destinationPath: String, result: MethodChannel.Result) {
        try {
            val uri = Uri.parse(uriString)
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
