package com.offline.mesh

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.net.wifi.WifiManager
import android.content.Context

class MainActivity : FlutterActivity() {
    private var multicastLock: WifiManager.MulticastLock? = null
    private var wifiLock: WifiManager.WifiLock? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        val wifi = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager

        try {
            // Acquire MulticastLock to allow discovery packets
            multicastLock = wifi.createMulticastLock("offlineMeshLock")
            multicastLock?.setReferenceCounted(true)
            multicastLock?.acquire()

            // Acquire WifiLock - wrap in try-catch as some devices restrict this
            wifiLock = wifi.createWifiLock(3, "offlineMeshWifiLock") // 3 = WIFI_MODE_FULL_HIGH_PERF
            wifiLock?.setReferenceCounted(true)
            wifiLock?.acquire()
        } catch (e: Exception) {
            // Fallback: Continue without locks if the OS restricts them
        }


        
        val channelName = "com.offline.mesh/anti_forensics"
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName).setMethodCallHandler { call, result ->
            if (call.method == "isMulticastLockActive") {
                result.success(multicastLock?.isHeld ?: false)
            } else {
                result.notImplemented()
            }
        }
    }

    override fun onDestroy() {
        multicastLock?.release()
        wifiLock?.release()
        super.onDestroy()
    }

}
