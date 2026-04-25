import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'crypto_constants.dart';
import 'secure_memory.dart';

/// AES-256-GCM encryption and decryption for message fragments.
///
/// ## Design Decisions
///
/// **AES-256-GCM vs ChaCha20-Poly1305:**
/// Both are available in `cryptography ^2.5.0`. AES-GCM is chosen because:
/// - ARM Cortex-A has native AES instructions (NEON + AES extensions) on
///   Android 8+ and all A-series iOS chips — hardware-accelerated at OS level.
/// - GCM is standardised in FIPS 140-2, making audit simpler.
/// ChaCha20 would be preferable on very low-end hardware; for modern
/// Android/iOS devices AES-GCM is equally fast or faster.
///
/// **Nonce strategy:**
/// - Each encryption call generates a fresh 12-byte random nonce.
/// - The sequence number is embedded in Additional Authenticated Data (AAD),
///   cryptographically binding the fragment index to its ciphertext.
/// - A (key, nonce) reuse would be catastrophic for GCM. Because we generate
///   a 96-bit random nonce per fragment, the birthday bound is ~2^48 fragments
///   per key — far beyond what any session produces.
///
/// **Error handling:**
/// [decryptFragment] returns `null` on ANY failure (wrong key, corrupted
/// ciphertext, wrong sequence). It never throws — callers in the relay loop
/// must not be able to distinguish *why* decryption failed.
class AesCipher {
  final AesGcm _aesGcm = AesGcm.with256bits(
    nonceLength: CryptoConstants.aesGcmNonceLength,
  );

  // --------------------------------------------------------------------------
  // ENCRYPTION
  // --------------------------------------------------------------------------

  /// Encrypt [plaintext] with AES-256-GCM.
  ///
  /// [plaintext]      — fragment bytes to encrypt (caller responsible for
  ///                    zeroizing the source buffer after this call returns)
  /// [sessionKey]     — 32-byte SecretKey derived from ECDH
  /// [sequenceNumber] — fragment index (0, 1, or 2); bound to ciphertext
  ///                    via AAD to prevent fragment reordering attacks
  ///
  /// Returns a [SecretBox] containing:
  ///   • [SecretBox.nonce]      — 12 random bytes
  ///   • [SecretBox.cipherText] — encrypted bytes (same length as plaintext)
  ///   • [SecretBox.mac]        — 16-byte GCM authentication tag
  ///
  /// Throws [ArgumentError] if the session key is the wrong length.
  Future<SecretBox> encryptFragment({
    required Uint8List plaintext,
    required SecretKey sessionKey,
    required int sequenceNumber,
  }) async {
    // Validate key length before use — guard against mis-wired callers.
    final keyBytes = await sessionKey.extractBytes();
    final keyLen = keyBytes.length;
    SecureMemory.zeroize(keyBytes); // extracted only for validation
    if (keyLen != CryptoConstants.aesKeyLength) {
      throw ArgumentError(
        'Session key must be ${CryptoConstants.aesKeyLength} bytes, '
        'got $keyLen',
      );
    }

    // AAD: big-endian 4-byte sequence number
    final aad = _buildAad(sequenceNumber);

    // Generate random nonce — each call uses a fresh nonce
    final nonce = _randomNonce();

    final secretBox = await _aesGcm.encrypt(
      plaintext,
      secretKey: sessionKey,
      nonce: nonce,
      aad: aad,
    );

    return secretBox;
  }

  // --------------------------------------------------------------------------
  // DECRYPTION
  // --------------------------------------------------------------------------

  /// Attempt to decrypt [secretBox] with [sessionKey].
  ///
  /// [secretBox]      — reconstructed from received wire bytes via
  ///                    [bytesToSecretBox]
  /// [sessionKey]     — candidate session key (may be wrong key for blind relay)
  /// [sequenceNumber] — expected fragment index for AAD validation
  ///
  /// Returns:
  ///   • [Uint8List] plaintext on success
  ///   • `null` on ANY failure (wrong key, corrupted MAC, wrong sequence)
  ///
  /// **CRITICAL:** Never throw from this method. Callers must not be able to
  /// distinguish which failure mode occurred (timing / side-channel safety).
  Future<Uint8List?> decryptFragment({
    required SecretBox secretBox,
    required SecretKey sessionKey,
    required int sequenceNumber,
  }) async {
    final aad = _buildAad(sequenceNumber);
    try {
      final plaintext = await _aesGcm.decrypt(
        secretBox,
        secretKey: sessionKey,
        aad: aad,
      );
      return Uint8List.fromList(plaintext);
    } on SecretBoxAuthenticationError catch (_) {
      // Expected for blind relay — wrong key or tampered data.
      return null;
    } on ArgumentError catch (_) {
      // Key or nonce length mismatch.
      return null;
    } catch (_) {
      // Any other platform/implementation error.
      return null;
    }
  }

  // --------------------------------------------------------------------------
  // WIRE ENCODING / DECODING
  // --------------------------------------------------------------------------

  /// Serialize a [SecretBox] to a flat byte array for BLE transmission or QR.
  ///
  /// Wire format:
  /// ```
  /// [ nonce (12 bytes) | ciphertext (variable) | mac (16 bytes) ]
  /// ```
  Uint8List secretBoxToBytes(SecretBox box) {
    final nonce = Uint8List.fromList(box.nonce);
    final cipher = Uint8List.fromList(box.cipherText);
    final mac = Uint8List.fromList(box.mac.bytes);

    final total = nonce.length + cipher.length + mac.length;
    final out = Uint8List(total);
    var offset = 0;

    out.setAll(offset, nonce);
    offset += nonce.length;

    out.setAll(offset, cipher);
    offset += cipher.length;

    out.setAll(offset, mac);

    return out;
  }

  /// Reconstruct a [SecretBox] from flat wire bytes.
  ///
  /// Inverse of [secretBoxToBytes]. Throws [ArgumentError] if [bytes] is
  /// shorter than the minimum viable SecretBox.
  SecretBox bytesToSecretBox(Uint8List bytes) {
    if (bytes.length < CryptoConstants.minSecretBoxWireLength) {
      throw ArgumentError(
        'Wire bytes too short: ${bytes.length} < '
        '${CryptoConstants.minSecretBoxWireLength}',
      );
    }

    const nonceEnd = CryptoConstants.aesGcmNonceLength;
    final macStart = bytes.length - CryptoConstants.aesGcmTagLength;

    final nonce = bytes.sublist(0, nonceEnd);
    final cipherText = bytes.sublist(nonceEnd, macStart);
    final macBytes = bytes.sublist(macStart);

    return SecretBox(
      cipherText,
      nonce: nonce,
      mac: Mac(macBytes),
    );
  }

  // --------------------------------------------------------------------------
  // PRIVATE HELPERS
  // --------------------------------------------------------------------------

  /// Build a 4-byte big-endian AAD buffer from [sequenceNumber].
  Uint8List _buildAad(int sequenceNumber) {
    final aad = Uint8List(4);
    aad.buffer.asByteData().setUint32(0, sequenceNumber, Endian.big);
    return aad;
  }

  /// Generate a cryptographically random 12-byte nonce.
  List<int> _randomNonce() {
    // SecureRandom from the cryptography package delegates to
    // dart:math SecureRandom (platform CSPRNG: /dev/urandom on Android/iOS)
    return _aesGcm.newNonce();
  }
}
