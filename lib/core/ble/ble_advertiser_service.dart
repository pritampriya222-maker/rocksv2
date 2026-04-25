import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'ble_peripheral_bridge.dart';

/// Manages Peripheral mode (GATT Server) to broadcast presence and receive data.
/// 
/// Note: Since `flutter_blue_plus` acts strictly as a Central (Client), 
/// this service delegates the Peripheral (Server) responsibilities to our 
/// native `BlePeripheralBridge` while fulfilling the architectural interface.
class BleAdvertiserService {
  final BlePeripheralBridge _bridge = BlePeripheralBridge();
  
  final StreamController<List<int>> _onFragmentReceived = StreamController<List<int>>.broadcast();
  
  /// Stream yielding raw bytes whenever another device writes to our characteristic.
  Stream<List<int>> get onFragmentReceived => _onFragmentReceived.stream;

  bool _isAdvertising = false;

  /// Sets up the GATT server.
  /// Exposes a single write-without-response Characteristic for incoming fragments.
  Future<void> setupGattServer() async {
    // The actual GATT server setup is handled natively via the bridge.
    // We bind the native callback to our Dart stream here.
    _bridge.onFragmentWritten = (Uint8List bytes) {
      _onFragmentReceived.add(bytes);
    };
  }

  /// Starts broadcasting the Mesh Service UUID.
  /// Embeds the ephemeral identity and X25519 public key in the advertisement payload.
  Future<void> startAdvertising(String ephemeralUuid, List<int> publicKey) async {
    if (_isAdvertising) return;

    try {
      // Ensure Bluetooth is on before advertising
      final state = await FlutterBluePlus.adapterState.first;
      if (state != BluetoothAdapterState.on) {
        throw Exception('Bluetooth adapter is not powered on.');
      }

      await _bridge.startAdvertising(
        ephemeralUuid: ephemeralUuid,
        pubKeyBytes: Uint8List.fromList(publicKey),
      );
      _isAdvertising = true;
    } on PlatformException catch (e) {
      // Rigorous error handling for BLE state issues
      throw Exception('Failed to start advertising. Ensure permissions are granted: ${e.message}');
    } catch (e) {
      throw Exception('Unknown error while starting advertising: $e');
    }
  }

  /// Stops advertising and shuts down the GATT server.
  Future<void> stopAdvertising() async {
    if (!_isAdvertising) return;
    try {
      await _bridge.stopAdvertising();
      _isAdvertising = false;
    } catch (e) {
      throw Exception('Failed to stop advertising: $e');
    }
  }

  void dispose() {
    _onFragmentReceived.close();
    stopAdvertising();
  }
}
