import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models/ephemeral_peer.dart';
import '../../providers/network_providers.dart';
import '../../providers/messaging_providers.dart';
import '../../providers/crypto_providers.dart';

class DirectChatScreen extends ConsumerStatefulWidget {
  final EphemeralPeer peer;
  const DirectChatScreen({super.key, required this.peer});

  @override
  ConsumerState<DirectChatScreen> createState() => _DirectChatScreenState();
}

class _DirectChatScreenState extends ConsumerState<DirectChatScreen> {
  final _textController = TextEditingController();

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final allMessages = ref.watch(messagingControllerProvider);
    // Filter messages for this specific peer (Private messages involving this peerId)
    final messages = allMessages.where((m) => !m.isGroup && m.peerId == widget.peer.deviceUuid).toList();

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            CircleAvatar(
              radius: 16,
              backgroundColor: Colors.blueAccent.withValues(alpha: 0.2),
              child: const Icon(Icons.person, size: 18, color: Colors.blueAccent),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('PRIVATE: ${widget.peer.deviceUuid.substring(0, 8)}', style: const TextStyle(fontSize: 14)),
                Text(widget.peer.ipAddress ?? 'Offline', style: const TextStyle(fontSize: 10, color: Colors.greenAccent)),
              ],
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: messages.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.lock_outline, size: 48, color: Colors.grey[700]),
                        const SizedBox(height: 16),
                        const Text('END-TO-END ENCRYPTED', style: TextStyle(color: Colors.grey, fontSize: 10, letterSpacing: 2)),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: messages.length,
                    itemBuilder: (context, index) {
                      final msg = messages[index];
                      final isMe = msg.isMe;
                      return Align(
                        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          decoration: BoxDecoration(
                            color: isMe ? Colors.blueAccent.withValues(alpha: 0.2) : Colors.grey[800],
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: isMe ? Colors.blueAccent.withValues(alpha: 0.5) : Colors.transparent),
                          ),
                          child: Text(msg.text, style: const TextStyle(color: Colors.white)),
                        ),
                      );
                    },
                  ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8).copyWith(bottom: MediaQuery.of(context).padding.bottom + 8),
            decoration: BoxDecoration(
              color: Colors.blueGrey[900],
              boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 10, offset: Offset(0, -2))],
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _textController,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(hintText: 'Type private message...', hintStyle: TextStyle(color: Colors.grey), border: InputBorder.none),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.send, color: Colors.blueAccent, size: 32),
                  onPressed: () => _sendPrivateMessage(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _sendPrivateMessage() {
    final text = _textController.text.trim();
    if (text.isEmpty) return;

    final wifiMgr = ref.read(wifiMeshManagerProvider);
    final ecdh = ref.read(ecdhManagerProvider);
    final fragmentSvc = ref.read(fragmentServiceProvider);

    ref.read(messagingControllerProvider.notifier).sendMessage(
      text: text,
      wifiManager: wifiMgr,
      ecdh: ecdh,
      fragmentService: fragmentSvc,
      peers: [widget.peer], // ONLY this peer
      isGroup: false,
    );
    
    _textController.clear();
  }
}
