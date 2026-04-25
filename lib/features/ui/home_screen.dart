import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'qr_exchange_screen.dart';

import '../messaging/message_state_provider.dart';

// Note: In a complete project, these would be imported from your provider registry.
// We declare mock providers here for UI structural compilation as per the prompt.
final peerCountProvider = StateProvider<int>((ref) => 0);
final messagesProvider = StateProvider<List<DisplayMessage>>((ref) => []);
final meshRelayProvider = Provider<dynamic>((ref) => throw UnimplementedError());
final fragmentationEngineProvider = Provider<dynamic>((ref) => throw UnimplementedError());

/// The main dashboard for the user to see peers, read messages, and send new ones.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final peerCount = ref.watch(peerCountProvider);
    final messages = ref.watch(messagesProvider);
    final textController = TextEditingController();

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Offline Mesh', style: TextStyle(fontWeight: FontWeight.bold)),
            Text(
              peerCount > 0 ? 'BLE Active: $peerCount Peers' : 'BLE Disconnected',
              style: TextStyle(
                fontSize: 12,
                color: peerCount > 0 ? Colors.greenAccent : Colors.redAccent,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_forever, color: Colors.redAccent),
            tooltip: 'Wipe Memory & Exit',
            onPressed: () => _showWipeWarning(context, ref),
          ),
        ],
      ),
      body: Column(
        children: [
          // Graceful Degradation Warning
          if (peerCount == 0)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              color: Colors.orange.withValues(alpha: 0.2),
              child: const Text(
                'No BLE peers found. Use the QR Fallback for air-gapped relay.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.orangeAccent, fontSize: 13),
              ),
            ),
            
          // Messages List
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: messages.length,
              itemBuilder: (context, index) {
                final msg = messages[index];
                final bool isMe = index % 2 == 0; // Mocking isMe dynamically for UI display
                
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
          
          // Bottom Input Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8).copyWith(
              bottom: MediaQuery.of(context).padding.bottom + 8,
            ),
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: textController,
                    decoration: const InputDecoration(
                      hintText: 'Type secure message...',
                      border: InputBorder.none,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.send, color: Colors.blueAccent),
                  onPressed: () {
                    final text = textController.text.trim();
                    if (text.isNotEmpty) {
                      _sendMessage(ref, text);
                      textController.clear();
                    }
                  },
                ),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute<void>(builder: (_) => const QrExchangeScreen()),
          );
        },
        icon: const Icon(Icons.qr_code_2),
        label: const Text('QR Fallback'),
      ),
    );
  }

  void _sendMessage(WidgetRef ref, String text) {
    // 1. Pass text to FragmentationEngine
    // final engine = ref.read(fragmentationEngineProvider);
    // final chunks = engine.splitMessage(text);
    
    // 2. Encrypt chunks (delegated to Crypto layer)
    // 3. Pass to MeshRelayController for broadcast
    // final relay = ref.read(meshRelayProvider);
    // chunks.forEach((chunk) => relay.broadcastFragment(chunk));
    
    // Note: State logic omitted as per strict UI layer constraints.
  }

  void _showWipeWarning(BuildContext context, WidgetRef ref) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('WIPE MEMORY?'),
        content: const Text(
          'This will permanently zero-out all cryptographic keys and RAM buffers, then exit the app. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('CANCEL'),
          ),
          TextButton(
            onPressed: () {
              // 1. Call SessionLifecycleManager.teardown()
              // 2. Clear Riverpod state
              // 3. Exit App (e.g. SystemNavigator.pop())
            },
            child: const Text('WIPE & EXIT', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
  }
}
