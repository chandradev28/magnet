package com.magnet.app.magnet

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private var pendingLink: String? = null
    private var linkSink: EventChannel.EventSink? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        pendingLink = extractLink(intent)
        requestNotificationPermission()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger

        MethodChannel(messenger, CHANNEL_NATIVE).setMethodCallHandler { call, result ->
            when (call.method) {
                "getInitialLink" -> {
                    val link = pendingLink
                    pendingLink = null
                    result.success(link)
                }
                "startService" -> {
                    val title = call.argument<String>("title") ?: "magnet"
                    val body = call.argument<String>("body") ?: "Streaming"
                    StreamService.start(this, title, body)
                    result.success(true)
                }
                "stopService" -> {
                    StreamService.stop(this)
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }

        EventChannel(messenger, CHANNEL_LINKS).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    linkSink = events
                    val queued = pendingLink
                    if (queued != null) {
                        pendingLink = null
                        events?.success(queued)
                    }
                }

                override fun onCancel(arguments: Any?) {
                    linkSink = null
                }
            }
        )
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val link = extractLink(intent) ?: return
        val sink = linkSink
        if (sink != null) {
            sink.success(link)
        } else {
            pendingLink = link
        }
    }

    private fun requestNotificationPermission() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return
        val granted = checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED
        if (!granted) {
            requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 9110)
        }
    }

    /** Accepts both a magnet: VIEW intent and shared text that contains one. */
    private fun extractLink(intent: Intent?): String? {
        if (intent == null) return null
        val data = intent.data?.toString()
        if (data != null && data.startsWith("magnet:", ignoreCase = true)) {
            return data
        }
        val text = intent.getStringExtra(Intent.EXTRA_TEXT) ?: return null
        val index = text.indexOf("magnet:?", ignoreCase = true)
        if (index < 0) return null
        return text.substring(index).trim().split(Regex("\\s+"))[0]
    }

    private companion object {
        const val CHANNEL_NATIVE = "magnet/native"
        const val CHANNEL_LINKS = "magnet/links"
    }
}
