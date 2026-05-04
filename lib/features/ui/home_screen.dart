import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../qr/qr_screen.dart';
import '../../providers/network_providers.dart';
import '../../providers/crypto_providers.dart';
import '../../providers/messaging_providers.dart';
import '../../core/models/ephemeral_peer.dart';
import 'direct_chat_screen.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final _textController = TextEditingController();

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final peerCount = ref.watch(connectedPeersProvider).valueOrNull?.length ?? 0;
    final peers = ref.watch(connectedPeersProvider).valueOrNull ?? [];
    final allMessages = ref.watch(messagingControllerProvider);
    final groupMessages = allMessages.where((m) => m.isGroup).toList();

    return Scaffold(
      body: Column(
        children: [
          // Peer list horizontal scroll
          if (peers.isNotEmpty)
            Container(
              height: 80,
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF161616),
                border: Border(
                  bottom: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
                ),
              ),
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: peers.length,
                itemBuilder: (context, index) {
                  final peer = peers[index];
                  return _PeerChip(
                    peer: peer,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) => DirectChatScreen(peer: peer),
                        ),
                      );
                    },
                  );
                },
              ),
            ),

          if (peerCount == 0)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.orange.withValues(alpha: 0.1),
                    Colors.orange.withValues(alpha: 0.05),
                  ],
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.5,
                      color: Colors.orangeAccent.withValues(alpha: 0.7),
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Text(
                    'Searching for mesh peers...',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.orangeAccent, fontSize: 12),
                  ),
                ],
              ),
            ),

          // Group messages
          Expanded(
            child: groupMessages.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.forum_outlined,
                            size: 48, color: Colors.grey[700]),
                        const SizedBox(height: 16),
                        const Text(
                          'GROUP BROADCAST',
                          style: TextStyle(
                            color: Colors.grey,
                            fontSize: 10,
                            letterSpacing: 2,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Messages sent here go to all peers',
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: groupMessages.length,
                    itemBuilder: (context, index) {
                      final msg = groupMessages[index];
                      final bool isMe = msg.isMe;
                      final timeDiff =
                          DateTime.now().difference(msg.receivedAt);
                      final timeStr = timeDiff.inMinutes < 1
                          ? 'now'
                          : '${timeDiff.inMinutes}m ago';

                      return Align(
                        alignment: isMe
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          constraints: BoxConstraints(
                            maxWidth:
                                MediaQuery.of(context).size.width * 0.75,
                          ),
                          child: Column(
                            crossAxisAlignment: isMe
                                ? CrossAxisAlignment.end
                                : CrossAxisAlignment.start,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 10),
                                decoration: BoxDecoration(
                                  color: isMe
                                      ? Colors.blueAccent.withValues(alpha: 0.2)
                                      : const Color(0xFF262626),
                                  borderRadius: BorderRadius.only(
                                    topLeft: const Radius.circular(12),
                                    topRight: const Radius.circular(12),
                                    bottomLeft: Radius.circular(
                                        isMe ? 12 : 2),
                                    bottomRight: Radius.circular(
                                        isMe ? 2 : 12),
                                  ),
                                  border: Border.all(
                                    color: isMe
                                        ? Colors.blueAccent.withValues(alpha: 0.3)
                                        : Colors.white.withValues(alpha: 0.06),
                                  ),
                                ),
                                child: Text(
                                  msg.text,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 3),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (isMe)
                                    const Icon(Icons.done_all,
                                        size: 11, color: Colors.blueAccent),
                                  if (isMe) const SizedBox(width: 4),
                                  Text(
                                    timeStr,
                                    style: TextStyle(
                                      color: Colors.white.withValues(alpha: 0.3),
                                      fontSize: 9,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),

          // Message input
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8)
                .copyWith(
              bottom: MediaQuery.of(context).padding.bottom + 8,
            ),
            decoration: BoxDecoration(
              color: const Color(0xFF161616),
              border: Border(
                top: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
              ),
            ),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.qr_code_2,
                      color: Colors.blueAccent, size: 22),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                          builder: (_) => const QrScreen()),
                    );
                  },
                ),
                Expanded(
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(
                      color: const Color(0xFF222222),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                          color: Colors.white.withValues(alpha: 0.08)),
                    ),
                    child: TextField(
                      controller: _textController,
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                      decoration: InputDecoration(
                        hintText: 'Broadcast to mesh...',
                        hintStyle: TextStyle(
                            color: Colors.white.withValues(alpha: 0.25), fontSize: 13),
                        border: InputBorder.none,
                        contentPadding:
                            const EdgeInsets.symmetric(vertical: 10),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () {
                    final text = _textController.text.trim();
                    if (text.isNotEmpty) {
                      _sendMessage(ref, text);
                      _textController.clear();
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: const BoxDecoration(
                      color: Colors.blueAccent,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.send,
                        color: Colors.white, size: 18),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _sendMessage(WidgetRef ref, String text) {
    final wifiMgr = ref.read(wifiMeshManagerProvider);
    final ecdh = ref.read(ecdhManagerProvider);
    final fragmentSvc = ref.read(fragmentServiceProvider);
    final peers = ref.read(connectedPeersProvider).valueOrNull ?? [];

    if (peers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No peers connected. Wait for discovery.')),
      );
      return;
    }

    ref.read(messagingControllerProvider.notifier).sendMessage(
          text: text,
          wifiManager: wifiMgr,
          ecdh: ecdh,
          fragmentService: fragmentSvc,
          peers: peers,
        );
  }
}

// =============================================================================
// PEER CHIP
// =============================================================================

class _PeerChip extends StatelessWidget {
  final EphemeralPeer peer;
  final VoidCallback onTap;
  const _PeerChip({required this.peer, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(right: 10),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: Colors.blueAccent.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.blueAccent.withValues(alpha: 0.2)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircleAvatar(
              radius: 14,
              backgroundColor: Colors.blueAccent.withValues(alpha: 0.2),
              child: const Icon(Icons.person, size: 14, color: Colors.blueAccent),
            ),
            const SizedBox(height: 4),
            Text(
              peer.deviceUuid.substring(0, 6),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 9,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
