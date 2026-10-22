package com.shapnest.shapnest_app

import android.content.Intent
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.shapnest.shapnest_app/foreground_service"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "startService" -> {
                    val title = call.argument<String>("title") ?: "SHAPNEST Active Protection"
                    val text = call.argument<String>("text") ?: "Real-time safety monitoring active."
                    val serviceIntent = Intent(this, ShapnestForegroundService::class.java).apply {
                        action = ShapnestForegroundService.ACTION_START
                        putExtra(ShapnestForegroundService.EXTRA_TITLE, title)
                        putExtra(ShapnestForegroundService.EXTRA_TEXT, text)
                    }
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        startForegroundService(serviceIntent)
                    } else {
                        startService(serviceIntent)
                    }
                    result.success(true)
                }
                "stopService" -> {
                    val serviceIntent = Intent(this, ShapnestForegroundService::class.java).apply {
                        action = ShapnestForegroundService.ACTION_STOP
                    }
                    startService(serviceIntent)
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    @Deprecated("Deprecated in Java")
    override fun onBackPressed() {
        // Move app to background instead of destroying Activity so BLE monitoring continues seamlessly
        moveTaskToBack(true)
    }
}
