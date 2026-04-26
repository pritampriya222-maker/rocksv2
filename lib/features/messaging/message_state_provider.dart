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

class DisplayMessage {
  final String id;
  final String text;
  final DateTime receivedAt;
  final bool isMe;
  final String? peerId;
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

class MessageStateNotifier extends StateNotifier<List<DisplayMessage>> {
  final AesCipher _aesCipher;
  final FragmentationEngine _fragmentationEngine;
  final Map<String, Map<int, MessageFragment>> _incomingBuffers = {};
  final Map<String, SecretKey> _sessionKeyCache = {};
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

  void _scheduleCleanup() {
    _cleanupTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      final now = DateTime.now().millisecondsSinceEpoch;
      _incomingBuffers.removeWhere((messageId, fragmentsMap) {
        if (fragmentsMap.isEmpty) return true;
        final oldestTimestamp = fragmentsMap.values.map((f) => f.timestampMs).reduce((a, b) => a < b ? a : b);
        return now - oldestTimestamp > 300000;
      });
    });
  }

  Future<void> onFragmentReceived(MessageFragment fragment, List<EphemeralPeer> peers, EcdhManager ecdh) async {
    if (fragment.isExpired) return;
    final msgId = fragment.fragmentSetId;
    _incomingBuffers.putIfAbsent(msgId, () => {});
    _incomingBuffers[msgId]![fragment.index] = fragment;

    for (var peer in peers) {
      if (peer.isKeyExchangeComplete && !_sessionKeyCache.containsKey(peer.deviceUuid)) {
        final key = await ecdh.deriveSessionKey(remotePublicKeyBytes: peer.ecdhPublicKey);
        _sessionKeyCache[peer.deviceUuid] = key;
      }
    }

    if (_incomingBuffers[msgId]!.length == 3) {
      await _reassembleAndDecrypt(msgId, ecdh);
    }
  }

  Future<void> _reassembleAndDecrypt(String msgId, EcdhManager ecdh) async {
    final fragments = _incomingBuffers[msgId]!;
    _incomingBuffers.remove(msgId);

    for (final entry in _sessionKeyCache.entries) {
      final peerUuid = entry.key;
      final sessionKey = entry.value;

      try {
        final plaintextChunks = <int, String>{};
        for (var i = 0; i < 3; i++) {
          final f = fragments[i]!;
          final secretBox = _aesCipher.bytesToSecretBox(f.wireBytes);
          final decryptedBytes = await _aesCipher.decryptFragment(
            secretBox: secretBox,
            sessionKey: sessionKey,
            sequenceNumber: f.index,
          );
          if (decryptedBytes == null) throw Exception('Key mismatch');
          plaintextChunks[i] = utf8.decode(decryptedBytes);
        }

        final fullMessage = _fragmentationEngine.reassembleMessage(plaintextChunks);
        state = [
          ...state,
          DisplayMessage(
            id: msgId,
            text: fullMessage,
            receivedAt: DateTime.now(),
            isMe: false,
            peerId: peerUuid,
            isGroup: fragments.values.first.isGroup,
          )
        ];
        return;
      } catch (_) {
        continue;
      }
    }
  }

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
        final sessionKey = await ecdh.deriveSessionKey(remotePublicKeyBytes: peer.ecdhPublicKey);
        final plaintextBytes = Uint8List.fromList(utf8.encode(text));
        final fragments = await fragmentService.createFragments(
          plaintext: plaintextBytes,
          sessionKey: sessionKey,
          isGroup: isGroup,
        );
        fragmentSetId ??= fragments.first.fragmentSetId;
        for (final fragment in fragments) {
          await wifiManager.broadcastFragment(fragment);
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      } catch (e) {
        print('[Messaging] Failed to send to peer ${peer.ipAddress}: $e');
      }
    }

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
