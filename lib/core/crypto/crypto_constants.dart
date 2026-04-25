/// Cryptographic constants for the Offline Mesh system.
///
/// All time values are in milliseconds unless noted.
/// All length values are in bytes unless noted.
/// No magic numbers are permitted in any other crypto file.
class CryptoConstants {
  CryptoConstants._(); // prevent instantiation

  // --------------------------------------------------------------------------
  // ECDH / Key Agreement
  // --------------------------------------------------------------------------

  /// X25519 public key length (always 32 bytes per RFC 7748)
  static const int x25519PublicKeyLength = 32;

  /// X25519 private key length (always 32 bytes per RFC 7748)
  static const int x25519PrivateKeyLength = 32;

  /// Derived session key length (256 bits = 32 bytes, for AES-256)
  static const int sessionKeyLength = 32;

  // --------------------------------------------------------------------------
  // AES-256-GCM
  // --------------------------------------------------------------------------

  /// AES-GCM nonce length (96 bits = 12 bytes, per RFC 5288 / NIST SP 800-38D)
  static const int aesGcmNonceLength = 12;

  /// AES-GCM authentication tag length (128 bits = 16 bytes)
  static const int aesGcmTagLength = 16;

  /// AES key length (256 bits = 32 bytes)
  static const int aesKeyLength = 32;

  // --------------------------------------------------------------------------
  // Fragmentation
  // --------------------------------------------------------------------------

  /// Total number of independent fragments per message
  static const int fragmentCount = 3;

  /// Fragment index A (first, 40% of plaintext length)
  static const int fragmentIndexA = 0;

  /// Fragment index B (second, 30% of plaintext length)
  static const int fragmentIndexB = 1;

  /// Fragment index C (third, remaining 30% of plaintext length)
  static const int fragmentIndexC = 2;

  /// Byte split boundary A: first 40% of plaintext
  static const double fragmentSplitA = 0.40;

  /// Byte split boundary B: next 30% of plaintext (cumulative 70%)
  static const double fragmentSplitB = 0.30;

  // fragmentSplitC is the remainder (30%) — no constant needed

  // --------------------------------------------------------------------------
  // TTL & Timing
  // --------------------------------------------------------------------------

  /// Ephemeral UUID + keypair rotation interval in milliseconds (30 seconds)
  static const int ephemeralRotationMs = 30000;

  /// Session key TTL after peer disconnection in milliseconds (30 seconds)
  static const int sessionKeyTtlMs = 30000;

  /// Session cleanup scan interval in milliseconds (10 seconds)
  static const int sessionCleanupIntervalMs = 10000;

  /// Fragment relay TTL in milliseconds (5 minutes)
  static const int fragmentTtlMs = 300000;

  /// Maximum random flood-relay jitter in milliseconds (5 seconds)
  static const int maxRelayJitterMs = 5000;

  // --------------------------------------------------------------------------
  // Hashing & MAC
  // --------------------------------------------------------------------------

  /// SHA-256 output length (32 bytes)
  static const int sha256Length = 32;

  /// HMAC-SHA256 output length (32 bytes)
  static const int hmacSha256Length = 32;

  /// Fragment set ID: first N bytes of the HMAC over session nonce
  static const int fragmentIdLength = 16;

  /// Peer fingerprint byte width (first 8 bytes of pubkey used as map key)
  static const int peerFingerprintBytes = 8;

  // --------------------------------------------------------------------------
  // Wire / Encoding
  // --------------------------------------------------------------------------

  /// Minimum SecretBox wire size: nonce + at-least-one-byte ciphertext + tag
  static const int minSecretBoxWireLength =
      aesGcmNonceLength + 1 + aesGcmTagLength;

  /// Fragment hop count ceiling — drop fragments exceeding this
  static const int maxHopCount = 10;
}
