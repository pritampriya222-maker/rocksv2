import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../core/models/public_alert.dart';
import '../../core/models/dead_drop_bundle.dart';
import '../../core/models/news_post.dart';
import '../../core/models/safe_route.dart';
import '../../providers/alert_providers.dart';
import '../../providers/news_providers.dart';
import '../../providers/route_providers.dart';

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
                  tooltip: 'Create Dead Drop QR',
                  onPressed: () => _showDeadDropQr(context),
                ),
              ],
            )
          : AppBar(
              title: const Text('EMERGENCY ALERTS'),
              actions: [
                IconButton(
                  icon: const Icon(Icons.qr_code_scanner),
                  tooltip: 'Scan Dead Drop',
                  onPressed: () => _openDeadDropScanner(context),
                ),
              ],
            ),

      body: alerts.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.shield_outlined, size: 64, color: Colors.grey[700]),
                  const SizedBox(height: 16),
                  const Text(
                    'NO ACTIVE ALERTS',
                    style: TextStyle(
                      color: Colors.grey,
                      fontSize: 12,
                      letterSpacing: 2,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Create an alert or receive from mesh peers',
                    style: TextStyle(color: Colors.grey, fontSize: 11),
                  ),
                ],
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
              label: const Text('ALERT', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
            ),
    );
  }

  Widget _buildAlertCard(PublicAlert alert, bool isSelected) {
    final severityColor = Color(alert.severity.colorValue);
    final timeDiff = DateTime.now().difference(alert.createdAt);
    final timeStr = timeDiff.inMinutes < 1
        ? 'Just now'
        : timeDiff.inMinutes < 60
            ? '${timeDiff.inMinutes}m ago'
            : '${timeDiff.inHours}h ago';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isSelected
            ? Colors.blueAccent.withValues(alpha: 0.1)
            : const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isSelected
              ? Colors.blueAccent
              : severityColor.withValues(alpha: 0.3),
          width: isSelected ? 2 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Severity header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: severityColor.withValues(alpha: 0.08),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(11)),
            ),
            child: Row(
              children: [
                Icon(
                  alert.severity == AlertSeverity.high
                      ? Icons.error
                      : alert.severity == AlertSeverity.medium
                          ? Icons.warning
                          : Icons.info,
                  color: severityColor,
                  size: 16,
                ),
                const SizedBox(width: 8),
                Text(
                  alert.severity.label,
                  style: TextStyle(
                    color: severityColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                    letterSpacing: 1.2,
                  ),
                ),
                const Spacer(),
                Text(
                  timeStr,
                  style: const TextStyle(color: Colors.grey, fontSize: 10),
                ),
                if (isSelected) ...[
                  const SizedBox(width: 8),
                  const Icon(Icons.check_circle, color: Colors.blueAccent, size: 16),
                ],
              ],
            ),
          ),
          // Alert body
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              alert.text,
              style: const TextStyle(color: Colors.white, fontSize: 15),
            ),
          ),
        ],
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
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
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
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.redAccent.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.warning_amber,
                            color: Colors.redAccent, size: 20),
                      ),
                      const SizedBox(width: 12),
                      const Text('EMERGENCY ALERT',
                          style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.redAccent)),
                    ],
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: textController,
                    autofocus: true,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      hintText: 'Describe the emergency...',
                      border: OutlineInputBorder(),
                    ),
                    maxLines: 2,
                  ),
                  const SizedBox(height: 16),
                  const Text('SEVERITY',
                      style: TextStyle(fontSize: 11, color: Colors.grey, letterSpacing: 1)),
                  const SizedBox(height: 8),
                  Row(
                    children: AlertSeverity.values.map((s) {
                      final isSelected = selectedSeverity == s;
                      final sColor = Color(s.colorValue);
                      return Expanded(
                        child: GestureDetector(
                          onTap: () => setModalState(() => selectedSeverity = s),
                          child: Container(
                            margin: EdgeInsets.only(
                                right: s != AlertSeverity.high ? 8 : 0),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? sColor.withValues(alpha: 0.2)
                                  : Colors.white.withValues(alpha: 0.05),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: isSelected
                                    ? sColor
                                    : Colors.white.withValues(alpha: 0.1),
                                width: isSelected ? 2 : 1,
                              ),
                            ),
                            child: Center(
                              child: Text(
                                s.label,
                                style: TextStyle(
                                  color: isSelected ? sColor : Colors.grey,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.redAccent,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: () {
                        if (textController.text.isNotEmpty) {
                          ref.read(alertProvider.notifier).addAlert(textController.text, selectedSeverity);
                          Navigator.pop(ctx);
                        }
                      },
                      child: const Text('BROADCAST ALERT',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
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
                    final data = jsonDecode(jsonStr) as List<dynamic>;
                    final alerts = data.map((a) => PublicAlert.fromJson(Map<String, dynamic>.from(a as Map))).toList();
                    
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

  void _showDeadDropQr(BuildContext context) {
    try {
      final selectedAlerts = ref.read(alertProvider)
          .where((a) => _selectedAlertIds.contains(a.id))
          .toList();
      
      final bool isSelectionMode = selectedAlerts.isNotEmpty;
      
      final news = isSelectionMode ? <NewsPost>[] : ref.read(newsProvider);
      final routes = isSelectionMode ? <SafeRoute>[] : ref.read(routeProvider);

      // TRUNCATE TEXT: To ensure the QR code never fails and is instantly scannable,
      // we truncate the alert text to 40 characters. It acts as a lightweight preview.
      // The full text is automatically fetched via the background TCP Mesh.
      List<PublicAlert> truncateAlerts(List<PublicAlert> input) {
        return input.map((a) => PublicAlert(
          id: a.id,
          text: a.text.length > 40 ? '${a.text.substring(0, 40)}...' : a.text,
          severity: a.severity,
          createdAt: a.createdAt,
        )).toList();
      }

      final bundle = DeadDropBundle(
        alerts: isSelectionMode ? truncateAlerts(selectedAlerts) : truncateAlerts(ref.read(alertProvider).take(5).toList()),
        news: news.length > 5 ? news.sublist(0, 5) : news,
        routes: routes.length > 5 ? routes.sublist(0, 5) : routes,
      );

      final encoded = bundle.encode();
      final bool isTooLarge = encoded.length > 2800; // QR physical limit

      showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF1E1E1E),
          title: Row(
            children: [
              Icon(Icons.qr_code_2, color: isTooLarge ? Colors.orangeAccent : Colors.blueAccent),
              const SizedBox(width: 8),
              Text(isTooLarge ? 'DATA TOO LARGE' : 'DEAD DROP QR', style: const TextStyle(fontSize: 16)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isTooLarge) ...[
                const Icon(Icons.warning_amber_rounded, size: 48, color: Colors.orangeAccent),
                const SizedBox(height: 12),
                const Text(
                  'You have too much data selected to fit in a single QR code. Try selecting fewer alerts.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey, fontSize: 13),
                ),
              ] else ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${bundle.totalItems} items bundled • ${encoded.length} chars',
                    style: const TextStyle(color: Colors.grey, fontSize: 10),
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Anyone with this app can scan and import this bundle.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 11, color: Colors.grey),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: SizedBox(
                    width: 240,
                    height: 240,
                    child: QrImageView(
                      data: encoded,
                      version: QrVersions.auto,
                      errorCorrectionLevel: QrErrorCorrectLevel.L,
                      errorStateBuilder: (cxt, err) {
                        return Center(
                          child: Text(
                            'Data too complex for QR\n$err',
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.red, fontSize: 12),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                setState(() {
                  _isSelectionMode = false;
                  _selectedAlertIds.clear();
                });
              },
              child: const Text('DONE'),
            ),
          ],
        ),
      );
    } catch (e) {
      print('[QR Error] $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to generate QR: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  /// Scanner that handles Dead Drop bundles
  void _openDeadDropScanner(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (ctx) => Scaffold(
          appBar: AppBar(title: const Text('SCAN DEAD DROP')),
          body: MobileScanner(
            onDetect: (capture) {
              for (final barcode in capture.barcodes) {
                final raw = barcode.rawValue;
                if (raw == null || raw.isEmpty) continue;

                // Try Dead Drop bundle first
                try {
                  final bundle = DeadDropBundle.decode(raw);
                  if (bundle.alerts.isNotEmpty) {
                    ref.read(alertProvider.notifier).syncFromPeer(bundle.alerts);
                  }
                  if (bundle.news.isNotEmpty) {
                    ref.read(newsProvider.notifier).syncFromPeer(bundle.news);
                  }
                  if (bundle.routes.isNotEmpty) {
                    ref.read(routeProvider.notifier).syncFromPeer(bundle.routes);
                  }

                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                          'Imported Dead Drop: ${bundle.alerts.length} alerts, ${bundle.news.length} news, ${bundle.routes.length} routes'),
                    ),
                  );
                  return;
                } catch (_) {}

                // Try legacy alert format
                if (raw.startsWith('SPY_MESH_ALERTS:')) {
                  try {
                    final jsonStr = raw.replaceFirst('SPY_MESH_ALERTS:', '');
                    final data = jsonDecode(jsonStr) as List<dynamic>;
                    final alerts = data
                        .map((a) => PublicAlert.fromJson(
                            Map<String, dynamic>.from(a as Map)))
                        .toList();
                    ref.read(alertProvider.notifier).syncFromPeer(alerts);
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                          content:
                              Text('Imported ${alerts.length} Alerts')),
                    );
                    return;
                  } catch (_) {}
                }
              }
            },
          ),
        ),
      ),
    );
  }
}
