package de.iptasys.sleepdoctor

import android.content.ContentValues
import android.content.Intent
import android.provider.MediaStore
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity: FlutterActivity() {
    private val CHANNEL = "de.iptasys.sleepdoctor/ble_sync_service"
    private val LOG_CHANNEL = "de.iptasys.sleepdoctor/debug_log_saver"

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "startForegroundService" -> {
                    try {
                        val intent = Intent(this, BleSyncForegroundService::class.java).apply {
                            action = "START_FOREGROUND"
                        }
                        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
                            startForegroundService(intent)
                        } else {
                            startService(intent)
                        }
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("SERVICE_ERROR", "Failed to start foreground service: ${e.message}", null)
                    }
                }
                "stopForegroundService" -> {
                    try {
                        val intent = Intent(this, BleSyncForegroundService::class.java).apply {
                            action = "STOP_FOREGROUND"
                        }
                        stopService(intent)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("SERVICE_ERROR", "Failed to stop foreground service: ${e.message}", null)
                    }
                }
                "isServiceRunning" -> {
                    result.success(BleSyncForegroundService.isServiceRunning())
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
        
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, LOG_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "saveDebugLogs" -> {
                    try {
                        val sourcePath = call.argument<String>("sourcePath")
                        if (sourcePath == null) {
                            result.error("INVALID_ARGUMENT", "Source path is null", null)
                            return@setMethodCallHandler
                        }
                        
                        val sourceFile = File(sourcePath)
                        if (!sourceFile.exists()) {
                            result.error("FILE_NOT_FOUND", "Source file does not exist", null)
                            return@setMethodCallHandler
                        }
                        
                        val content = sourceFile.readText()
                        
                        val contentValues = ContentValues().apply {
                            put(MediaStore.Downloads.DISPLAY_NAME, "sleepdoctor_debug.txt")
                            put(MediaStore.Downloads.MIME_TYPE, "text/plain")
                            put(MediaStore.Downloads.RELATIVE_PATH, "Download/SleepDoctor")
                        }
                        
                        val resolver = contentResolver
                        val uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, contentValues)
                        
                        if (uri == null) {
                            result.error("INSERT_FAILED", "Failed to create file in MediaStore", null)
                            return@setMethodCallHandler
                        }
                        
                        resolver.openOutputStream(uri)?.use { outputStream ->
                            outputStream.write(content.toByteArray())
                            outputStream.flush()
                        }
                        
                        result.success("Downloads/SleepDoctor/sleepdoctor_debug.txt")
                    } catch (e: Exception) {
                        result.error("SAVE_ERROR", "Failed to save debug logs: ${e.message}", null)
                    }
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }
}
