import 'dart:async';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cryptography/cryptography.dart';
import '../../core/models/message_fragment.dart';
import '../../core/models/ephemeral_peer.dart';
import '../../core/crypto/crypto.dart';
import '../../core/network/wifi_mesh_manager.dart';


import 'fragmentation_engine.dart';
import 'dart:typed_data';


/// Represents a successfully reassembled and decrypted message for the UI.
class DisplayMessage {
  final String id;
  final String text;
  final DateTime receivedAt;
  final bool isMe;
  final String? peerId; // Null for group chat, or the ID of the specific peer
  final bool isGroup;

  DisplayMessage({
    required this.id,
    required this.text,
    required this.receivedAt,
    this.isMe = false,
    this.peerId,
    this.isGroup = true,
  });
}


/// Riverpod StateNotifier to track incoming fragments and trigger reassembly.
class MessageStateNotifier extends StateNotifier<List<DisplayMessage>> {
  final AesCipher _aesCipher;
  final FragmentationEngine _fragmentationEngine;
  
  final Map<String, Map<int, MessageFragment>> _incomingBuffers = {};
  Timer? _cleanupTimer;

  
  MessageStateNotifier({
    required AesCipher aesCipher,
    required FragmentationEngine fragmentationEngine,
  })  : _aesCipher = aesCipher,
        _fragmentationEngine = fragmentationEngine,
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
  Future<void> onFragmentReceived(MessageFragment fragment, List<EphemeralPeer> peers, EcdhManager ecdh) async {
    // 1. Drop expired fragments immediately
    if (fragment.isExpired) return;

    final msgId = fragment.fragmentSetId;

    // 2. Initialize buffer map for this msgId if not exists
    _incomingBuffers.putIfAbsent(msgId, () => {});

    // 3. Add fragment to the buffer by its sequence index (0, 1, or 2)
    _incomingBuffers[msgId]![fragment.index] = fragment;

    // 4. Check if we have all 3 pieces for this message ID
    if (_incomingBuffers[msgId]!.length == 3) {
      await _reassembleAndDecrypt(msgId, peers, ecdh);
    }
  }


  /// Decrypts the 3 fragments and reassembles them using the FragmentationEngine.
  Future<void> _reassembleAndDecrypt(String msgId, List<EphemeralPeer> peers, EcdhManager ecdh) async {
    final fragments = _incomingBuffers[msgId]!;
    _incomingBuffers.remove(msgId);

    // Try EVERY peer to see who sent this message
    for (final peer in peers) {
      try {
        if (!peer.isKeyExchangeComplete) continue;

        final sessionKey = await ecdh.deriveSessionKey(
          remotePublicKeyBytes: peer.ecdhPublicKey,
        );

        final plaintextChunks = <int, String>{};

        for (var i = 0; i < 3; i++) {
          final f = fragments[i]!;
          final secretBox = _aesCipher.bytesToSecretBox(f.wireBytes);
          final decryptedBytes = await _aesCipher.decryptFragment(
            secretBox: secretBox,
            sessionKey: sessionKey,
            sequenceNumber: f.index,
          );
          
          if (decryptedBytes == null) throw Exception('No match');
          plaintextChunks[i] = utf8.decode(decryptedBytes);
        }

        // IF WE REACH HERE, Decryption succeeded with this peer's key!
        final fullMessage = _fragmentationEngine.reassembleMessage(plaintextChunks);

        state = [
          ...state,
          DisplayMessage(
            id: msgId,
            text: fullMessage,
            receivedAt: DateTime.now(),
            isMe: false,
            peerId: peer.deviceUuid,
            isGroup: fragments.values.first.isGroup,
          )
        ];

        return; // Success! Stop trying other peers.
      } catch (_) {
        continue; // Try next peer
      }
    }
  }


  /// Sends a plaintext message by fragmenting and broadcasting it.
  /// (This fix addresses the "no effect" issue for the sender and recipient)
  Future<void> sendMessage({
    required String text,
    required WifiMeshManager wifiManager,
    required EcdhManager ecdh,
    required FragmentService fragmentService,
    required List<EphemeralPeer> peers,
    bool isGroup = true,
  }) async {
    if (peers.isEmpty) return;
    
    String? fragmentSetId;
    String? lastPeerId;

    for (final peer in peers) {
      try {
        if (!peer.isKeyExchangeComplete) continue;

        lastPeerId = peer.deviceUuid;

        // 1. Derive unique session key for THIS peer
        final sessionKey = await ecdh.deriveSessionKey(
          remotePublicKeyBytes: peer.ecdhPublicKey,
        );

        // 2. Create encrypted fragments specifically for THIS peer
        final plaintextBytes = Uint8List.fromList(utf8.encode(text));
        final fragments = await fragmentService.createFragments(
          plaintext: plaintextBytes,
          sessionKey: sessionKey,
          isGroup: isGroup,
        );

        
        fragmentSetId ??= fragments.first.fragmentSetId;

        // 3. Send to mesh
        for (final fragment in fragments) {
          await wifiManager.broadcastFragment(fragment);
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      } catch (e) {
        print('[Messaging] Failed to send to peer ${peer.ipAddress}: $e');
      }
    }

    // 4. Add to local state
    state = [
      ...state,
      DisplayMessage(
        id: fragmentSetId ?? DateTime.now().toString(),
        text: text,
        receivedAt: DateTime.now(),
        isMe: true,
        isGroup: isGroup,
        peerId: isGroup ? null : lastPeerId,
      )
    ];
  }


}


