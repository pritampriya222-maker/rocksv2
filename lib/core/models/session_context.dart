import 'dart:typed_data';

/// Represents an outbound session for sending a message.
/// Destroyed immediately after all 3 fragments are sent.
class SessionContext {
  /// Random session ID (not linked to any device ID)
  final String sessionId;

  /// Sender's ephemeral X25519 private key — DESTROYED after send
  final Uint8List localPrivateKey;

  /// Sender's ephemeral X25519 public key — embedded in BLE advertisement
  final Uint8List localPublicKey;

  /// Session creation time — key material expires after 30 seconds
  final DateTime createdAt;

  SessionContext({
    required this.sessionId,
    required this.localPrivateKey,
    required this.localPublicKey,
  }) : createdAt = DateTime.now();

  bool get isExpired =>
      DateTime.now().difference(createdAt).inSeconds > 30;

  /// Cryptographically zero all key material
  void destroy() {
    for (int i = 0; i < localPrivateKey.length; i++) {
      localPrivateKey[i] = 0;
    }
    for (int i = 0; i < localPublicKey.length; i++) {
      localPublicKey[i] = 0;
    }
  }
}
