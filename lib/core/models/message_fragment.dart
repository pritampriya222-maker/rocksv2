import 'dart:convert';
import 'dart:typed_data';

/// One of three independently encrypted shards of a message.
///
/// ## Security Invariants
///
/// - A single fragment reveals NOTHING about the plaintext.
/// - The [fragmentSetId] is derived from HMAC of the three nonces — it is
///   a correlation handle with no plaintext content.
/// - [ciphertext] and [wireBytes] contain no key material.
/// - [hmacTag] proves fragment authenticity to a holder of the session key;
///   a relay device without the session key cannot verify it, and should
///   forward blindly.
/// - [isExpired] must be checked before forwarding. Expired fragments are
///   dropped and zeroized by the relay buffer.
class MessageFragment {
  // --------------------------------------------------------------------------
  // IDENTITY
  // --------------------------------------------------------------------------

  /// Common identifier for all 3 fragments of one message.
  ///
  /// Derived from HMAC-SHA256(key, nonce0 || nonce1 || nonce2) — first 16
  /// bytes, base64url-encoded. Does NOT reveal plaintext or sender.
  final String fragmentSetId;

  /// This fragment's index in the set: 0, 1, or 2.
  final int index;

  /// Total fragments in the set (always 3).
  final int total;

  // --------------------------------------------------------------------------
  // CIPHERTEXT MATERIAL
  // --------------------------------------------------------------------------

  /// Flat wire encoding:
  /// ```
  /// [nonce: 12 bytes] [ciphertext: variable] [GCM tag: 16 bytes]
  /// ```
  /// Used for BLE transmission and QR encoding.
  final Uint8List wireBytes;

  /// Raw AES-GCM ciphertext (without nonce or tag).
  ///
  /// Stored separately for HMAC computation — the HMAC input is computed
  /// over ciphertext only, not the full wire encoding.
  final Uint8List ciphertext;

  /// 12-byte AES-GCM nonce unique to this fragment.
  final Uint8List nonce;

  /// HMAC-SHA256 tag covering: seq || ciphertext || ttlMs.
  final Uint8List hmacTag;

  // --------------------------------------------------------------------------
  // LIFECYCLE
  // --------------------------------------------------------------------------

  /// Unix epoch milliseconds when this fragment was created.
  final int timestampMs;

  /// Time-to-live in milliseconds (default 300 000 = 5 minutes).
  final int ttlMs;

  /// Current relay hop count. Incremented by each relay device.
  int hopCount;

  // --------------------------------------------------------------------------
  // CONSTRUCTION
  // --------------------------------------------------------------------------

  MessageFragment({
    required this.fragmentSetId,
    required this.index,
    required this.total,
    required this.wireBytes,
    required this.ciphertext,
    required this.nonce,
    required this.hmacTag,
    required this.timestampMs,
    this.ttlMs = 300000,
    this.hopCount = 0,
  });

  // --------------------------------------------------------------------------
  // EXPIRY
  // --------------------------------------------------------------------------

  /// Whether this fragment has outlived its TTL.
  bool get isExpired =>
      DateTime.now().millisecondsSinceEpoch > timestampMs + ttlMs;

  /// Milliseconds remaining before expiry (can be negative if expired).
  int get remainingTtlMs =>
      (timestampMs + ttlMs) - DateTime.now().millisecondsSinceEpoch;

  // --------------------------------------------------------------------------
  // SERIALIZATION (for QR encoding and BLE write)
  // --------------------------------------------------------------------------

  /// Serialize to a JSON-encodable map.
  ///
  /// Binary fields are base64url-encoded for compactness (important for QR
  /// version control — fewer characters = lower QR density).
  Map<String, dynamic> toJson() => {
        'id': fragmentSetId,
        'i': index,
        't': total,
        'w': base64Url.encode(wireBytes).replaceAll('=', ''),
        'h': base64Url.encode(hmacTag).replaceAll('=', ''),
        'ts': timestampMs,
        'ttl': ttlMs,
        'hop': hopCount,
      };

  /// Reconstruct a [MessageFragment] from a JSON-decoded map.
  ///
  /// Throws [FormatException] if any required key is missing or malformed.
  factory MessageFragment.fromJson(Map<String, dynamic> json) {
    final wireBytes = _b64d(json['w'] as String);

    // Extract ciphertext and nonce from wireBytes for internal use
    const nonceLen = 12;
    const tagLen = 16;
    if (wireBytes.length < nonceLen + tagLen + 1) {
      throw const FormatException('wireBytes too short in fragment JSON');
    }
    final nonce = wireBytes.sublist(0, nonceLen);
    final macStart = wireBytes.length - tagLen;
    final ciphertext = wireBytes.sublist(nonceLen, macStart);

    return MessageFragment(
      fragmentSetId: json['id'] as String,
      index: json['i'] as int,
      total: json['t'] as int,
      wireBytes: wireBytes,
      ciphertext: ciphertext,
      nonce: nonce,
      hmacTag: _b64d(json['h'] as String),
      timestampMs: json['ts'] as int,
      ttlMs: json['ttl'] as int? ?? 300000,
      hopCount: json['hop'] as int? ?? 0,
    );
  }

  /// Encode the fragment to a JSON string (for QR payload).
  String toJsonString() => jsonEncode(toJson());

  /// Decode a fragment from a JSON string (from QR scan).
  factory MessageFragment.fromJsonString(String jsonStr) =>
      MessageFragment.fromJson(
        jsonDecode(jsonStr) as Map<String, dynamic>,
      );

  // --------------------------------------------------------------------------
  // UTILITIES
  // --------------------------------------------------------------------------

  /// Create a copy with incremented hop count.
  MessageFragment withIncrementedHop() => MessageFragment(
        fragmentSetId: fragmentSetId,
        index: index,
        total: total,
        wireBytes: wireBytes,
        ciphertext: ciphertext,
        nonce: nonce,
        hmacTag: hmacTag,
        timestampMs: timestampMs,
        ttlMs: ttlMs,
        hopCount: hopCount + 1,
      );

  @override
  bool operator ==(Object other) =>
      other is MessageFragment &&
      other.fragmentSetId == fragmentSetId &&
      other.index == index;

  @override
  int get hashCode => Object.hash(fragmentSetId, index);

  @override
  String toString() =>
      'Fragment[$fragmentSetId #$index/$total hop=$hopCount]';

  // --------------------------------------------------------------------------
  // PRIVATE
  // --------------------------------------------------------------------------

  static Uint8List _b64d(String s) {
    // Restore padding stripped by toJson()
    var padded = s;
    while (padded.length % 4 != 0) {
      padded += '=';
    }
    return Uint8List.fromList(base64Url.decode(padded));
  }
}
