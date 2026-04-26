import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/network_providers.dart';
import '../../core/models/ephemeral_peer.dart';
import 'direct_chat_screen.dart';


class PeerListScreen extends ConsumerWidget {
  const PeerListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final peers = ref.watch(connectedPeersProvider).valueOrNull ?? [];

    return Scaffold(
      appBar: AppBar(
        title: const Text('PEER NETWORK'),
        actions: [
          const Padding(
            padding: EdgeInsets.only(right: 16),
            child: Icon(Icons.hub_outlined, color: Colors.blueAccent),
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
            color: Colors.blueAccent.withValues(alpha: 0.05),
            child: const Row(
              children: [
                Icon(Icons.wifi_tethering, size: 14, color: Colors.blueAccent),
                SizedBox(width: 8),
                Text(
                  'WI-FI MESH ACTIVE',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: Colors.blueAccent,
                  ),
                ),
                Spacer(),
                Text(
                  'DISCOVERING...',
                  style: TextStyle(fontSize: 10, color: Colors.grey),
                ),
              ],
            ),
          ),
          _buildWebPortalStatus(),

          Expanded(
            child: peers.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.hub_outlined, size: 64, color: Colors.grey),
                        const SizedBox(height: 24),
                        const Text(
                          'SEARCHING FOR MESH PEERS...',
                          style: TextStyle(color: Colors.grey, letterSpacing: 2),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Connect to the same Wi-Fi or Hotspot.',
                          style: TextStyle(color: Colors.grey, fontSize: 12),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: peers.length,
                    itemBuilder: (context, index) {
                      final peer = peers[index];
                      return _PeerCard(peer: peer);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildWebPortalStatus() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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


class _PeerCard extends ConsumerWidget {
  final EphemeralPeer peer;
  const _PeerCard({required this.peer});

  @override
  Widget build(BuildContext context, WidgetRef ref) {

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Colors.blueAccent.withValues(alpha: 0.2),
          child: const Icon(Icons.person, color: Colors.blueAccent),
        ),
        title: Text(
          'Peer ${peer.deviceUuid.substring(0, 8)}',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(peer.ipAddress ?? 'Local Mesh Peer'),

        trailing: const Icon(Icons.chevron_right, color: Colors.grey),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute<void>(
              builder: (context) => DirectChatScreen(peer: peer),
            ),
          );
        },


      ),
    );
  }
}
