package com.aura.word

import android.content.Intent
import android.net.Uri
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.EventChannel
import java.io.File
import java.io.FileOutputStream

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.aura.word/file_handler"
    private var pendingFilePath: String? = null
    private var eventSink: EventChannel.EventSink? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        // Method Channel for getting initial shared file
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getInitialSharedFile" -> {
                    val filePath = handleIntent(intent)
                    result.success(filePath)
                    // Clear after sending
                    pendingFilePath = null
                }
                else -> result.notImplemented()
            }
        }
        
        // Event Channel for streaming new file shares while app is running
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, "$CHANNEL/events").setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    eventSink = events
                    // Send pending file if any
                    pendingFilePath?.let {
                        events?.success(it)
                        pendingFilePath = null
                    }
                }
                override fun onCancel(arguments: Any?) {
                    eventSink = null
                }
            }
        )
        
        // Handle initial intent
        handleIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val filePath = handleIntent(intent)
        if (filePath != null) {
            eventSink?.success(filePath) ?: run { pendingFilePath = filePath }
        }
    }

    private fun handleIntent(intent: Intent?): String? {
        if (intent == null) return null
        
        val action = intent.action
        val type = intent.type
        
        if (Intent.ACTION_VIEW == action || Intent.ACTION_SEND == action) {
            val uri: Uri? = when {
                Intent.ACTION_VIEW == action -> intent.data
                else -> intent.getParcelableExtra(Intent.EXTRA_STREAM)
            }
            
            if (uri != null) {
                return copyUriToTempFile(uri)
            }
        }
        return null
    }
    
    private fun copyUriToTempFile(uri: Uri): String? {
        return try {
            val inputStream = contentResolver.openInputStream(uri)
            val tempFile = File(cacheDir, "shared_backup_${System.currentTimeMillis()}.wcc")
            val outputStream = FileOutputStream(tempFile)
            
            inputStream?.use { input ->
                outputStream.use { output ->
                    input.copyTo(output)
                }
            }
            
            tempFile.absolutePath
        } catch (e: Exception) {
            e.printStackTrace()
            null
        }
    }
}
