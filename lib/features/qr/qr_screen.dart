import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../core/app_theme.dart';
import '../../core/models/message_fragment.dart';
import '../../providers/crypto_providers.dart';
import '../../providers/network_providers.dart';
import '../../providers/messaging_providers.dart';
import '../../providers/qr_providers.dart';



/// QR Relay screen — two modes:
///
/// **Generate mode**: Type message → encrypt → display 3 QR codes (one per fragment).
///   The recipient scans each QR with their camera.
///
/// **Scan mode**: Scan a QR code → parse fragment → relay via BLE (or collect all 3).
///
/// QR payload per fragment:
///   Base64url-encoded JSON from [MessageFragment.toJsonString()]
///
/// This is the air-gapped fallback for when BLE is unavailable.
class QrScreen extends ConsumerStatefulWidget {
  const QrScreen({super.key});

  @override
  ConsumerState<QrScreen> createState() => _QrScreenState();
}

class _QrScreenState extends ConsumerState<QrScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('QR RELAY'),
        bottom: TabBar(
          controller: _tabs,
          indicatorColor: AppTheme.accent,
          labelColor: AppTheme.textPrimary,
          unselectedLabelColor: AppTheme.textSecondary,
          labelStyle: const TextStyle(
            fontSize: 11,
            letterSpacing: 1.2,
            fontFamily: 'RobotoMono',
          ),
          tabs: const [
            Tab(text: '[ GENERATE ]'),
            Tab(text: '[ SCAN ]'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: const [
          _GenerateTab(),
          _ScanTab(),
        ],
      ),
    );
  }
}

// =============================================================================
// GENERATE TAB
// =============================================================================

class _GenerateTab extends ConsumerStatefulWidget {
  const _GenerateTab();

  @override
  ConsumerState<_GenerateTab> createState() => _GenerateTabState();
}

class _GenerateTabState extends ConsumerState<_GenerateTab> {
  final _controller = TextEditingController();
  List<MessageFragment>? _fragments;
  int _displayIndex = 0;
  bool _generating = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _generate() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    setState(() {
      _generating = true;
      _error = null;
      _fragments = null;
      _displayIndex = 0;
    });

    try {
      final peers = ref.read(connectedPeersProvider).valueOrNull ?? [];
      if (peers.isEmpty) {
        // No BLE peers — generate with a local ephemeral key
        // The receiver must manually enter the session key (or use pre-shared)
        // For the demo: we generate the session key from the local identity
        // In production: show a key QR separately
        throw Exception(
          'At least one peer must be in your Wi-Fi Mesh to exchange keys.',
        );

      }

      final activePeer = peers.firstWhere(
        (p) => p.isKeyExchangeComplete,
        orElse: () =>
            throw Exception('No peer with completed key exchange found.'),
      );

      final ecdh = ref.read(ecdhManagerProvider);
      final fragmentSvc = ref.read(fragmentServiceProvider);

      final sessionKey = await ecdh.deriveSessionKey(
        remotePublicKeyBytes: activePeer.ecdhPublicKey,
      );

      final plaintextBytes = Uint8List.fromList(utf8.encode(text));
      final fragments = await fragmentSvc.createFragments(
        plaintext: plaintextBytes,
        sessionKey: sessionKey,
      );

      setState(() => _fragments = fragments);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }


  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _SectionLabel('PLAINTEXT MESSAGE'),
          const SizedBox(height: 8),
          TextField(
            controller: _controller,
            maxLines: 3,
            style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14),
            decoration: const InputDecoration(
              hintText: 'Type message to encrypt into QR fragments…',
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 44,
            child: ElevatedButton(
              onPressed: _generating ? null : _generate,
              child: _generating
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: AppTheme.accent),
                    )
                  : const Text('[ GENERATE QR FRAGMENTS ]',
                      style: TextStyle(fontSize: 11, letterSpacing: 0.8)),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!,
                style: const TextStyle(color: AppTheme.error, fontSize: 11)),
          ],
          if (_fragments != null) ...[
            const SizedBox(height: 24),
            _FragmentQrViewer(
              fragments: _fragments!,
              currentIndex: _displayIndex,
              onIndexChanged: (i) => setState(() => _displayIndex = i),
            ),
          ],
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------

class _FragmentQrViewer extends ConsumerWidget {
  final List<MessageFragment> fragments;
  final int currentIndex;
  final ValueChanged<int> onIndexChanged;

