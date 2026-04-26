import 'dart:convert';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import '../models/message_fragment.dart';
import 'aes_cipher.dart';
import 'hmac_util.dart';
import 'secure_memory.dart';
import 'crypto_constants.dart';

/// Splits plaintext into 3 independently encrypted fragments (40-30-30 split)
/// and reassembles them back to plaintext when all 3 are available.
///
/// ## Security Invariant
///
/// No device that holds only 1 or 2 fragments can reconstruct the message.
/// Each fragment is AES-256-GCM encrypted with a UNIQUE nonce and carries its
/// own HMAC-SHA256 tag. The session key is required to decrypt any fragment.
///
/// A relay device receives and forwards encrypted fragments it cannot decrypt.
///
/// ## Fragmentation Algorithm (40-30-30 split)
///
/// Given plaintext bytes of length N:
///   Fragment 0: bytes [0 .. split_a)          — 40%
///   Fragment 1: bytes [split_a .. split_b)     — 30%
///   Fragment 2: bytes [split_b .. N)           — remaining 30%
///
/// Each chunk is independently encrypted with AES-256-GCM.
/// The sequence number is bound via AAD, preventing reordering.
/// A common fragment-set ID is derived from HMAC of the concatenated nonces
/// so the receiver can group the three fragments without knowing content.
class FragmentService {
  final AesCipher _aes = AesCipher();
  final HmacUtil _hmac = HmacUtil();

  // --------------------------------------------------------------------------
  // FRAGMENT CREATION
  // --------------------------------------------------------------------------

