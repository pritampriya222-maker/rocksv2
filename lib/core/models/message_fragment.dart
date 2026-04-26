import 'dart:convert';
import 'dart:typed_data';

/// One of three independently encrypted shards of a message.
class MessageFragment {
  final String fragmentSetId;
  final int index;
  final int total;
  final Uint8List wireBytes;
  final Uint8List ciphertext;
  final Uint8List nonce;
  final Uint8List hmacTag;
  final int timestampMs;
  final int ttlMs;
  int hopCount;
  final bool isGroup;

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
    this.isGroup = true,
  });

  bool get isExpired =>
      DateTime.now().millisecondsSinceEpoch > timestampMs + ttlMs;

  Map<String, dynamic> toJson() => {
        'id': fragmentSetId,
        'i': index,
        't': total,
        'w': base64Url.encode(wireBytes).replaceAll('=', ''),
        'h': base64Url.encode(hmacTag).replaceAll('=', ''),
        'ts': timestampMs,
        'ttl': ttlMs,
        'hop': hopCount,
        'g': isGroup ? 1 : 0,
      };

  factory MessageFragment.fromJson(Map<String, dynamic> json) {
    final wireBytes = _b64d(json['w'] as String);
    const nonceLen = 12;
    const tagLen = 16;
    final nonce = wireBytes.sublist(0, nonceLen);
    final ciphertext = wireBytes.sublist(nonceLen, wireBytes.length - tagLen);

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
      isGroup: (json['g'] as int? ?? 1) == 1,
    );
  }

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
        isGroup: isGroup,
      );

  String toJsonString() => jsonEncode(toJson());
  Uint8List toWireBytes() => utf8.encode(toJsonString());

  factory MessageFragment.fromJsonString(String jsonStr) =>
      MessageFragment.fromJson(jsonDecode(jsonStr) as Map<String, dynamic>);

  factory MessageFragment.fromWireBytes(Uint8List bytes) =>
      MessageFragment.fromJsonString(utf8.decode(bytes));

  static Uint8List _b64d(String s) {
    var padded = s;
    while (padded.length % 4 != 0) padded += '=';
    return Uint8List.fromList(base64Url.decode(padded));
  }
}
