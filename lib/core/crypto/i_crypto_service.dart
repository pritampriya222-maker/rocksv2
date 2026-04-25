import 'dart:typed_data';

/// Crypto service interface — implemented fully in Prompt 3.
/// 
/// Design principles:
/// - Every method is async (cryptography package is async)
/// - Private keys NEVER leave this class as return values
/// - Keys are zeroed via destroy() before GC
abstract class ICryptoService {
  /// Generate an ephemeral X25519 key pair.
  /// Returns (publicKey, privateKey) — private key stored only in RAM.
  Future<({Uint8List publicKey, Uint8List privateKey})> generateKeyPair();

  /// Perform ECDH to derive a shared 32-byte session key.
  /// Zeroes privateKey after derivation.
  Future<Uint8List> deriveSessionKey({
    required Uint8List localPrivateKey,
    required Uint8List peerPublicKey,
  });

  /// Encrypt plaintext with AES-256-GCM.
  /// Returns (ciphertext, nonce) — nonce is 12 random bytes.
  Future<({Uint8List ciphertext, Uint8List nonce})> encrypt({
    required Uint8List key,
    required Uint8List plaintext,
  });

  /// Decrypt ciphertext with AES-256-GCM.
  /// Throws if authentication tag is invalid.
  Future<Uint8List> decrypt({
    required Uint8List key,
    required Uint8List ciphertext,
    required Uint8List nonce,
  });

  /// Compute HMAC-SHA256 of data with key.
  Future<Uint8List> hmacSha256({
    required Uint8List key,
    required Uint8List data,
  });

  /// Verify HMAC-SHA256 tag. Returns false if invalid (constant-time).
  Future<bool> verifyHmac({
    required Uint8List key,
    required Uint8List data,
    required Uint8List expectedTag,
  });

  /// Cryptographically secure random bytes.
  Uint8List randomBytes(int length);
}
