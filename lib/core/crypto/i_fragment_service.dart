import 'dart:typed_data';
import 'package:offline_mesh_app/core/models/message_fragment.dart';

/// Fragment service interface — implemented in Prompt 3.
abstract class IFragmentService {
  /// Split plaintext into 3 encrypted fragments.
  /// Each fragment encrypted with the shared session key.
  /// No single fragment contains enough data to reconstruct the message.
  Future<List<MessageFragment>> fragmentAndEncrypt({
    required String plaintext,
    required Uint8List sessionKey,
  });

  /// Attempt to reconstruct plaintext from 3 received fragments.
  /// Returns null if any fragment is missing or invalid.
  Future<String?> reassembleFragments({
    required List<MessageFragment> fragments,
    required Uint8List sessionKey,
  });

  /// Verify a fragment's HMAC before relaying.
  Future<bool> verifyFragment({
    required MessageFragment fragment,
    required Uint8List sessionKey,
  });
}
