import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../crypto/crypto.dart';
import '../models/ephemeral_peer.dart';
import '../models/message_fragment.dart';
import 'ble_constants.dart';

/// Manages the complete BLE lifecycle for the Offline Mesh:
///
/// - Advertising this device's ephemeral UUID and public key
/// - Scanning for peer devices running the mesh service
/// - Performing ECDH key exchange via GATT read of peer public key
/// - Receiving encrypted fragments from peers
/// - Forwarding (blind-relaying) fragments to all other peers
///
/// ## Thread Safety
///
/// All operations are async and run on the Dart event loop.
/// Stream controllers are [broadcast] so multiple subscribers are safe.
///
/// ## Memory Model
///
/// - [_connectedPeers] is an in-RAM map — never written to storage.
/// - Peer entries are removed on disconnect; their [EphemeralPeer.destroy()]
///   zeroes the session key.
/// - [_seenFragmentIds] is a bounded LRU-like set used for dedup.
class BleManager {
  final EcdhManager _ecdhManager;

  // --------------------------------------------------------------------------
  // Internal state (all RAM-only)
  // --------------------------------------------------------------------------

  /// Currently connected peers: deviceId → EphemeralPeer
  final Map<String, EphemeralPeer> _connectedPeers = {};

  /// Seen fragment IDs for flood-relay deduplication (bounded)
  final Set<String> _seenFragmentIds = {};

  /// Stream of incoming fragments this device can decrypt (for UI display)
  final StreamController<MessageFragment> _inboundController =
      StreamController<MessageFragment>.broadcast();

  /// Stream of peer connection events (for UI peers screen)
  final StreamController<List<EphemeralPeer>> _peersController =
      StreamController<List<EphemeralPeer>>.broadcast();

  StreamSubscription<List<ScanResult>>? _scanSubscription;
  StreamSubscription<BluetoothAdapterState>? _adapterSubscription;

  bool _isScanning = false;
  bool _isAdvertising = false;
  bool _disposed = false;

  final _random = Random.secure();

  // --------------------------------------------------------------------------
  // CONSTRUCTION
  // --------------------------------------------------------------------------

  BleManager({
    required EcdhManager ecdhManager,
    required FragmentService fragmentService,
  })  : _ecdhManager = ecdhManager;

  // --------------------------------------------------------------------------
  // PUBLIC STREAMS
  // --------------------------------------------------------------------------

  /// Emits fragments that this device successfully decrypted.
  Stream<MessageFragment> get inboundFragments => _inboundController.stream;

  /// Emits the current peer list whenever it changes.
  Stream<List<EphemeralPeer>> get peerUpdates => _peersController.stream;

  /// Current snapshot of connected peers.
  List<EphemeralPeer> get connectedPeers =>
      List.unmodifiable(_connectedPeers.values);

  // --------------------------------------------------------------------------
  // BLE ADAPTER READINESS
  // --------------------------------------------------------------------------

  /// Returns [true] if the Bluetooth adapter is powered on.
  Future<bool> get isBluetoothOn async {
    final state = await FlutterBluePlus.adapterState.first;
    return state == BluetoothAdapterState.on;
  }

  /// Monitor adapter state changes (e.g., user disabling Bluetooth).
  void listenToAdapterState(void Function(BluetoothAdapterState) onState) {
    _adapterSubscription?.cancel();
    _adapterSubscription =
        FlutterBluePlus.adapterState.listen(onState);
  }

  // --------------------------------------------------------------------------
  // SCANNING (CENTRAL ROLE)
  // --------------------------------------------------------------------------

  /// Start scanning for nearby mesh peers.
  ///
  /// Filters by [BleConstants.meshServiceUuid] to ignore non-mesh devices.
  /// Each discovered device triggers GATT connection and key exchange.
  Future<void> startScanning() async {
    if (_isScanning || _disposed) return;
    _isScanning = true;

    await FlutterBluePlus.startScan(
      withServices: [Guid(BleConstants.meshServiceUuid)],
      timeout: const Duration(milliseconds: BleConstants.scanTimeoutMs),
      continuousUpdates: true,
    );

    _scanSubscription = FlutterBluePlus.scanResults.listen(
      _onScanResults,
      onError: (_) {},
    );
  }

  /// Stop scanning.
  Future<void> stopScanning() async {
    _isScanning = false;
    await _scanSubscription?.cancel();
    _scanSubscription = null;
    await FlutterBluePlus.stopScan();
  }

  void _onScanResults(List<ScanResult> results) {
    for (final result in results) {
      final deviceId = result.device.remoteId.str;

      // Skip if already connected
      if (_connectedPeers.containsKey(deviceId)) continue;

      // Extract advertised local name
      final localName = result.advertisementData.advName;
      if (!localName.startsWith(BleConstants.advertisementPrefix)) continue;

      // Async connect without blocking scan loop
      _connectAndExchangeKeys(result.device, result.rssi).ignore();
    }
  }

