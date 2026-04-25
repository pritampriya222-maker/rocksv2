import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/app_theme.dart';
import '../../core/models/ephemeral_peer.dart';
import '../../providers/crypto_providers.dart';
import '../../providers/ble_providers.dart';

/// Messaging screen — compose, fragment, and broadcast a message.
///
/// Flow:
///   1. User types plaintext message
///   2. [SEND] encrypts → splits 40-30-30 → 3 MessageFragments
///   3. Fragments broadcast to all BLE peers
///   4. Received + reassembled messages appear in the inbox
class MessagingScreen extends ConsumerStatefulWidget {
  const MessagingScreen({super.key});

  @override
  ConsumerState<MessagingScreen> createState() => _MessagingScreenState();
}

class _MessagingScreenState extends ConsumerState<MessagingScreen> {
  final TextEditingController _controller = TextEditingController();
  bool _sending = false;
  String? _sendError;
  List<_InboxMessage> _inbox = [];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _listenForReassembledMessages();
  }

  // ---------------------------------------------------------------------------
  // Reassembly listener
  // ---------------------------------------------------------------------------

  void _listenForReassembledMessages() {
    // Watch fragment buffer; when a set is complete, attempt reassembly
    ref.listenManual(fragmentBufferProvider, (_, sets) async {
      for (final set in sets) {
        if (!set.isComplete) continue;

        final ecdh = ref.read(ecdhManagerProvider);
        final fragmentSvc = ref.read(fragmentServiceProvider);

        // Try each known peer's session key
        final peers = ref.read(connectedPeersProvider).valueOrNull ?? [];
        for (final EphemeralPeer peer in peers) {
          if (peer.sessionKey == null) continue;
          final sessionKey = await ecdh.deriveSessionKey(
            remotePublicKeyBytes: peer.ecdhPublicKey,
          );

          final plaintext = await fragmentSvc.reassembleFragments(
            fragments: set.orderedFragments,
            sessionKey: sessionKey,
          );

          if (plaintext != null) {
            ref.read(fragmentBufferProvider.notifier).removeSet(set.setId);
            if (mounted) {
              setState(() {
                _inbox = [
                  _InboxMessage(
                    text: plaintext,
                    receivedAt: DateTime.now(),
                    fragmentSetId: set.setId,
                  ),
                  ..._inbox,
                ];
              });
            }
            break;
          }
        }
      }
    });
  }

  // ---------------------------------------------------------------------------
  // Send
  // ---------------------------------------------------------------------------

  Future<void> _sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    if (_sending) return;

    setState(() {
      _sending = true;
      _sendError = null;
    });

    try {
      final peers = ref.read(connectedPeersProvider).valueOrNull ?? [];
      if (peers.isEmpty) {
        setState(() => _sendError = 'No peers connected. Check PEER NETWORK.');
        return;
      }

      // Use the first peer's session key (or broadcast to all)
      // For demo: use the most recently connected peer with a key
      final activePeer = peers.firstWhere(
        (p) => p.isKeyExchangeComplete,
        orElse: () => throw Exception('No peer with completed key exchange'),
      );

      final ecdh = ref.read(ecdhManagerProvider);
      final fragmentSvc = ref.read(fragmentServiceProvider);
      final bleMgr = ref.read(bleManagerProvider);

      final sessionKey = await ecdh.deriveSessionKey(
        remotePublicKeyBytes: activePeer.ecdhPublicKey,
      );

      final plaintextBytes = Uint8List.fromList(utf8.encode(text));
      final fragments = await fragmentSvc.createFragments(
        plaintext: plaintextBytes,
        sessionKey: sessionKey,
      );

      // Broadcast each fragment independently
      for (final fragment in fragments) {
        await bleMgr.broadcastFragment(fragment);
        // Small stagger between fragments (prevents BLE congestion)
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }

      _controller.clear();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('3 FRAGMENTS DISPATCHED'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      setState(() => _sendError = e.toString());
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(title: const Text('COMPOSE MESSAGE')),
      body: Column(
        children: [
          Expanded(child: _Inbox(messages: _inbox)),
          const Divider(height: 1),
          _Composer(
            controller: _controller,
            sending: _sending,
            error: _sendError,
            onSend: _sendMessage,
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// INBOX
// =============================================================================

class _InboxMessage {
  final String text;
  final DateTime receivedAt;
  final String fragmentSetId;
  const _InboxMessage({
    required this.text,
    required this.receivedAt,
    required this.fragmentSetId,
  });
}

class _Inbox extends StatelessWidget {
  final List<_InboxMessage> messages;
  const _Inbox({required this.messages});

  @override
  Widget build(BuildContext context) {
    if (messages.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inbox_outlined, color: AppTheme.textHint, size: 40),
            SizedBox(height: 12),
            Text(
              'NO MESSAGES YET',
              style: TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 11,
                letterSpacing: 1.5,
              ),
            ),
            SizedBox(height: 6),
            Text(
              'Received fragments will be reassembled here.',
              style: TextStyle(color: AppTheme.textHint, fontSize: 11),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: messages.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) => _MessageTile(msg: messages[i]),
    );
  }
}

class _MessageTile extends StatelessWidget {
  final _InboxMessage msg;
  const _MessageTile({required this.msg});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onLongPress: () => Clipboard.setData(ClipboardData(text: msg.text)),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: AppTheme.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.lock_open, size: 12, color: AppTheme.success),
                const SizedBox(width: 6),
                Text(
                  'DECRYPTED  •  ${_formatTime(msg.receivedAt)}',
                  style: const TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 10,
                    letterSpacing: 0.8,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              msg.text,
              style: const TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 15,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'SET: ${msg.fragmentSetId.substring(0, 12)}…',
              style: const TextStyle(
                color: AppTheme.textHint,
                fontSize: 10,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime t) {
    final h = t.hour.toString().padLeft(2, '0');
    final m = t.minute.toString().padLeft(2, '0');
    final s = t.second.toString().padLeft(2, '0');
    return '$h:$m:$s';
  }
}

// =============================================================================
// COMPOSER
// =============================================================================

class _Composer extends StatelessWidget {
  final TextEditingController controller;
  final bool sending;
  final String? error;
  final VoidCallback onSend;

  const _Composer({
    required this.controller,
    required this.sending,
    required this.error,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppTheme.surface,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                error!,
                style: const TextStyle(
                  color: AppTheme.error,
                  fontSize: 11,
                ),
              ),
            ),
          TextField(
            controller: controller,
            maxLines: 3,
            minLines: 1,
            style: const TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 14,
            ),
            decoration: const InputDecoration(
              hintText: 'Type emergency message…',
              hintStyle: TextStyle(color: AppTheme.textHint),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 44,
            child: ElevatedButton(
              onPressed: sending ? null : onSend,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.surfaceAlt,
                side: const BorderSide(color: AppTheme.accent),
              ),
              child: sending
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppTheme.accent,
                      ),
                    )
                  : const Text(
                      '[ ENCRYPT & BROADCAST 3 FRAGMENTS ]',
                      style: TextStyle(
                        fontSize: 11,
                        letterSpacing: 0.8,
                        color: AppTheme.accent,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
