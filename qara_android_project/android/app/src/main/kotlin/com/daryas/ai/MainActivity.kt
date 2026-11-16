package com.daryas.ai

import android.content.Intent
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "qara/native"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "startWakeService" -> {
                        try {
                            val intent = Intent(this, QaraWakeService::class.java)
                                .setAction(QaraWakeService.ACTION_START)
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                                startForegroundService(intent)
                            } else {
                                startService(intent)
                            }
                            result.success(true)
                        } catch (error: Exception) {
                            result.error("WAKE_START_FAILED", error.message, null)
                        }
                    }
                    "stopWakeService" -> {
                        try {
                            stopService(Intent(this, QaraWakeService::class.java))
                            result.success(true)
                        } catch (error: Exception) {
                            result.error("WAKE_STOP_FAILED", error.message, null)
                        }
                    }
                    "isWakeServiceRunning" -> result.success(QaraWakeService.isRunning)
                    else -> result.notImplemented()
                }
            }
    }
}
