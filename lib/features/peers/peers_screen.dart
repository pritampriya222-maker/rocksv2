import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/app_theme.dart';
import '../../core/models/ephemeral_peer.dart';
import '../../providers/ble_providers.dart';

/// Peers screen — shows live BLE peer list and connection status.
class PeersScreen extends ConsumerWidget {
  const PeersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final peersAsync = ref.watch(connectedPeersProvider);

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('PEER NETWORK'),
        actions: [
          _ScanToggleButton(),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _StatusBar(peersAsync: peersAsync),
          const Divider(height: 1),
          Expanded(
            child: peersAsync.when(
              loading: () => const _ScanningIndicator(),
              error: (e, _) => _ErrorView(message: e.toString()),
              data: (peers) => peers.isEmpty
                  ? const _EmptyState()
                  : _PeerList(peers: peers),
            ),
          ),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Status bar
// -----------------------------------------------------------------------------

class _StatusBar extends StatelessWidget {
  final AsyncValue<List<EphemeralPeer>> peersAsync;
  const _StatusBar({required this.peersAsync});

  @override
  Widget build(BuildContext context) {
    final count = peersAsync.valueOrNull?.length ?? 0;
    return Container(
      width: double.infinity,
      color: AppTheme.surface,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              color: count > 0 ? AppTheme.success : AppTheme.warning,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 10),
          Text(
            count > 0
                ? '$count PEER${count == 1 ? '' : 'S'} CONNECTED'
                : 'SCANNING FOR PEERS…',
            style: const TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 11,
              letterSpacing: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Scan toggle button
// -----------------------------------------------------------------------------

class _ScanToggleButton extends ConsumerStatefulWidget {
  @override
  ConsumerState<_ScanToggleButton> createState() => _ScanToggleButtonState();
}

class _ScanToggleButtonState extends ConsumerState<_ScanToggleButton> {
  bool _scanning = false;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: _toggle,
      icon: Icon(
        _scanning ? Icons.stop : Icons.search,
        size: 16,
        color: _scanning ? AppTheme.error : AppTheme.accent,
      ),
      label: Text(
        _scanning ? 'STOP' : 'SCAN',
        style: TextStyle(
          fontSize: 11,
          color: _scanning ? AppTheme.error : AppTheme.accent,
          letterSpacing: 1,
        ),
      ),
    );
  }

  Future<void> _toggle() async {
    final mgr = ref.read(bleManagerProvider);
    if (_scanning) {
      await mgr.stopScanning();
    } else {
      await mgr.startScanning();
    }
    if (mounted) setState(() => _scanning = !_scanning);
  }
}

// -----------------------------------------------------------------------------
// Peer list
// -----------------------------------------------------------------------------

class _PeerList extends StatelessWidget {
  final List<EphemeralPeer> peers;
  const _PeerList({required this.peers});

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: peers.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) => _PeerTile(peer: peers[i]),
    );
  }
}

class _PeerTile extends StatelessWidget {
  final EphemeralPeer peer;
  const _PeerTile({required this.peer});

  @override
  Widget build(BuildContext context) {
    final rssiColor = peer.rssi > -60
        ? AppTheme.success
        : peer.rssi > -80
            ? AppTheme.warning
            : AppTheme.error;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        children: [
          const Icon(Icons.bluetooth_connected,
              color: AppTheme.accent, size: 18),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _shortId(peer.deviceUuid),
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  peer.isKeyExchangeComplete
                      ? 'KEY EXCHANGE COMPLETE'
                      : 'AWAITING KEY EXCHANGE',
                  style: TextStyle(
                    color: peer.isKeyExchangeComplete
                        ? AppTheme.success
                        : AppTheme.warning,
                    fontSize: 10,
                    letterSpacing: 0.8,
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${peer.rssi} dBm',
                style: TextStyle(
                  color: rssiColor,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                _relativeTime(peer.discoveredAt),
                style: const TextStyle(
                  color: AppTheme.textHint,
                  fontSize: 10,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _shortId(String uuid) {
    if (uuid.length > 17) return uuid.substring(0, 17).toUpperCase();
    return uuid.toUpperCase();
  }

  String _relativeTime(DateTime t) {
    final diff = DateTime.now().difference(t);
    if (diff.inSeconds < 60) return '${diff.inSeconds}s ago';
    return '${diff.inMinutes}m ago';
  }
}

// -----------------------------------------------------------------------------
// Empty / loading states
// -----------------------------------------------------------------------------

class _ScanningIndicator extends StatelessWidget {
  const _ScanningIndicator();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: AppTheme.accent,
            ),
          ),
          SizedBox(height: 16),
          Text(
            'SCANNING FOR MESH PEERS…',
            style: TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 11,
              letterSpacing: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.wifi_off, color: AppTheme.textHint, size: 48),
          SizedBox(height: 16),
          Text(
            'NO PEERS FOUND',
            style: TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 13,
              letterSpacing: 1.5,
            ),
          ),
          SizedBox(height: 8),
          Text(
            'Ensure nearby devices have the app open\nand Bluetooth enabled.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppTheme.textHint, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  const _ErrorView({required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        'BLE ERROR: $message',
        style: const TextStyle(color: AppTheme.error, fontSize: 12),
        textAlign: TextAlign.center,
      ),
    );
  }
}
