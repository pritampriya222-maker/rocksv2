import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'secure_memory.dart';

/// HMAC-SHA256 utilities for fragment authentication.
///
/// ## What the MAC covers
///
/// The MAC input is constructed as:
/// ```
/// seq(4 bytes big-endian) || ciphertext || ttl(8 bytes big-endian)
/// ```
///
/// Binding the sequence number prevents a replay attack where an adversary
/// reorders fragments. Binding the TTL timestamp prevents replaying expired
/// fragments after the session ends.
///
/// ## Verification strategy
///
/// [verifyFragmentMac] re-computes the expected MAC and compares it byte-by-byte
/// using [SecureMemory.constantTimeEquals] to prevent timing-based oracle attacks.
/// Even if the computed MAC is wrong on byte 0, all 32 bytes are compared before
/// returning [false].
class HmacUtil {
  final Hmac _hmac = Hmac.sha256();

  // --------------------------------------------------------------------------
  // COMPUTE
  // --------------------------------------------------------------------------

  /// Compute HMAC-SHA256 over a fragment's ciphertext, bound to [sequenceNumber]
  /// and [ttlMs] (TTL expiration in milliseconds since epoch).
  ///
  /// [ciphertext]     — the AES-GCM ciphertext bytes (nonce NOT included)
  /// [sessionKey]     — shared secret used as the HMAC key
  /// [sequenceNumber] — fragment index (0, 1, or 2)
  /// [ttlMs]          — expiration timestamp in epoch milliseconds
  ///
  /// Returns 32-byte HMAC-SHA256 tag.
  Future<Uint8List> computeFragmentMac({
    required Uint8List ciphertext,
    required SecretKey sessionKey,
    required int sequenceNumber,
    required int ttlMs,
  }) async {
    final payload = _buildPayload(ciphertext, sequenceNumber, ttlMs);

    final mac = await _hmac.calculateMac(
      payload,
      secretKey: sessionKey,
    );

    // Zeroize the temporary payload buffer
    SecureMemory.zeroize(payload);

    return Uint8List.fromList(mac.bytes);
  }

  // --------------------------------------------------------------------------
  // VERIFY
  // --------------------------------------------------------------------------

  /// Verify a fragment MAC in constant time.
  ///
  /// Computes the expected MAC and compares all 32 bytes via
  /// [SecureMemory.constantTimeEquals] regardless of any early mismatch.
  ///
  /// Returns [true] only if the MAC is valid.
  /// Returns [false] (never throws) on any mismatch or error.
  Future<bool> verifyFragmentMac({
    required Uint8List ciphertext,
    required SecretKey sessionKey,
    required int sequenceNumber,
    required int ttlMs,
    required Uint8List expectedMac,
  }) async {
    try {
      final computed = await computeFragmentMac(
        ciphertext: ciphertext,
        sessionKey: sessionKey,
        sequenceNumber: sequenceNumber,
        ttlMs: ttlMs,
      );

      final valid = SecureMemory.constantTimeEquals(computed, expectedMac);

      // Zeroize the computed value before returning
      SecureMemory.zeroize(computed);

      return valid;
    } catch (_) {
      // Verification must never throw — return false on any internal failure.
      return false;
    }
  }

  // --------------------------------------------------------------------------
  // PRIVATE
  // --------------------------------------------------------------------------

  /// Build HMAC input payload:
  /// ```
  /// [seq: 4 bytes BE] [ciphertext: N bytes] [ttl: 8 bytes BE]
  /// ```
  Uint8List _buildPayload(Uint8List ciphertext, int seq, int ttlMs) {
    // Total: 4 (seq) + ciphertext.length + 8 (ttl)
    final payload = Uint8List(4 + ciphertext.length + 8);
    final bd = payload.buffer.asByteData();

    // Write sequence number as 4-byte big-endian
    bd.setUint32(0, seq, Endian.big);

    // Copy ciphertext into the middle
    payload.setAll(4, ciphertext);

    // Write TTL as 8-byte big-endian
    bd.setUint64(4 + ciphertext.length, ttlMs, Endian.big);

    return payload;
  }
}
