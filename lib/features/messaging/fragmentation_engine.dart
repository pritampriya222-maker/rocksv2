import 'dart:math';

/// Handles the 3-part splitting and deterministic reassembly of strings.
class FragmentationEngine {
  /// Splits a plaintext string into exactly 3 chunks (approx 40%, 30%, 30%).
  List<String> splitMessage(String plaintext) {
    if (plaintext.isEmpty) {
      return ['', '', ''];
    }

    final len = plaintext.length;
    // 40% for the first chunk
    final chunk0Len = max(1, (len * 0.4).floor());
    
    // Remaining length to be split 50/50 (which equates to 30% of total each)
    final remainingAfter0 = len - chunk0Len;
    final chunk1Len = remainingAfter0 > 1 ? (remainingAfter0 / 2).floor() : (remainingAfter0 == 1 ? 1 : 0);

    final chunk0 = plaintext.substring(0, chunk0Len);
    final chunk1 = plaintext.substring(chunk0Len, chunk0Len + chunk1Len);
    final chunk2 = plaintext.substring(chunk0Len + chunk1Len);

    return [chunk0, chunk1, chunk2];
  }

  /// Reassembles the 3 chunks back into the original plaintext message.
  /// 
  /// Throws an exception if any of the required sequence keys (0, 1, 2) are missing.
  String reassembleMessage(Map<int, String> chunks) {
    if (!chunks.containsKey(0) || !chunks.containsKey(1) || !chunks.containsKey(2)) {
      throw Exception('Incomplete chunks. Required sequence indices: 0, 1, 2.');
    }

    // Deterministic concatenation in exact order
    return chunks[0]! + chunks[1]! + chunks[2]!;
  }
}
