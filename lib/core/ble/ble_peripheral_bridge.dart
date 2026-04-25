import 'dart:async';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'ble_constants.dart';

/// Native platform bridge for BLE Peripheral (advertising) mode.
///
/// flutter_blue_plus does not expose BLE advertising (peripheral role) in
/// its Dart API. This class provides a thin MethodChannel wrapper to the
/// native implementations:
///
///   Android: android/app/src/main/kotlin/.../BlePeripheralChannel.kt
///   iOS:     ios/Runner/BlePeripheralChannel.swift
///
/// ## GATT Server Structure (advertised by this device)
///
/// Service UUID: [BleConstants.meshServiceUuid]
///   ├── Char [pubKeyReadCharUuid]      READ       — returns 32-byte pubkey
///   ├── Char [fragmentWriteCharUuid]   WRITE      — accepts fragment packets
///   └── Char [fragmentNotifyCharUuid]  NOTIFY     — pushes fragments to subs
///
/// The ephemeral public key is updated every 30 seconds via [updatePubKey()].
/// Connecting peers read it once for ECDH key exchange.
class BlePeripheralBridge {
  static const _channel = MethodChannel('com.offline.mesh/ble_peripheral');

  /// Callback invoked when a remote central writes a fragment to this device.
  void Function(Uint8List bytes)? onFragmentWritten;

  // --------------------------------------------------------------------------
  // ADVERTISING CONTROL
  // --------------------------------------------------------------------------

  /// Start GATT server + BLE advertisement.
  ///
  /// [pubKeyBytes] — 32-byte X25519 public key embedded in GATT characteristic.
  /// [ephemeralUuid] — short device identifier in the LOCAL NAME field.
  Future<void> startAdvertising({
    required Uint8List pubKeyBytes,
    required String ephemeralUuid,
  }) async {
    await _channel.invokeMethod<void>('startAdvertising', {
      'serviceUuid': BleConstants.meshServiceUuid,
      'pubKeyBase64': base64.encode(pubKeyBytes),
      'localName':
          '${BleConstants.advertisementPrefix}${ephemeralUuid.substring(0, 8)}',
    });

    // Set up write handler from native side
    _channel.setMethodCallHandler(_handleNativeCall);
  }

  /// Update the public key characteristic value (called on rotation).
  Future<void> updatePubKey(Uint8List newPubKeyBytes) async {
    await _channel.invokeMethod<void>('updatePubKey', {
      'pubKeyBase64': base64.encode(newPubKeyBytes),
    });
  }

  /// Stop advertising and tear down the GATT server.
  Future<void> stopAdvertising() async {
    _channel.setMethodCallHandler(null);
    await _channel.invokeMethod<void>('stopAdvertising');
  }

  // --------------------------------------------------------------------------
  // NOTIFY outbound fragment to connected centrals
  // --------------------------------------------------------------------------

  /// Push a fragment to all connected centrals via NOTIFY characteristic.
  Future<void> notifyFragment(Uint8List wireBytes) async {
    await _channel.invokeMethod<void>('notifyFragment', {
      'data': wireBytes,
    });
  }

  // --------------------------------------------------------------------------
  // NATIVE CALL HANDLER
  // --------------------------------------------------------------------------

  Future<dynamic> _handleNativeCall(MethodCall call) async {
    if (call.method == 'onFragmentWritten') {
      final bytes = call.arguments as Uint8List;
      onFragmentWritten?.call(bytes);
    }
    return null;
  }
}
