package com.jazeelwayanad.fintrack

import android.content.Intent
import android.net.Uri
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val upiRequest = 8754
    private var upiResult: MethodChannel.Result? = null

    @Deprecated("Used for the UPI chooser result on FlutterActivity")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != upiRequest) return
        val callback = upiResult ?: return
        upiResult = null
        val status = data?.getStringExtra("response")
            ?.split("&")
            ?.mapNotNull { field ->
                val parts = field.split("=", limit = 2)
                if (parts.size == 2 && parts[0].equals("status", ignoreCase = true)) parts[1].lowercase() else null
            }
            ?.singleOrNull()
        callback.success(when (status) {
            "success" -> "success"
            "failure", "failed" -> "failed"
            "pending", "submitted" -> "pending"
            "cancel", "cancelled", "canceled" -> "cancelled"
            else -> if (resultCode == RESULT_CANCELED) "cancelled" else "unknown"
        })
    }

    @Suppress("DEPRECATION")
    private fun launchUpi(raw: String?, result: MethodChannel.Result) {
        val uri = raw?.let(Uri::parse)
        if (raw == null || uri == null || raw.length > 4096 || uri.scheme != "upi" || uri.encodedAuthority != "pay"
            || !uri.path.isNullOrEmpty() || uri.encodedFragment != null) {
            result.error("INVALID_UPI", "Invalid UPI payment details", null)
            return
        }
        if (upiResult != null) {
            result.error("PAYMENT_OPEN", "A UPI app is already open", null)
            return
        }
        val intent = Intent(Intent.ACTION_VIEW, uri)
        if (intent.resolveActivity(packageManager) == null) {
            result.success("launch_failed")
            return
        }
        try {
            upiResult = result
            startActivityForResult(Intent.createChooser(intent, "Pay with UPI"), upiRequest)
        } catch (error: android.content.ActivityNotFoundException) {
            upiResult = null
            result.success("launch_failed")
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "fintrack/upi").setMethodCallHandler { call, result ->
            if (call.method == "open") launchUpi(call.arguments as? String, result) else result.notImplemented()
        }
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
