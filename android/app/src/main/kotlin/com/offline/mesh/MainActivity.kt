package com.offline.mesh

import com.offline.mesh.ble.BlePeripheralChannel
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private val channelName = "com.offline.mesh/ble_peripheral"
    private var blePeripheralChannel: BlePeripheralChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        val methodChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            channelName
        )

        blePeripheralChannel = BlePeripheralChannel(
            context = applicationContext,
            channel = methodChannel
        )

        methodChannel.setMethodCallHandler(blePeripheralChannel)
    }

    override fun onDestroy() {
        super.onDestroy()
        blePeripheralChannel = null
    }
}
