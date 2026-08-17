package com.kamanbi.pdf_daeri

import android.os.StatFs
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * 플랫폼 채널: 여유 저장공간 조회.
 * dart:io / path_provider 어느 쪽도 크로스플랫폼 여유공간 API를 제공하지 않아
 * (설계 §7.3 "저장 전 여유 공간 확인"), StatFs로 직접 조회한다.
 * lib/data/storage/workspace.dart의 Workspace.freeSpaceBytes()가 이 채널을 호출한다.
 */
class MainActivity : FlutterActivity() {
    private val storageChannel = "com.kamanbi.pdf_daeri/storage"

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
                        val free = stat.availableBytes
                        result.success(free)
                    } catch (e: Exception) {
                        result.error("STATFS_FAILED", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }
}