  const _FragmentQrViewer({
    required this.fragments,
    required this.currentIndex,
    required this.onIndexChanged,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {

    final fragment = fragments[currentIndex];
    final qrMgr = ref.watch(qrPayloadManagerProvider);
    final qrData = qrMgr.encodeForQr(jsonDecode(fragment.toJsonString()) as Map<String, dynamic>);



    return Column(
      children: [
        Row(
          children: List.generate(3, (i) {
            final active = i == currentIndex;
            return Expanded(
              child: GestureDetector(
                onTap: () => onIndexChanged(i),
                child: Container(
                  margin: EdgeInsets.only(right: i < 2 ? 8 : 0),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    color: active ? AppTheme.surfaceAlt : AppTheme.surface,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: active ? AppTheme.accent : AppTheme.border,
                    ),
                  ),
                  child: Text(
                    'SHARD ${i + 1}',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: active ? AppTheme.accent : AppTheme.textSecondary,
                      fontSize: 11,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
              ),
            );
          }),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
          ),
          child: QrImageView(
            data: qrData,
            version: QrVersions.auto,
            errorCorrectionLevel: QrErrorCorrectLevel.M,
            size: 240,
            backgroundColor: Colors.white,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'FRAGMENT ${currentIndex + 1}/3  •  '
          '${qrData.length} CHARS  •  '
          'SHOW ALL 3 TO RECIPIENT',
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: AppTheme.textSecondary,
            fontSize: 10,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _NavBtn(
              label: '◀ PREV',
              onTap: currentIndex > 0
                  ? () => onIndexChanged(currentIndex - 1)
                  : null,
            ),
            const SizedBox(width: 16),
            _NavBtn(
              label: 'NEXT ▶',
              onTap: currentIndex < 2
                  ? () => onIndexChanged(currentIndex + 1)
                  : null,
            ),
          ],
        ),
      ],
    );
  }
}

class _NavBtn extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  const _NavBtn({required this.label, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: onTap != null ? AppTheme.border : AppTheme.textHint,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: onTap != null ? AppTheme.textPrimary : AppTheme.textHint,
            fontSize: 11,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// SCAN TAB
// =============================================================================

class _ScanTab extends ConsumerStatefulWidget {
  const _ScanTab();

  @override
  ConsumerState<_ScanTab> createState() => _ScanTabState();
}

class _ScanTabState extends ConsumerState<_ScanTab> {
  final _scannedFragments = <int, MessageFragment>{};
  String? _lastStatus;
  bool _scannerActive = true;
  MobileScannerController? _scannerController;

  @override
  void initState() {
    super.initState();
    _scannerController = MobileScannerController();
  }

  @override
  void dispose() {
    _scannerController?.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (!_scannerActive) return;

    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue;
      if (raw == null || raw.isEmpty) continue;

      try {
        final qrMgr = ref.read(qrPayloadManagerProvider);
        final map = qrMgr.decodeFromQr(raw);
        final fragment = MessageFragment.fromJsonString(jsonEncode(map));

        if (_scannedFragments.containsKey(fragment.index)) continue;
        
        setState(() {
          _scannedFragments[fragment.index] = fragment;
          _lastStatus =
              'SHARD ${fragment.index + 1}/3 CAPTURED  '
              '(${_scannedFragments.length}/3 total)';
        });



        if (_scannedFragments.length == 3) {
          _relayAllFragments();
          break;
        }
      } catch (_) {
        // Silently ignore invalid mesh fragments to prevent status spam
      }
    }
  }


  Future<void> _relayAllFragments() async {
    setState(() {
      _scannerActive = false;
      _lastStatus = 'ALL 3 SHARDS CAPTURED — relaying via Wi-Fi Mesh…';

    });

    final sorted = [0, 1, 2].map((i) => _scannedFragments[i]!).toList();


    for (final fragment in sorted) {
      // 1. Relay via Wi-Fi Mesh
      await ref.read(wifiMeshManagerProvider).broadcastFragment(fragment);
      
      final peers = ref.read(connectedPeersProvider).valueOrNull ?? [];
      final ecdh = ref.read(ecdhManagerProvider);
      ref.read(messagingControllerProvider.notifier).onFragmentReceived(fragment, peers, ecdh);



      
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }


    if (mounted) {
      setState(() => _lastStatus = '✓ ALL 3 FRAGMENTS RELAYED VIA MESH');

      _scannedFragments.clear();
    }
  }

  void _reset() {
    setState(() {
      _scannedFragments.clear();
      _lastStatus = null;
      _scannerActive = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Scanner viewport
        Expanded(
          flex: 3,
          child: _scannerActive
              ? MobileScanner(
                  controller: _scannerController,
                  onDetect: _onDetect,
                )
              : Container(
                  color: AppTheme.surface,
                  child: const Center(
                    child: Icon(Icons.check_circle_outline,
                        color: AppTheme.success, size: 64),
                  ),
                ),
        ),

        // Status panel
        Expanded(
          flex: 2,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Shard progress indicators
                Row(
                  children: List.generate(3, (i) {
                    final captured = _scannedFragments.containsKey(i);
                    return Expanded(
                      child: Container(
                        margin: EdgeInsets.only(right: i < 2 ? 8 : 0),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: captured
                              ? AppTheme.success.withValues(alpha: 0.15)
                              : AppTheme.surface,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: captured
                                ? AppTheme.success
                                : AppTheme.border,
                          ),
                        ),
                        child: Column(
                          children: [
                            Icon(
                              captured
                                  ? Icons.check
                                  : Icons.qr_code_scanner,
                              color: captured
                                  ? AppTheme.success
                                  : AppTheme.textHint,
                              size: 18,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'SHARD ${i + 1}',
                              style: TextStyle(
                                color: captured
                                    ? AppTheme.success
                                    : AppTheme.textHint,
                                fontSize: 10,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                ),

                const SizedBox(height: 14),

                if (_lastStatus != null)
                  Text(
                    _lastStatus!,
                    style: const TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 12,
                    ),
                    textAlign: TextAlign.center,
                  ),

                const Spacer(),

                if (!_scannerActive)
                  ElevatedButton(
                    onPressed: _reset,
                    child: const Text(
                      '[ SCAN ANOTHER MESSAGE ]',
                      style: TextStyle(fontSize: 11, letterSpacing: 0.8),
                    ),
                  ),

                if (_scannerActive)
                  const Text(
                    'SCAN ALL 3 QR SHARDS FROM THE SENDER',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppTheme.textHint,
                      fontSize: 10,
                      letterSpacing: 1,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// =============================================================================
// HELPERS
// =============================================================================

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        color: AppTheme.textSecondary,
        fontSize: 10,
        letterSpacing: 1.5,
      ),
    );
  }
}
