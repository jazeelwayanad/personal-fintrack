package com.jazeelwayanad.fintrack

import android.content.Intent
import android.net.Uri
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "fintrack/external_links").setMethodCallHandler { call, result ->
            if (call.method == "version") {
                result.success(packageManager.getPackageInfo(packageName, 0).versionName)
            } else if (call.method != "open") {
                result.notImplemented()
            } else {
                val url = call.arguments as? String
                val release = url?.matches(Regex("https://github\\.com/jazeelwayanad/personal-fintrack/releases/download/v([0-9]+\\.[0-9]+\\.[0-9]+)/FinTrack-\\1\\.apk")) == true
                if (url == null || !(release || url == "https://eucodes.in/" || url.startsWith("mailto:info@eucodes.in?subject="))) {
                    result.error("INVALID_URL", "Unsupported destination", null)
                } else {
                    try {
                        val action = if (url.startsWith("mailto:")) Intent.ACTION_SENDTO else Intent.ACTION_VIEW
                        startActivity(Intent(action, Uri.parse(url)))
                        result.success(null)
                    } catch (error: android.content.ActivityNotFoundException) {
                        result.error("NO_HANDLER", "No application available", null)
                    }
                }
            }
        }
    }
}
