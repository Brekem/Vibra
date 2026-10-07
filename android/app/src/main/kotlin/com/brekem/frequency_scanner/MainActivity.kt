package com.brekem.frequency_scanner

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val toneGenerator = ToneGenerator()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger

        MethodChannel(messenger, TONE_CHANNEL).setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "start" -> {
                        toneGenerator.start(
                            call.argument<Double>("frequency") ?: 440.0,
                            call.argument<Double>("amplitude") ?: 0.1,
                        )
                        result.success(null)
                    }
                    "update" -> {
                        toneGenerator.update(
                            call.argument<Double>("frequency") ?: 440.0,
                            call.argument<Double>("amplitude") ?: 0.1,
                        )
                        result.success(null)
                    }
                    "stop" -> {
                        toneGenerator.stop()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            } catch (e: Exception) {
                result.error("TONE_ERROR", e.message, null)
            }
        }

        val systemChannel = MethodChannel(messenger, SYSTEM_CHANNEL)
        ScannerService.stopListener = { systemChannel.invokeMethod("stopRequested", null) }
        systemChannel.setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "keepScreenOn" -> {
                        if (call.argument<Boolean>("on") == true) {
                            window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                        } else {
                            window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                        }
                        result.success(null)
                    }
                    "startService" -> {
                        requestNotificationPermission()
                        ScannerService.start(this, call.argument<String>("text") ?: "")
                        result.success(null)
                    }
                    "updateService" -> {
                        ScannerService.update(this, call.argument<String>("text") ?: "")
                        result.success(null)
                    }
                    "stopService" -> {
                        ScannerService.stop(this)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            } catch (e: Exception) {
                result.error("SYSTEM_ERROR", e.message, null)
            }
        }
    }

    private fun requestNotificationPermission() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) {
            requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), NOTIFICATION_REQUEST)
        }
    }

    override fun onDestroy() {
        ScannerService.stopListener = null
        toneGenerator.stop()
        ScannerService.stop(this)
        super.onDestroy()
    }

    companion object {
        private const val TONE_CHANNEL = "com.brekem.frequency_scanner/tone"
        private const val SYSTEM_CHANNEL = "com.brekem.frequency_scanner/system"
        private const val NOTIFICATION_REQUEST = 2001
    }
}
