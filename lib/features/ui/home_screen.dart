import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../qr/qr_screen.dart';
import '../../providers/network_providers.dart';
import '../../providers/crypto_providers.dart';
import '../../providers/messaging_providers.dart';
import '../../core/security/anti_forensics_service.dart';

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
    final allMessages = ref.watch(messagingControllerProvider);
    final messages = allMessages.where((m) => m.isGroup).toList();


    return Scaffold(
      appBar: AppBar(
        title: const Text('SECURE DIRECT'),
        actions: [
          IconButton(
            icon: const Icon(Icons.qr_code_2),
            tooltip: 'QR Fallback',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute<void>(builder: (_) => const QrScreen()),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.delete_forever, color: Colors.redAccent),
            tooltip: 'Wipe Memory',
            onPressed: () => _showWipeWarning(context, ref),
          ),
        ],
      ),
      body: Column(
        children: [
          _buildWebPortalStatus(),
          if (peerCount == 0)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              color: Colors.orange.withValues(alpha: 0.2),
              child: const Text(
                'No Mesh peers found. Discovery Active...',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.orangeAccent, fontSize: 13),
              ),
            ),

          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: messages.length,
              itemBuilder: (context, index) {
                final msg = messages[index];
                final bool isMe = msg.isMe;
                return Align(
                  alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: isMe ? Colors.blueAccent.withValues(alpha: 0.2) : Colors.grey[800],
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isMe ? Colors.blueAccent.withValues(alpha: 0.5) : Colors.transparent,
                      ),
                    ),
                    child: Text(
                      msg.text,
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                );
              },
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8).copyWith(
              bottom: MediaQuery.of(context).padding.bottom + 8,
            ),
            decoration: BoxDecoration(
              color: Colors.blueGrey[900],
              boxShadow: const [
                BoxShadow(color: Colors.black54, blurRadius: 10, offset: Offset(0, -2))
              ],
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _textController,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      hintText: 'Type secure message...',
                      hintStyle: TextStyle(color: Colors.grey),
                      border: InputBorder.none,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.send, color: Colors.blueAccent, size: 32),
                  onPressed: () {
                    final text = _textController.text.trim();
                    if (text.isNotEmpty) {
                      _sendMessage(ref, text);
                      _textController.clear();
                    }
                  },
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

  void _showWipeWarning(BuildContext context, WidgetRef ref) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('WIPE MEMORY?'),
        content: const Text(
          'This will permanently zero-out all cryptographic keys and RAM buffers.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('CANCEL'),
          ),
          TextButton(
            onPressed: () => ref.read(antiForensicsProvider).nuclearWipe(),
            child: const Text('WIPE & EXIT', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
  }

  Widget _buildWebPortalStatus() {

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.blueAccent.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blueAccent.withValues(alpha: 0.5)),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.laptop_chromebook, color: Colors.blueAccent, size: 20),
              SizedBox(width: 8),
              Text('LAPTOP WEB PORTAL', 
                style: TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.bold, fontSize: 12)),
            ],
          ),
          SizedBox(height: 8),
          Text('To join from a laptop, connect to this phone\'s hotspot and open:',
            style: TextStyle(color: Colors.white70, fontSize: 11)),
          SizedBox(height: 4),
          SelectableText(
            'http://192.168.43.1:9000',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16, fontFamily: 'monospace'),
          ),
          SizedBox(height: 4),
          Text('Note: Turn off any VPN on your laptop.',
            style: TextStyle(color: Colors.orangeAccent, fontSize: 10, fontStyle: FontStyle.italic)),
        ],
      ),
    );
  }
}