  // --------------------------------------------------------------------------
  // GATT CONNECTION & KEY EXCHANGE
  // --------------------------------------------------------------------------

  Future<void> _connectAndExchangeKeys(
    BluetoothDevice device,
    int rssi,
  ) async {
    if (_disposed) return;
    if (_connectedPeers.length >= BleConstants.maxConcurrentConnections) return;

    try {
      await device.connect(
        timeout: const Duration(
            milliseconds: BleConstants.connectionTimeoutMs),
        autoConnect: false,
      );

      // Request larger MTU for fragment payloads
      if (device.platformName.isNotEmpty) {
        await device.requestMtu(BleConstants.preferredMtu);
      }

      // Discover services
      final services = await device.discoverServices();
      final meshService = services.firstWhere(
        (s) => s.serviceUuid == Guid(BleConstants.meshServiceUuid),
        orElse: () => throw Exception('Mesh service not found'),
      );

      // Read peer's public key from the dedicated characteristic
      final pubKeyChar = meshService.characteristics.firstWhere(
        (c) => c.characteristicUuid == Guid(BleConstants.pubKeyReadCharUuid),
        orElse: () => throw Exception('PubKey characteristic not found'),
      );

      final pubKeyBytes = Uint8List.fromList(await pubKeyChar.read());

      if (pubKeyBytes.length != 32) {
        await device.disconnect();
        return;
      }

      // Derive session key via ECDH
      final sessionKey = await _ecdhManager.deriveSessionKey(
        remotePublicKeyBytes: pubKeyBytes,
      );

      final peer = EphemeralPeer(
        deviceUuid: device.remoteId.str,
        ecdhPublicKey: pubKeyBytes,
        rssi: rssi,
        discoveredAt: DateTime.now(),
        sessionKey: Uint8List.fromList(await sessionKey.extractBytes()),
      );

      _connectedPeers[device.remoteId.str] = peer;
      _emitPeerUpdate();

      // Subscribe to fragment notifications from this peer
      final notifyChar = meshService.characteristics.firstWhere(
        (c) =>
            c.characteristicUuid ==
            Guid(BleConstants.fragmentNotifyCharUuid),
        orElse: () => throw Exception('Notify characteristic not found'),
      );

      await notifyChar.setNotifyValue(true);
      notifyChar.lastValueStream.listen(
        (bytes) =>
            _onFragmentReceived(Uint8List.fromList(bytes), fromPeer: peer),
        onDone: () => _onPeerDisconnected(device.remoteId.str),
        onError: (_) => _onPeerDisconnected(device.remoteId.str),
      );

      // Listen for disconnect
      device.connectionState.listen((state) {
        if (state == BluetoothConnectionState.disconnected) {
          _onPeerDisconnected(device.remoteId.str);
        }
      });
    } catch (_) {
      // Connection or key exchange failed — clean up silently
      _onPeerDisconnected(device.remoteId.str);
    }
  }

  // --------------------------------------------------------------------------
  // PERIPHERAL / ADVERTISING
  // --------------------------------------------------------------------------

  /// Begin advertising this device's mesh service.
  ///
  /// flutter_blue_plus does not support peripheral mode on all platforms.
  /// On Android 5+: native BLE advertising via BluetoothLeAdvertiser.
  /// On iOS: CoreBluetooth peripheral mode (requires entitlement).
  ///
  /// The [pubKeyBytes] are written to the [pubKeyReadCharUuid] characteristic
  /// so connecting peers can perform ECDH without additional handshake RTTs.
  Future<void> startAdvertising(Uint8List pubKeyBytes) async {
    if (_isAdvertising || _disposed) return;

    // NOTE: flutter_blue_plus >=1.28 does not expose peripheral/advertising
    // APIs directly in Dart. On Android, we use a MethodChannel to the
    // native BluetoothLeAdvertiser. On iOS, CBPeripheralManager is needed.
    //
    // For the MVP / hackathon, we use the platform channel stub below.
    // Full peripheral implementation is in:
    //   android/app/src/main/kotlin/.../BlePeripheralChannel.kt
    //   ios/Runner/BlePeripheralChannel.swift
    //
    // See `BlePeripheralBridge` class in this directory.
    _isAdvertising = true;
    // TODO (Prompt 5 native bridge): call platform channel
  }

  /// Update the advertised public key (called on each identity rotation).
  Future<void> updateAdvertisedPubKey(Uint8List newPubKeyBytes) async {
    if (!_isAdvertising) return;
    await startAdvertising(newPubKeyBytes);
  }

  /// Stop advertising.
  Future<void> stopAdvertising() async {
    _isAdvertising = false;
    // TODO (Prompt 5 native bridge): call platform channel
  }

  // --------------------------------------------------------------------------
  // FRAGMENT DISPATCH
  // --------------------------------------------------------------------------

