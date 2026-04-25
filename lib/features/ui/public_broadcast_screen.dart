import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../broadcast/gossip_controller.dart';

// Note: Declared as mock for UI compilation.
final gossipProvider = StateNotifierProvider<GossipController, List<PublicBroadcast>>((ref) => throw UnimplementedError());

/// The UI for viewing, creating, and manually relaying public alerts.
class PublicBroadcastScreen extends ConsumerWidget {
  const PublicBroadcastScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final broadcasts = ref.watch(gossipProvider);

    return Scaffold(
      body: broadcasts.isEmpty
          ? const Center(
              child: Text(
                'No public alerts detected in the area.',
                style: TextStyle(color: Colors.grey),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: broadcasts.length,
              itemBuilder: (context, index) {
                final broadcast = broadcasts[index];
                return _buildAlertCard(context, broadcast);
              },
            ),
      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          FloatingActionButton.small(
            heroTag: 'qr_broadcast',
            onPressed: () => _showQrOptions(context, ref, broadcasts.isNotEmpty ? broadcasts.first : null),
            backgroundColor: Colors.white,
            foregroundColor: Colors.black,
            child: const Icon(Icons.qr_code_2),
          ),
          const SizedBox(height: 16),
          FloatingActionButton.extended(
            heroTag: 'create_alert',
            onPressed: () => _showCreateAlertModal(context, ref),
            backgroundColor: Colors.orangeAccent,
            icon: const Icon(Icons.warning_amber_rounded),
            label: const Text('CREATE ALERT', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildAlertCard(BuildContext context, PublicBroadcast broadcast) {
    final date = DateTime.fromMillisecondsSinceEpoch(broadcast.timestamp);
    final timeString = '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';

    return Card(
      color: Colors.orange.withValues(alpha: 0.1),
      shape: RoundedRectangleBorder(
        side: const BorderSide(color: Colors.orangeAccent, width: 1),
        borderRadius: BorderRadius.circular(12),
      ),
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Row(
                  children: [
                    Icon(Icons.campaign, color: Colors.orangeAccent, size: 20),
                    SizedBox(width: 8),
                    Text('PUBLIC ALERT', style: TextStyle(color: Colors.orangeAccent, fontWeight: FontWeight.bold)),
                  ],
                ),
                Text(timeString, style: const TextStyle(color: Colors.grey, fontSize: 12)),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              broadcast.text,
              style: const TextStyle(fontSize: 16, color: Colors.white, height: 1.4),
            ),
            const SizedBox(height: 12),
            Text(
              'ID: ${broadcast.id.substring(0, 8)}...',
              style: const TextStyle(fontSize: 10, color: Colors.white54),
            ),
          ],
        ),
      ),
    );
  }

  void _showCreateAlertModal(BuildContext context, WidgetRef ref) {
    final textController = TextEditingController();

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom,
            left: 24,
            right: 24,
            top: 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Create Public Alert', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.orangeAccent)),
              const SizedBox(height: 8),
              const Text('This message will be sent in plaintext and permanently saved on all receiving devices in the mesh.', style: TextStyle(color: Colors.grey, fontSize: 13)),
              const SizedBox(height: 16),
              TextField(
                controller: textController,
                maxLength: 140, // Keep it short for simple QR compatibility
                decoration: const InputDecoration(
                  hintText: 'Describe the emergency...',
                  border: OutlineInputBorder(),
                ),
                maxLines: 3,
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.orangeAccent),
                  onPressed: () {
                    final text = textController.text.trim();
                    if (text.isNotEmpty) {
                      ref.read(gossipProvider.notifier).createAndSendBroadcast(text);
                      Navigator.pop(ctx);
                    }
                  },
                  child: const Text('BROADCAST ALERT', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(height: 32),
            ],
          ),
        );
      },
    );
  }

  void _showQrOptions(BuildContext context, WidgetRef ref, PublicBroadcast? latestBroadcast) {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.qr_code_scanner),
                title: const Text('Scan Incoming Broadcast'),
                onTap: () {
                  Navigator.pop(ctx);
                  _openScanner(context, ref);
                },
              ),
              if (latestBroadcast != null)
                ListTile(
                  leading: const Icon(Icons.qr_code_2),
                  title: const Text('Show Latest Broadcast QR'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _showLatestQr(context, latestBroadcast);
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  void _openScanner(BuildContext context, WidgetRef ref) {
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          appBar: AppBar(title: const Text('Scan Public Alert')),
          body: MobileScanner(
            onDetect: (capture) {
              final barcodes = capture.barcodes;
              for (final barcode in barcodes) {
                final rawData = barcode.rawValue;
                if (rawData != null && rawData.isNotEmpty) {
                  // Process simple JSON immediately without GZIP/Base64 decode
                  ref.read(gossipProvider.notifier).onBroadcastReceived(rawData);
                  Navigator.pop(context);
                  break;
                }
              }
            },
          ),
        ),
      ),
    );
  }

  void _showLatestQr(BuildContext context, PublicBroadcast broadcast) {
    // Generate simple JSON payload
    final jsonPayload = jsonEncode({
      'id': broadcast.id,
      'text': broadcast.text,
      'timestamp': broadcast.timestamp,
    });

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Broadcast QR', textAlign: TextAlign.center),
        content: SizedBox(
          width: 250,
          height: 250,
          child: QrImageView(
            data: jsonPayload,
            version: QrVersions.auto,
            errorCorrectionLevel: QrErrorCorrectLevel.M,
            backgroundColor: Colors.white,
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('DONE')),
        ],
      ),
    );
  }
}
