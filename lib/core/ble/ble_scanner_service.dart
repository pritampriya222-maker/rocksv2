import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'ble_constants.dart';

/// Manages Central mode (GATT Client) to discover and connect to peers.
class BleScannerService {
  final StreamController<List<BluetoothDevice>> _connectedPeersController =
      StreamController<List<BluetoothDevice>>.broadcast();

  final Map<String, BluetoothDevice> _connectedPeers = {};
  final Map<String, BluetoothCharacteristic> _writeCharacteristics = {};

  StreamSubscription<List<ScanResult>>? _scanSubscription;
  bool _isScanning = false;

  /// Reactive list of currently connected active peers.
  Stream<List<BluetoothDevice>> get connectedPeersStream =>
      _connectedPeersController.stream;

  List<BluetoothDevice> get currentPeers => _connectedPeers.values.toList();

  /// Scans specifically for our Mesh Service UUID.
  /// Automatically restarts if halted (with backoff to prevent battery drain).
  Future<void> startContinuousScan() async {
    if (_isScanning) return;
    _isScanning = true;

    try {
      final state = await FlutterBluePlus.adapterState.first;
      if (state != BluetoothAdapterState.on) {
        _isScanning = false;
        return; // Wait for Bluetooth to be enabled
      }

      _scanSubscription = FlutterBluePlus.scanResults.listen(
        (results) {
          for (final result in results) {
            final deviceId = result.device.remoteId.str;
            if (!_connectedPeers.containsKey(deviceId)) {
              // Async connect to avoid blocking the scan loop
              connectToPeer(result.device).ignore();
            }
          }
        },
        onError: (e) {
          // Graceful handling and backoff
          _handleScanErrorAndRestart();
        },
      );

      await FlutterBluePlus.startScan(
        withServices: [Guid(BleConstants.meshServiceUuid)],
        continuousUpdates: true,
      );
    } catch (e) {
      _handleScanErrorAndRestart();
    }
  }

  void _handleScanErrorAndRestart() {
    _isScanning = false;
    _scanSubscription?.cancel();
    
    // Backoff and restart logic to prevent battery drain during failure loops
    Future.delayed(const Duration(seconds: 5), () {
      if (!_isScanning) {
        startContinuousScan();
      }
    });
  }

  /// Stops the continuous scan gracefully.
  Future<void> stopScan() async {
    _isScanning = false;
    await _scanSubscription?.cancel();
    await FlutterBluePlus.stopScan();
  }

  /// Connects to a peer, negotiates MTU, and discovers services.
  Future<void> connectToPeer(BluetoothDevice device) async {
    final deviceId = device.remoteId.str;
    if (_connectedPeers.containsKey(deviceId)) return;

    try {
      // Connect with autoConnect: false to explicitly manage connection lifecycle
      await device.connect(autoConnect: false, timeout: const Duration(seconds: 10));

      // Instantly request MTU of 512 for large fragment payloads
      if (device.platformName.isNotEmpty) {
        await device.requestMtu(512);
      }

      // Discover services and locate the mesh write characteristic
      final services = await device.discoverServices();
      BluetoothService? meshService;
      
      for (final s in services) {
        if (s.serviceUuid == Guid(BleConstants.meshServiceUuid)) {
          meshService = s;
          break;
        }
      }

      if (meshService == null) {
        await device.disconnect();
        return;
      }

      BluetoothCharacteristic? writeChar;
      for (final c in meshService.characteristics) {
        if (c.characteristicUuid == Guid(BleConstants.fragmentWriteCharUuid)) {
          writeChar = c;
          break;
        }
      }

      if (writeChar == null) {
        await device.disconnect();
        return;
      }

      // Store the peer and its characteristic
      _writeCharacteristics[deviceId] = writeChar;
      _connectedPeers[deviceId] = device;
      _emitPeers();

      // Listen for unexpected disconnects (Graceful PlatformException handling)
      device.connectionState.listen((state) {
        if (state == BluetoothConnectionState.disconnected) {
          _removePeer(deviceId);
        }
      });

    } on PlatformException catch (_) {
      // Sudden disconnect or unauthorized exception
      _removePeer(deviceId);
    } catch (_) {
      // Any other connection failure
      _removePeer(deviceId);
    }
  }

  /// Writes data directly to a peer's characteristic.
  Future<void> writeToPeer(String deviceId, List<int> data) async {
    final char = _writeCharacteristics[deviceId];
    if (char != null) {
      try {
        await char.write(data, withoutResponse: true);
      } catch (_) {
        // Drop the packet quietly if write fails (e.g., peer moved out of range)
      }
    }
  }

  void _removePeer(String id) {
    _connectedPeers.remove(id);
    _writeCharacteristics.remove(id);
    _emitPeers();
  }

  void _emitPeers() {
    if (!_connectedPeersController.isClosed) {
      _connectedPeersController.add(_connectedPeers.values.toList());
    }
  }

  void dispose() {
    stopScan();
    _connectedPeersController.close();
    for (final peer in _connectedPeers.values) {
      peer.disconnect();
    }
    _connectedPeers.clear();
    _writeCharacteristics.clear();
  }
}