  /// Split [plaintext] into 3 encrypted [MessageFragment]s.
  ///
  /// [plaintext]  — the user's message (UTF-8 encoded by caller before passing)
  /// [sessionKey] — 32-byte SecretKey from ECDH
  ///
  /// Returns exactly [CryptoConstants.fragmentCount] (3) fragments.
  /// The caller should zeroize the [plaintext] buffer after this returns.
  Future<List<MessageFragment>> createFragments({
    required Uint8List plaintext,
    required SecretKey sessionKey,
    bool isGroup = true,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final ttlMs = now + CryptoConstants.fragmentTtlMs;


    // --- Split plaintext into 3 chunks (40-30-30) ----------------------
    final chunks = _splitPlaintext(plaintext);

    // --- Encrypt each chunk independently ----------------------------
    final fragments = <MessageFragment>[];
    final allNonces = <Uint8List>[];

    for (var i = 0; i < CryptoConstants.fragmentCount; i++) {
      final chunk = chunks[i];

      final secretBox = await _aes.encryptFragment(
        plaintext: chunk,
        sessionKey: sessionKey,
        sequenceNumber: i,
      );

      final wireBytes = _aes.secretBoxToBytes(secretBox);

      // Extract the nonce for fragment-set ID derivation
      allNonces.add(Uint8List.fromList(secretBox.nonce));

      // Compute integrity MAC over ciphertext bytes
      final ciphertext = Uint8List.fromList(secretBox.cipherText);
      final macBytes = await _hmac.computeFragmentMac(
        ciphertext: ciphertext,
        sessionKey: sessionKey,
        sequenceNumber: i,
        ttlMs: ttlMs,
      );

      fragments.add(MessageFragment(
        fragmentSetId: '', // will be filled below
        index: i,
        total: CryptoConstants.fragmentCount,
        wireBytes: wireBytes,
        ciphertext: ciphertext,
        nonce: allNonces[i],
        hmacTag: macBytes,
        timestampMs: now,
        ttlMs: CryptoConstants.fragmentTtlMs,
        isGroup: isGroup,
      ));


      // Zeroize plaintext chunk immediately
      SecureMemory.zeroizeUint8List(chunk);
    }

    // --- Derive common fragment-set ID from all three nonces ----------
    // fragmentSetId = base64url(first 16 bytes of HMAC(key, nonce0||nonce1||nonce2))
    final nonceConcat = Uint8List(
      allNonces.fold(0, (sum, n) => sum + n.length),
    );
    var offset = 0;
    for (final n in allNonces) {
      nonceConcat.setAll(offset, n);
      offset += n.length;
    }
    final setIdMac = await _hmac.computeFragmentMac(
      ciphertext: nonceConcat,
      sessionKey: sessionKey,
      sequenceNumber: 0xff, // sentinel for set-ID computation
      ttlMs: 0,
    );
    SecureMemory.zeroize(nonceConcat);

    final setId = base64Url
        .encode(setIdMac.sublist(0, CryptoConstants.fragmentIdLength))
        .replaceAll('=', '');
    SecureMemory.zeroize(setIdMac);

    // Patch fragment-set ID into every fragment
    return [
      for (final f in fragments)
        MessageFragment(
          fragmentSetId: setId,
          index: f.index,
          total: f.total,
          wireBytes: f.wireBytes,
          ciphertext: f.ciphertext,
          nonce: f.nonce,
          hmacTag: f.hmacTag,
          timestampMs: f.timestampMs,
          ttlMs: f.ttlMs,
          isGroup: isGroup,
        ),
    ];

  }

  // --------------------------------------------------------------------------
  // REASSEMBLY
  // --------------------------------------------------------------------------

  /// Attempt to reassemble plaintext from [fragments].
  ///
  /// Requirements:
  ///   • Exactly [CryptoConstants.fragmentCount] fragments (3)
  ///   • All with the same [MessageFragment.fragmentSetId]
  ///   • None expired ([MessageFragment.isExpired])
  ///   • HMAC verification passes for each fragment
  ///   • AES-GCM decryption succeeds with [sessionKey]
  ///
  /// Returns UTF-8 decoded plaintext on success, [null] on any failure.
  /// Zeroizes all intermediate plaintext buffers before returning.
  Future<String?> reassembleFragments({
    required List<MessageFragment> fragments,
    required SecretKey sessionKey,
  }) async {
    // Validate count
    if (fragments.length != CryptoConstants.fragmentCount) return null;

    // Sort by index to ensure correct reassembly order
    final sorted = List<MessageFragment>.from(fragments)
      ..sort((a, b) => a.index.compareTo(b.index));

    // Validate all indices are 0, 1, 2 and same set
    final setId = sorted.first.fragmentSetId;
    for (var i = 0; i < sorted.length; i++) {
      if (sorted[i].index != i) return null;
      if (sorted[i].fragmentSetId != setId) return null;
      if (sorted[i].isExpired) return null;
    }

    // Decrypt each fragment
    final plaintextChunks = <Uint8List>[];
    for (final fragment in sorted) {
      // 1. Verify HMAC
      final ttlMs = fragment.timestampMs + fragment.ttlMs;
      final macValid = await _hmac.verifyFragmentMac(
        ciphertext: fragment.ciphertext,
        sessionKey: sessionKey,
        sequenceNumber: fragment.index,
        ttlMs: ttlMs,
        expectedMac: fragment.hmacTag,
      );
      if (!macValid) {
        _zeroizeChunks(plaintextChunks);
        return null;
      }

      // 2. Reconstruct SecretBox from wire bytes and decrypt
      final secretBox = _aes.bytesToSecretBox(fragment.wireBytes);
      final plainChunk = await _aes.decryptFragment(
        secretBox: secretBox,
        sessionKey: sessionKey,
        sequenceNumber: fragment.index,
      );
      if (plainChunk == null) {
        _zeroizeChunks(plaintextChunks);
        return null;
      }

      plaintextChunks.add(plainChunk);
    }

    // Concatenate plaintext chunks
    final total = plaintextChunks.fold(0, (sum, c) => sum + c.length);
    final fullPlaintext = Uint8List(total);
    var pos = 0;
    for (final chunk in plaintextChunks) {
      fullPlaintext.setAll(pos, chunk);
      pos += chunk.length;
    }

    // Decode UTF-8
    String? message;
    try {
      message = utf8.decode(fullPlaintext);
    } catch (_) {
      // Invalid UTF-8 — corrupted or wrong key
      message = null;
    }

    // Zeroize intermediate buffers
    _zeroizeChunks(plaintextChunks);
    SecureMemory.zeroizeUint8List(fullPlaintext);

    return message;
  }

  // --------------------------------------------------------------------------
  // RELAY VALIDATION (for blind relay devices)
  // --------------------------------------------------------------------------

  /// Quick HMAC check for relay devices that DO have the session key.
  ///
  /// Relay devices typically cannot decrypt but should verify integrity
  /// before forwarding to prevent flooding garbage data.
  ///
  /// Returns [false] if the fragment is expired, has a bad HMAC, or the key
  /// is unavailable. The relay should DROP fragments returning [false].
  Future<bool> verifyFragment({
    required MessageFragment fragment,
    required SecretKey sessionKey,
  }) async {
    if (fragment.isExpired) return false;
    if (fragment.hopCount >= CryptoConstants.maxHopCount) return false;

    final ttlMs = fragment.timestampMs + fragment.ttlMs;
    return _hmac.verifyFragmentMac(
      ciphertext: fragment.ciphertext,
      sessionKey: sessionKey,
      sequenceNumber: fragment.index,
      ttlMs: ttlMs,
      expectedMac: fragment.hmacTag,
    );
  }

  // --------------------------------------------------------------------------
  // PRIVATE HELPERS
  // --------------------------------------------------------------------------

  /// Split [plaintext] into 3 Uint8List chunks using the 40-30-30 ratio.
  ///
  /// For very short messages (< 3 bytes), every chunk gets at least 1 byte.
  List<Uint8List> _splitPlaintext(Uint8List plaintext) {
    final n = plaintext.length;

    // Compute boundaries; ensure each chunk has at least 1 byte
    final splitA = (n * CryptoConstants.fragmentSplitA).floor().clamp(1, n - 2);
    final splitB =
        (n * (CryptoConstants.fragmentSplitA + CryptoConstants.fragmentSplitB))
            .floor()
            .clamp(splitA + 1, n - 1);

    return [
      Uint8List.fromList(plaintext.sublist(0, splitA)),
      Uint8List.fromList(plaintext.sublist(splitA, splitB)),
      Uint8List.fromList(plaintext.sublist(splitB)),
    ];
  }

  void _zeroizeChunks(List<Uint8List> chunks) {
    for (final chunk in chunks) {
      SecureMemory.zeroizeUint8List(chunk);
    }
  }
}
