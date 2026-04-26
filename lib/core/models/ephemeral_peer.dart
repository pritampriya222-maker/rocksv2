import 'dart:typed_data';

/// Represents a discovered mesh peer during a session.
/// Ephemeral — destroyed when session ends or wiped.
class EphemeralPeer {
  final String deviceUuid;
  final Uint8List ecdhPublicKey;
  final Uint8List? sessionKey;
  final int rssi;
  final String? ipAddress;
  final DateTime discoveredAt;

  bool get isKeyExchangeComplete => sessionKey != null && sessionKey!.isNotEmpty;

  EphemeralPeer({
    required this.deviceUuid,
    required this.ecdhPublicKey,
    required this.rssi,
    required this.discoveredAt,
    this.ipAddress,
    this.sessionKey,
  });

  EphemeralPeer copyWith({
    String? deviceUuid,
    Uint8List? ecdhPublicKey,
    Uint8List? sessionKey,
    int? rssi,
    String? ipAddress,
    DateTime? discoveredAt,
  }) {
    return EphemeralPeer(
      deviceUuid: deviceUuid ?? this.deviceUuid,
      ecdhPublicKey: ecdhPublicKey ?? this.ecdhPublicKey,
      sessionKey: sessionKey ?? this.sessionKey,
      rssi: rssi ?? this.rssi,
      ipAddress: ipAddress ?? this.ipAddress,
      discoveredAt: discoveredAt ?? this.discoveredAt,
    );
  }

  /// Zero out session key from memory (best effort)
  void destroy() {
    if (sessionKey != null) {
      for (int i = 0; i < sessionKey!.length; i++) {
        sessionKey![i] = 0;
      }
    }
  }

  @override
  String toString() => 'Peer[$deviceUuid IP:$ipAddress]';
}
