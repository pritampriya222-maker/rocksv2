import 'dart:typed_data';

/// Represents a discovered BLE peer during a session.
/// Ephemeral — destroyed when session ends or UUID rotates.
class EphemeralPeer {
  /// Random UUID advertised by peer (rotates every 30 seconds)
  final String deviceUuid;

  /// Peer's ephemeral X25519 public key (from BLE advertisement)
  final Uint8List ecdhPublicKey;

  /// Derived shared session key (ECDH output) — never persisted
  Uint8List? sessionKey;

  /// BLE signal strength — used for proximity estimation
  final int rssi;

  /// When this peer was discovered
  final DateTime discoveredAt;

  /// Peer is trusted if ECDH key exchange succeeded
  bool get isKeyExchangeComplete => sessionKey != null;

  /// Peer expires when UUID rotates (30 seconds)
  bool get isStale =>
      DateTime.now().difference(discoveredAt).inSeconds > 30;

  EphemeralPeer({
    required this.deviceUuid,
    required this.ecdhPublicKey,
    required this.rssi,
    required this.discoveredAt,
    this.sessionKey,
  });

  /// Zero out session key from memory before garbage collection
  void destroy() {
    if (sessionKey != null) {
      for (int i = 0; i < sessionKey!.length; i++) {
        sessionKey![i] = 0;
      }
      sessionKey = null;
    }
  }

  @override
  String toString() => 'Peer[$deviceUuid RSSI:$rssi]';
}