  /// Send a fragment to all currently connected peers.
  Future<void> broadcastFragment(MessageFragment fragment) async {
    if (_disposed) return;
    final fragmentWithHop = fragment.withIncrementedHop();
    final packet = BlePacket(
      type: BlePacket.typeFragment,
      payload: Uint8List.fromList(
        utf8.encode(fragmentWithHop.toJsonString()),
      ),
    );
    final wireBytes = packet.toBytes();

    for (final peer in _connectedPeers.values) {
      _sendToPeer(peer, wireBytes).ignore();
    }
  }

  /// Send a fragment to a specific peer only.
  Future<void> sendFragmentToPeer({
    required MessageFragment fragment,
    required EphemeralPeer peer,
  }) async {
    if (_disposed) return;
    final packet = BlePacket(
      type: BlePacket.typeFragment,
      payload: Uint8List.fromList(
        utf8.encode(fragment.withIncrementedHop().toJsonString()),
      ),
    );
    await _sendToPeer(peer, packet.toBytes());
  }

  Future<void> _sendToPeer(EphemeralPeer peer, Uint8List bytes) async {
    try {
      final device = BluetoothDevice.fromId(peer.deviceUuid);
      final services = await device.discoverServices();
      final meshService = services.firstWhere(
        (s) => s.serviceUuid == Guid(BleConstants.meshServiceUuid),
        orElse: () => throw Exception('Service not found'),
      );
      final writeChar = meshService.characteristics.firstWhere(
        (c) =>
            c.characteristicUuid ==
            Guid(BleConstants.fragmentWriteCharUuid),
        orElse: () => throw Exception('Write characteristic not found'),
      );
      await writeChar.write(bytes, withoutResponse: true);
    } catch (_) {
      // Peer may have disconnected mid-send — tolerate silently
    }
  }

  // --------------------------------------------------------------------------
  // FRAGMENT RECEPTION & RELAY
  // --------------------------------------------------------------------------

  void _onFragmentReceived(Uint8List bytes, {required EphemeralPeer fromPeer}) {
    final packet = BlePacket.fromBytes(bytes);
    if (packet == null || packet.type != BlePacket.typeFragment) return;

    MessageFragment fragment;
    try {
      final json = utf8.decode(packet.payload);
      fragment = MessageFragment.fromJsonString(json);
    } catch (_) {
      return; // Malformed payload — drop
    }

    // Drop expired or over-hopped fragments
    if (fragment.isExpired) return;
    if (fragment.hopCount >= BleConstants.maxSeenFragmentIds) return;

    // Deduplication: drop if seen before
    final dedupeKey = '${fragment.fragmentSetId}_${fragment.index}';
    if (_seenFragmentIds.contains(dedupeKey)) return;

    // Bound the seen-set size
    if (_seenFragmentIds.length >= BleConstants.maxSeenFragmentIds) {
      _seenFragmentIds.remove(_seenFragmentIds.first);
    }
    _seenFragmentIds.add(dedupeKey);

    // Emit for local reassembly attempt (consumers will try their session keys)
    _inboundController.add(fragment);

    // Blind relay: forward to all peers EXCEPT the sender, after random jitter
    _relayFragmentWithJitter(fragment, excludePeer: fromPeer.deviceUuid);
  }

  void _relayFragmentWithJitter(
    MessageFragment fragment, {
    required String excludePeer,
  }) {
    final jitterMs = BleConstants.minRelayDelayMs +
        _random.nextInt(
          BleConstants.maxRelayDelayMs - BleConstants.minRelayDelayMs,
        );

    Future.delayed(Duration(milliseconds: jitterMs), () {
      if (_disposed) return;
      final fragmentWithHop = fragment.withIncrementedHop();
      final packet = BlePacket(
        type: BlePacket.typeFragment,
        payload: Uint8List.fromList(
          utf8.encode(fragmentWithHop.toJsonString()),
        ),
      );
      final wireBytes = packet.toBytes();

      for (final entry in _connectedPeers.entries) {
        if (entry.key == excludePeer) continue;
        _sendToPeer(entry.value, wireBytes).ignore();
      }
    });
  }

  // --------------------------------------------------------------------------
  // PEER LIFECYCLE
  // --------------------------------------------------------------------------

  void _onPeerDisconnected(String deviceId) {
    final peer = _connectedPeers.remove(deviceId);
    peer?.destroy(); // zeroes session key bytes
    _emitPeerUpdate();
  }

  void _emitPeerUpdate() {
    if (!_peersController.isClosed) {
      _peersController.add(List.unmodifiable(_connectedPeers.values));
    }
  }

  // --------------------------------------------------------------------------
  // TEARDOWN
  // --------------------------------------------------------------------------

  /// Disconnect all peers, stop scan/advertise, close streams.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;

    await stopScanning();
    await stopAdvertising();

    for (final peer in _connectedPeers.values) {
      peer.destroy();
      try {
        await BluetoothDevice.fromId(peer.deviceUuid).disconnect();
      } catch (_) {}
    }
    _connectedPeers.clear();
    _seenFragmentIds.clear();

    await _adapterSubscription?.cancel();
    await _inboundController.close();
    await _peersController.close();
  }
}
