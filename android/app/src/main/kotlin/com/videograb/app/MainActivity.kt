package com.videograb.app

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private var bridge: DownloadBridge? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        val channel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.videograb/engine"
        )
        val downloadBridge = DownloadBridge(applicationContext, channel)
        bridge = downloadBridge
        channel.setMethodCallHandler { call, result ->
            downloadBridge.handle(call, result)
        }
    }
}
