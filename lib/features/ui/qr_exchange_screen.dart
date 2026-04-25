import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';

// Mock providers for UI compilation as per the prompt instructions.
final qrPayloadManagerProvider = Provider<dynamic>((ref) => throw UnimplementedError());
final messageStateNotifierProvider = Provider<dynamic>((ref) => throw UnimplementedError());

// Mock outgoing fragments list
final outgoingFragmentsProvider = StateProvider<List<String>>((ref) => [
  'MOCK_BASE64_GZIP_FRAGMENT_0',
  'MOCK_BASE64_GZIP_FRAGMENT_1',
  'MOCK_BASE64_GZIP_FRAGMENT_2',
]);

/// Handles the air-gapped manual exchange of encrypted fragments.
class QrExchangeScreen extends ConsumerStatefulWidget {
  const QrExchangeScreen({super.key});

  @override
  ConsumerState<QrExchangeScreen> createState() => _QrExchangeScreenState();
}

class _QrExchangeScreenState extends ConsumerState<QrExchangeScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  int _currentFragmentIndex = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('QR Air-Gapped Relay'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.qr_code_scanner), text: 'SCAN'),
            Tab(icon: Icon(Icons.qr_code_2), text: 'SHOW'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildScanTab(context),
          _buildShowTab(context),
        ],
      ),
    );
  }

  Widget _buildScanTab(BuildContext context) {
    return Column(
      children: [
        const Padding(
          padding: EdgeInsets.all(16.0),
          child: Text(
            'Scan all 3 fragments from the sender device to reassemble the message offline.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey),
          ),
        ),
        Expanded(
          child: MobileScanner(
            onDetect: (capture) {
              final List<Barcode> barcodes = capture.barcodes;
              for (final barcode in barcodes) {
                final rawData = barcode.rawValue;
                if (rawData != null && rawData.isNotEmpty) {
                  _handleScannedData(rawData);
                }
              }
            },
          ),
        ),
      ],
    );
  }

  void _handleScannedData(String base64QrData) {
    try {
      // 1. Decode payload via QrPayloadManager
      // final payloadManager = ref.read(qrPayloadManagerProvider);
      // final fragmentJson = payloadManager.decodeFromQr(base64QrData);
      
      // 2. Parse into EncryptedFragment model
      // final fragment = EncryptedFragment.fromJson(fragmentJson);
      
      // 3. Push to MessageStateNotifier
      // ref.read(messageStateNotifierProvider).onFragmentReceived(fragment);
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Fragment captured successfully!'), backgroundColor: Colors.green),
      );
      
      // If all 3 are collected, navigate back (handled by state provider logic usually)
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Invalid QR: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Widget _buildShowTab(BuildContext context) {
    final fragments = ref.watch(outgoingFragmentsProvider);

    if (fragments.isEmpty) {
      return const Center(child: Text('No outgoing message fragments to show.'));
    }

    final currentPayload = fragments[_currentFragmentIndex];

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          'FRAGMENT ${_currentFragmentIndex + 1} OF 3',
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 2),
        ),
        const SizedBox(height: 8),
        const Text(
          'Recipient must scan all 3 sequentially.',
          style: TextStyle(color: Colors.grey),
        ),
        const SizedBox(height: 32),
        
        // High-density QR Display
        Container(
          padding: const EdgeInsets.all(16),
          color: Colors.white,
          child: QrImageView(
            data: currentPayload,
            version: QrVersions.auto,
            errorCorrectionLevel: QrErrorCorrectLevel.M,
            size: 280.0,
          ),
        ),
        
        const SizedBox(height: 48),
        
        // Navigation Controls
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            ElevatedButton.icon(
              onPressed: _currentFragmentIndex > 0
                  ? () => setState(() => _currentFragmentIndex--)
                  : null,
              icon: const Icon(Icons.arrow_back),
              label: const Text('PREV'),
            ),
            ElevatedButton.icon(
              onPressed: _currentFragmentIndex < fragments.length - 1
                  ? () => setState(() => _currentFragmentIndex++)
                  : null,
              icon: const Icon(Icons.arrow_forward),
              label: const Text('NEXT'),
            ),
          ],
        ),
      ],
    );
  }
}
