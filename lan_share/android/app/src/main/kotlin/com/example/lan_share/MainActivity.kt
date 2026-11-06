package com.example.lan_share

import android.app.DownloadManager
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.net.wifi.WifiNetworkSpecifier
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream
import java.net.URLConnection

/**
 * Native helpers for the phone app: join the laptop's hotspot, save into Downloads,
 * and open the Downloads folder. Everything else lives in Dart.
 */
class MainActivity : FlutterActivity() {
    private var callback: ConnectivityManager.NetworkCallback? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "lanshare/native")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "joinWifi" -> joinWifi(
                        call.argument<String>("ssid") ?: "",
                        call.argument<String>("pass") ?: "",
                        result,
                    )
                    "leaveWifi" -> {
                        leaveWifi()
                        result.success(null)
                    }
                    "saveToDownloads" -> saveToDownloads(
                        call.argument<String>("path") ?: "",
                        call.argument<String>("name") ?: "file",
                        result,
                    )
                    "openDownloads" -> {
                        openDownloads()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    /** Joins the hotspot (Android 10+; the system asks the user once) and routes this app over it. */
    private fun joinWifi(ssid: String, pass: String, result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            result.success(false)
            return
        }
        leaveWifi()
        val cm = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        val specifier = WifiNetworkSpecifier.Builder()
            .setSsid(ssid)
            .setWpa2Passphrase(pass)
            .build()
        val request = NetworkRequest.Builder()
            .addTransportType(NetworkCapabilities.TRANSPORT_WIFI)
            .removeCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
            .setNetworkSpecifier(specifier)
            .build()
        var replied = false
        fun reply(ok: Boolean) {
            if (replied) return
            replied = true
            runOnUiThread { result.success(ok) }
        }
        val cb = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) {
                cm.bindProcessToNetwork(network)
                reply(true)
            }

            override fun onUnavailable() = reply(false)
        }
        callback = cb
        try {
            cm.requestNetwork(request, cb, 30_000)
        } catch (e: Exception) {
            reply(false)
        }
    }

    private fun leaveWifi() {
        val cm = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        try {
            cm.bindProcessToNetwork(null)
            callback?.let { cm.unregisterNetworkCallback(it) }
        } catch (_: Exception) {
            // already released
        }
        callback = null
    }

    /** Copies a downloaded file into the public Downloads folder, under "LAN Share". */
    private fun saveToDownloads(path: String, name: String, result: MethodChannel.Result) {
        Thread {
            try {
                val mime = URLConnection.guessContentTypeFromName(name) ?: "application/octet-stream"
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    val values = ContentValues().apply {
                        put(MediaStore.Downloads.DISPLAY_NAME, name)
                        put(MediaStore.Downloads.MIME_TYPE, mime)
                        put(MediaStore.Downloads.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS + "/LAN Share")
                        put(MediaStore.Downloads.IS_PENDING, 1)
                    }
                    val uri = contentResolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
                        ?: throw IllegalStateException("no uri")
                    contentResolver.openOutputStream(uri)!!.use { out ->
                        FileInputStream(path).use { it.copyTo(out) }
                    }
                    values.clear()
                    values.put(MediaStore.Downloads.IS_PENDING, 0)
                    contentResolver.update(uri, values, null, null)
                } else {
                    val dir = File(
                        Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS),
                        "LAN Share",
                    )
                    dir.mkdirs()
                    FileInputStream(path).use { input ->
                        File(dir, name).outputStream().use { input.copyTo(it) }
                    }
                }
                runOnUiThread { result.success(null) }
            } catch (e: Exception) {
                runOnUiThread { result.error("save", e.message, null) }
            }
        }.start()
    }

    private fun openDownloads() {
        try {
            startActivity(Intent(DownloadManager.ACTION_VIEW_DOWNLOADS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        } catch (_: Exception) {
            // no Downloads app: nothing to open
        }
    }
}
