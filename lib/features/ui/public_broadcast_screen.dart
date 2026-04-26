import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../core/models/public_alert.dart';

import '../../providers/alert_providers.dart';

class PublicBroadcastScreen extends ConsumerStatefulWidget {
  const PublicBroadcastScreen({super.key});

  @override
  ConsumerState<PublicBroadcastScreen> createState() => _PublicBroadcastScreenState();
}

class _PublicBroadcastScreenState extends ConsumerState<PublicBroadcastScreen> {
  final Set<String> _selectedAlertIds = {};
  bool _isSelectionMode = false;

  @override
  Widget build(BuildContext context) {
    final alerts = ref.watch(alertProvider);

    return Scaffold(
      appBar: _isSelectionMode
          ? AppBar(
              title: Text('${_selectedAlertIds.length} Selected'),
              leading: IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => setState(() {
                  _isSelectionMode = false;
                  _selectedAlertIds.clear();
                }),
              ),
              actions: [
                IconButton(
                  icon: const Icon(Icons.qr_code_scanner),
                  onPressed: () => _openScanner(context),
                ),
                IconButton(
                  icon: const Icon(Icons.qr_code_2),
                  onPressed: () => _showBundleQr(context, alerts),
                ),
              ],
            )
          : AppBar(
              title: const Text('PUBLIC ALERTS'),
              actions: [
                IconButton(
                  icon: const Icon(Icons.qr_code_scanner),
                  tooltip: 'Scan & Import Alerts',
                  onPressed: () => _openScanner(context),
                ),
              ],
            ),

      body: alerts.isEmpty
          ? const Center(
              child: Text(
                'No public alerts detected in the area.',
                style: TextStyle(color: Colors.grey),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: alerts.length,
              itemBuilder: (context, index) {
                final alert = alerts[index];
                final isSelected = _selectedAlertIds.contains(alert.id);
                
                return GestureDetector(
                  onLongPress: () {
                    setState(() {
                      _isSelectionMode = true;
                      _selectedAlertIds.add(alert.id);
                    });
                  },
                  onTap: () {
                    if (_isSelectionMode) {
                      setState(() {
                        if (isSelected) {
                          _selectedAlertIds.remove(alert.id);
                          if (_selectedAlertIds.isEmpty) _isSelectionMode = false;
                        } else {
                          _selectedAlertIds.add(alert.id);
                        }
                      });
                    } else {
                      _showAlertDetails(context, alert);
                    }
                  },
                  child: _buildAlertCard(alert, isSelected),
                );
              },
            ),
      floatingActionButton: _isSelectionMode
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _showCreateAlertModal(context, ref),
              backgroundColor: Colors.redAccent,
              icon: const Icon(Icons.add_alert, color: Colors.white),
              label: const Text('CREATE ALERT', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
            ),
    );
  }

  Widget _buildAlertCard(PublicAlert alert, bool isSelected) {
    return Card(
      color: isSelected ? Colors.blueAccent.withValues(alpha: 0.2) : Colors.black,
      shape: RoundedRectangleBorder(
        side: BorderSide(
          color: isSelected ? Colors.blueAccent : Color(alert.severity.colorValue),
          width: isSelected ? 2 : 1,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        contentPadding: const EdgeInsets.all(16),
        title: Text(
          alert.severity.label,
          style: TextStyle(
            color: Color(alert.severity.colorValue),
            fontWeight: FontWeight.bold,
            fontSize: 12,
            letterSpacing: 1.2,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 8),
            Text(
              alert.text,
              style: const TextStyle(color: Colors.white, fontSize: 16),
            ),
            const SizedBox(height: 8),
            Text(
              'Received: ${alert.createdAt.hour}:${alert.createdAt.minute.toString().padLeft(2, '0')}',
              style: const TextStyle(color: Colors.grey, fontSize: 10),
            ),
          ],
        ),
        trailing: isSelected ? const Icon(Icons.check_circle, color: Colors.blueAccent) : null,
      ),
    );
  }

  void _showAlertDetails(BuildContext context, PublicAlert alert) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(alert.severity.label, style: TextStyle(color: Color(alert.severity.colorValue))),
        content: Text(alert.text, style: const TextStyle(fontSize: 18)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('CLOSE')),
        ],
      ),
    );
  }

  void _showCreateAlertModal(BuildContext context, WidgetRef ref) {
    final textController = TextEditingController();
    AlertSeverity selectedSeverity = AlertSeverity.medium;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1E1E1E),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
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
                  const Text('NEW PUBLIC ALERT', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.redAccent)),
                  const SizedBox(height: 16),
                  TextField(
                    controller: textController,
                    autofocus: true,
                    decoration: const InputDecoration(
                      hintText: 'Describe the emergency...',
                      border: OutlineInputBorder(),
                    ),
                    maxLines: 2,
                  ),
                  const SizedBox(height: 16),
                  const Text('SEVERITY', style: TextStyle(fontSize: 12, color: Colors.grey)),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: AlertSeverity.values.map((s) {
                      final isSelected = selectedSeverity == s;
                      return ChoiceChip(
                        label: Text(s.label),
                        selected: isSelected,
                        selectedColor: Color(s.colorValue),
                        onSelected: (_) => setModalState(() => selectedSeverity = s),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
                      onPressed: () {
                        if (textController.text.isNotEmpty) {
                          ref.read(alertProvider.notifier).addAlert(textController.text, selectedSeverity);
                          Navigator.pop(ctx);
                        }
                      },
                      child: const Text('BROADCAST TO MESH', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    ),
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _openScanner(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (ctx) => Scaffold(
          appBar: AppBar(title: const Text('IMPORT ALERTS')),
          body: MobileScanner(
            onDetect: (capture) {
              final barcodes = capture.barcodes;
              for (final barcode in barcodes) {
                final raw = barcode.rawValue;
                if (raw != null && raw.startsWith('SPY_MESH_ALERTS:')) {
                  try {
                    final jsonStr = raw.replaceFirst('SPY_MESH_ALERTS:', '');
                    final List<dynamic> data = jsonDecode(jsonStr);
                    final alerts = data.map((a) => PublicAlert.fromJson(Map<String, dynamic>.from(a))).toList();
                    
                    ref.read(alertProvider.notifier).syncFromPeer(alerts);
                    
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Imported ${alerts.length} Alerts from QR')),
                    );
                    break;
                  } catch (e) {
                    print('[Scanner] Import failed: $e');
                  }
                }
              }
            },
          ),
        ),
      ),
    );
  }

  void _showBundleQr(BuildContext context, List<PublicAlert> allAlerts) {
    final selectedAlerts = allAlerts.where((a) => _selectedAlertIds.contains(a.id)).toList();
    
    // Create dual-purpose payload: Human-readable header + App-optimized footer
    final jsonPart = jsonEncode(selectedAlerts.map((a) => a.toJson()).toList());
    final bundleText = 'SPY_MESH_ALERTS:$jsonPart';

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('DEAD DROP QR', textAlign: TextAlign.center),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Anyone who scans this with the app will instantly import your alerts.', 
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 16),
            SizedBox(
              width: 250,
              height: 250,
              child: QrImageView(
                data: bundleText,
                version: QrVersions.auto,
                backgroundColor: Colors.white,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('DONE')),
        ],
      ),
    );
  }
}

