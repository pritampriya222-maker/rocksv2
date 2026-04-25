package com.offline.mesh.ble

import android.bluetooth.*
import android.bluetooth.le.*
import android.content.Context
import android.os.ParcelUuid
import android.util.Base64
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.UUID

/**
 * Native Android BLE Peripheral channel.
 *
 * Registers a GATT server with three characteristics:
 *   1. PubKey READ   — 32-byte X25519 public key
 *   2. Fragment WRITE — incoming fragment from central peers
 *   3. Fragment NOTIFY — outbound fragments to connected centrals
 *
 * Handles advertising via BluetoothLeAdvertiser.
 *
 * Channel name: "com.offline.mesh/ble_peripheral"
 */
class BlePeripheralChannel(
    private val context: Context,
    private val channel: MethodChannel
) : MethodChannel.MethodCallHandler {

    companion object {
        const val SERVICE_UUID          = "12345678-1234-5678-1234-56789abcdef0"
        const val PUBKEY_READ_UUID      = "12345678-1234-5678-1234-56789abcdef2"
        const val FRAGMENT_WRITE_UUID   = "12345678-1234-5678-1234-56789abcdef1"
        const val FRAGMENT_NOTIFY_UUID  = "12345678-1234-5678-1234-56789abcdef3"
    }

    private var gattServer: BluetoothGattServer? = null
    private var advertiser: BluetoothLeAdvertiser? = null
    private var pubKeyBytes: ByteArray = ByteArray(32)
    private val connectedDevices = mutableSetOf<BluetoothDevice>()

    private val bluetoothManager: BluetoothManager by lazy {
        context.getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager
    }

    // -------------------------------------------------------------------------
    // MethodChannel handler
    // -------------------------------------------------------------------------

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "startAdvertising" -> {
                val pubKeyBase64 = call.argument<String>("pubKeyBase64") ?: ""
                val localName    = call.argument<String>("localName") ?: "OM_device"
                pubKeyBytes = Base64.decode(pubKeyBase64, Base64.DEFAULT)
                startGattServer()
                startAdvertising(localName)
                result.success(null)
            }
            "updatePubKey" -> {
                val pubKeyBase64 = call.argument<String>("pubKeyBase64") ?: ""
                pubKeyBytes = Base64.decode(pubKeyBase64, Base64.DEFAULT)
                updatePubKeyCharacteristic()
                result.success(null)
            }
            "stopAdvertising" -> {
                stopAdvertising()
                stopGattServer()
                result.success(null)
            }
            "notifyFragment" -> {
                val data = call.argument<ByteArray>("data") ?: return
                notifyAllCentrals(data)
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    // -------------------------------------------------------------------------
    // GATT SERVER
    // -------------------------------------------------------------------------

    private fun startGattServer() {
        val bluetoothAdapter = bluetoothManager.adapter ?: return

        val service = BluetoothGattService(
            UUID.fromString(SERVICE_UUID),
            BluetoothGattService.SERVICE_TYPE_PRIMARY
        )

        // PubKey READ characteristic
        val pubKeyChar = BluetoothGattCharacteristic(
            UUID.fromString(PUBKEY_READ_UUID),
            BluetoothGattCharacteristic.PROPERTY_READ,
            BluetoothGattCharacteristic.PERMISSION_READ
        )
        pubKeyChar.value = pubKeyBytes

        // Fragment WRITE characteristic
        val writeChar = BluetoothGattCharacteristic(
            UUID.fromString(FRAGMENT_WRITE_UUID),
            BluetoothGattCharacteristic.PROPERTY_WRITE or
                    BluetoothGattCharacteristic.PROPERTY_WRITE_NO_RESPONSE,
            BluetoothGattCharacteristic.PERMISSION_WRITE
        )

        // Fragment NOTIFY characteristic
        val notifyChar = BluetoothGattCharacteristic(
            UUID.fromString(FRAGMENT_NOTIFY_UUID),
            BluetoothGattCharacteristic.PROPERTY_NOTIFY,
            BluetoothGattCharacteristic.PERMISSION_READ
        )
        val descriptor = BluetoothGattDescriptor(
            UUID.fromString("00002902-0000-1000-8000-00805f9b34fb"), // CCCD
            BluetoothGattDescriptor.PERMISSION_WRITE or BluetoothGattDescriptor.PERMISSION_READ
        )
        notifyChar.addDescriptor(descriptor)

        service.addCharacteristic(pubKeyChar)
        service.addCharacteristic(writeChar)
        service.addCharacteristic(notifyChar)

        gattServer = bluetoothManager.openGattServer(context, gattServerCallback)
        gattServer?.addService(service)
    }

    private fun updatePubKeyCharacteristic() {
        val service = gattServer?.getService(UUID.fromString(SERVICE_UUID)) ?: return
        val char = service.getCharacteristic(UUID.fromString(PUBKEY_READ_UUID)) ?: return
        char.value = pubKeyBytes
    }

    private fun stopGattServer() {
        gattServer?.close()
        gattServer = null
        connectedDevices.clear()
    }

    // -------------------------------------------------------------------------
    // BLE ADVERTISING
    // -------------------------------------------------------------------------

    private fun startAdvertising(localName: String) {
        val bluetoothAdapter = bluetoothManager.adapter ?: return
        advertiser = bluetoothAdapter.bluetoothLeAdvertiser ?: return

        val settings = AdvertiseSettings.Builder()
            .setAdvertiseMode(AdvertiseSettings.ADVERTISE_MODE_BALANCED)
            .setTxPowerLevel(AdvertiseSettings.ADVERTISE_TX_POWER_MEDIUM)
            .setConnectable(true)
            .build()

        val data = AdvertiseData.Builder()
            .setIncludeDeviceName(true)
            .addServiceUuid(ParcelUuid(UUID.fromString(SERVICE_UUID)))
            .build()

        advertiser?.startAdvertising(settings, data, advertiseCallback)
    }

    private fun stopAdvertising() {
        advertiser?.stopAdvertising(advertiseCallback)
        advertiser = null
    }

    // -------------------------------------------------------------------------
    // NOTIFY connected centrals
    // -------------------------------------------------------------------------

    private fun notifyAllCentrals(data: ByteArray) {
        val service = gattServer?.getService(UUID.fromString(SERVICE_UUID)) ?: return
        val char = service.getCharacteristic(UUID.fromString(FRAGMENT_NOTIFY_UUID)) ?: return
        char.value = data
        for (device in connectedDevices) {
            gattServer?.notifyCharacteristicChanged(device, char, false)
        }
    }

    // -------------------------------------------------------------------------
    // GATT SERVER CALLBACKS
    // -------------------------------------------------------------------------

    private val gattServerCallback = object : BluetoothGattServerCallback() {
        override fun onConnectionStateChange(
            device: BluetoothDevice, status: Int, newState: Int
        ) {
            if (newState == BluetoothProfile.STATE_CONNECTED) {
                connectedDevices.add(device)
            } else {
                connectedDevices.remove(device)
            }
        }

        override fun onCharacteristicReadRequest(
            device: BluetoothDevice, requestId: Int, offset: Int,
            characteristic: BluetoothGattCharacteristic
        ) {
            if (characteristic.uuid == UUID.fromString(PUBKEY_READ_UUID)) {
                gattServer?.sendResponse(
                    device, requestId, BluetoothGatt.GATT_SUCCESS, offset,
                    pubKeyBytes.copyOfRange(offset, pubKeyBytes.size)
                )
            } else {
                gattServer?.sendResponse(
                    device, requestId, BluetoothGatt.GATT_FAILURE, 0, null
                )
            }
        }

        override fun onCharacteristicWriteRequest(
            device: BluetoothDevice, requestId: Int,
            characteristic: BluetoothGattCharacteristic,
            preparedWrite: Boolean, responseNeeded: Boolean,
            offset: Int, value: ByteArray
        ) {
            if (characteristic.uuid == UUID.fromString(FRAGMENT_WRITE_UUID)) {
                if (responseNeeded) {
                    gattServer?.sendResponse(
                        device, requestId, BluetoothGatt.GATT_SUCCESS, 0, null
                    )
                }
                // Forward to Dart layer
                channel.invokeMethod("onFragmentWritten", value)
            }
        }

        override fun onDescriptorWriteRequest(
            device: BluetoothDevice, requestId: Int,
            descriptor: BluetoothGattDescriptor,
            preparedWrite: Boolean, responseNeeded: Boolean,
            offset: Int, value: ByteArray
        ) {
            if (responseNeeded) {
                gattServer?.sendResponse(
                    device, requestId, BluetoothGatt.GATT_SUCCESS, 0, null
                )
            }
        }
    }

    // -------------------------------------------------------------------------
    // ADVERTISE CALLBACK
    // -------------------------------------------------------------------------

    private val advertiseCallback = object : AdvertiseCallback() {
        override fun onStartSuccess(settingsInEffect: AdvertiseSettings) {}
        override fun onStartFailure(errorCode: Int) {}
    }
}
