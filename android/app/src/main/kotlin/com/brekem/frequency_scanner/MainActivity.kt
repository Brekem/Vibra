package com.brekem.frequency_scanner

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val toneGenerator = ToneGenerator()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
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
    }

    override fun onDestroy() {
        toneGenerator.stop()
        super.onDestroy()
    }

    companion object {
        private const val CHANNEL = "com.brekem.frequency_scanner/tone"
    }
}
