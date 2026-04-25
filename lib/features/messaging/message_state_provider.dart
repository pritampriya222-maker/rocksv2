import 'dart:async';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cryptography/cryptography.dart';
import '../../core/models/message_fragment.dart';
import '../../core/crypto/aes_cipher.dart';
import 'fragmentation_engine.dart';

/// Represents a successfully reassembled and decrypted message for the UI.
class DisplayMessage {
  final String id;
  final String text;
  final DateTime receivedAt;

  DisplayMessage({required this.id, required this.text, required this.receivedAt});
}

/// Riverpod StateNotifier to track incoming fragments and trigger reassembly.
class MessageStateNotifier extends StateNotifier<List<DisplayMessage>> {
  final AesCipher _aesCipher;
  final FragmentationEngine _fragmentationEngine;
  
  // Dependency to fetch the current active session key for decryption.
  final Future<SecretKey> Function() _getSessionKey;

  /// Private RAM buffer: Key is Message ID (fragmentSetId), inner map tracks sequence index (0, 1, 2).
  final Map<String, Map<int, MessageFragment>> _incomingBuffers = {};
  
  Timer? _cleanupTimer;

  MessageStateNotifier({
    required AesCipher aesCipher,
    required FragmentationEngine fragmentationEngine,
    required Future<SecretKey> Function() getSessionKey,
  })  : _aesCipher = aesCipher,
        _fragmentationEngine = fragmentationEngine,
        _getSessionKey = getSessionKey,
        super([]) {
    _scheduleCleanup();
  }

  @override
  void dispose() {
    _cleanupTimer?.cancel();
    super.dispose();
  }

  /// Starts a periodic timer to clear incomplete buffers older than 5 minutes from RAM.
  void _scheduleCleanup() {
    _cleanupTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      final now = DateTime.now().millisecondsSinceEpoch;
      
      _incomingBuffers.removeWhere((messageId, fragmentsMap) {
        if (fragmentsMap.isEmpty) return true;
        
        // Find the oldest fragment timestamp in this set
        final oldestTimestamp = fragmentsMap.values
            .map((f) => f.timestampMs)
            .reduce((a, b) => a < b ? a : b);
            
        // Drop buffer if sitting incomplete for > 5 minutes (300000 ms)
        return now - oldestTimestamp > 300000;
      });
    });
  }

  /// Processes an incoming encrypted fragment, buffering it in RAM.
  /// Reassembles the full message immediately when all 3 fragments (LEN == 3) arrive.
  Future<void> onFragmentReceived(MessageFragment fragment) async {
    // 1. Drop expired fragments immediately
    if (fragment.isExpired) return;

    final msgId = fragment.fragmentSetId;

    // 2. Initialize buffer map for this msgId if not exists
    _incomingBuffers.putIfAbsent(msgId, () => {});

    // 3. Add fragment to the buffer by its sequence index (0, 1, or 2)
    _incomingBuffers[msgId]![fragment.index] = fragment;

    // 4. Check if we have all 3 pieces for this message ID
    if (_incomingBuffers[msgId]!.length == 3) {
      await _reassembleAndDecrypt(msgId);
    }
  }

  /// Decrypts the 3 fragments and reassembles them using the FragmentationEngine.
  Future<void> _reassembleAndDecrypt(String msgId) async {
    // Extract the complete set of 3 fragments
    final fragments = _incomingBuffers[msgId]!;
    
    // CRITICAL: Immediately remove the message ID from buffer to free RAM
    _incomingBuffers.remove(msgId);

    try {
      final sessionKey = await _getSessionKey();
      final plaintextChunks = <int, String>{};

      // 1. Pass the 3 fragments to AesCipher for decryption
      for (var i = 0; i < 3; i++) {
        final f = fragments[i]!;
        
        // Reconstruct the SecretBox from the raw wireBytes
        final secretBox = _aesCipher.bytesToSecretBox(f.wireBytes);
        
        // Attempt decryption (will fail gracefully if we are a blind relay)
        final decryptedBytes = await _aesCipher.decryptFragment(
           secretBox: secretBox,
           sessionKey: sessionKey,
           sequenceNumber: f.index, // Sequence validation via AAD
        );
        
        if (decryptedBytes == null) {
          throw Exception('Decryption failed for chunk index $i');
        }
        
        plaintextChunks[i] = utf8.decode(decryptedBytes);
      }

      // 2. Reassemble via FragmentationEngine
      final fullMessage = _fragmentationEngine.reassembleMessage(plaintextChunks);

      // 3. Add the final assembled message to Riverpod state to trigger UI updates
      state = [
        ...state,
        DisplayMessage(
          id: msgId,
          text: fullMessage,
          receivedAt: DateTime.now(),
        )
      ];
    } catch (e) {
      // If decryption fails (e.g. we don't have the key), this node is just a relay.
      // We silently drop the error as the transport layer handles broadcasting separately.
    }
  }
}
