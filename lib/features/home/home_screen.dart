import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/app_theme.dart';
import '../../core/app_router.dart';
import '../../providers/ble_providers.dart';
import '../../providers/crypto_providers.dart';

/// Home screen — system status hub and navigation entry point.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  @override
  void initState() {
    super.initState();
    // Start scanning + advertising on home screen open
    WidgetsBinding.instance.addPostFrameCallback((_) => _initBle());
  }

  Future<void> _initBle() async {
    final bleMgr = ref.read(bleManagerProvider);
    final keyRotation = ref.read(keyRotationProvider);

    // Subscribe to rotation: update BLE advertisement whenever UUID rotates
    keyRotation.onRotation.listen((newPubKey) async {
      final bridge = ref.read(blePeripheralBridgeProvider);
      await bridge.updatePubKey(newPubKey);
    });

    // Start advertising with current pubkey
    final ecdh = ref.read(ecdhManagerProvider);
    final pubKey = ecdh.getCurrentPublicKeyBytes();
    final bridge = ref.read(blePeripheralBridgeProvider);
    await bridge.startAdvertising(
      pubKeyBytes: pubKey,
      ephemeralUuid: DateTime.now().millisecondsSinceEpoch.toString(),
    );

    // Start scanning for peers
    await bleMgr.startScanning();
  }

  @override
  Widget build(BuildContext context) {
    final peersAsync = ref.watch(connectedPeersProvider);
    final peerCount = peersAsync.valueOrNull?.length ?? 0;

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('OFFLINE MESH'),
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: 14),
            child: Center(
              child: Text(
                'BLE ACTIVE',
                style: TextStyle(
                  color: AppTheme.success,
                  fontSize: 10,
                  letterSpacing: 1.2,
                ),
              ),
            ),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _StatusGrid(peerCount: peerCount),
            const SizedBox(height: 28),
            const _SectionLabel('ACTIONS'),
            const SizedBox(height: 12),
            const _NavCard(
              label: '[ COMPOSE MESSAGE ]',
              subtitle: 'Encrypt · Fragment · Broadcast',
              route: AppRouter.messaging,
              icon: Icons.edit_outlined,
            ),
            const SizedBox(height: 10),
            _NavCard(
              label: '[ PEER NETWORK ]',
              subtitle: 'BLE discovery · ECDH · Relay status',
              route: AppRouter.peers,
              icon: Icons.wifi_tethering,
              badge: peerCount > 0 ? '$peerCount' : null,
            ),
            const SizedBox(height: 10),
            const _NavCard(
              label: '[ QR RELAY ]',
              subtitle: 'Air-gapped fallback · Scan & relay',
              route: AppRouter.qr,
              icon: Icons.qr_code_2,
            ),
            const Spacer(),
            _IdentityFooter(),
          ],
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Status grid
// -----------------------------------------------------------------------------

class _StatusGrid extends StatelessWidget {
  final int peerCount;
  const _StatusGrid({required this.peerCount});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const _StatusCell(
                label: 'NETWORK',
                value: 'OFFLINE',
                color: AppTheme.error,
              ),
              const _VertDivider(),
              const _StatusCell(
                label: 'BLE',
                value: 'ACTIVE',
                color: AppTheme.success,
              ),
              const _VertDivider(),
              _StatusCell(
                label: 'PEERS',
                value: '$peerCount',
                color: peerCount > 0 ? AppTheme.success : AppTheme.warning,
              ),
            ],
          ),
          const Divider(height: 16),
          const Row(
            children: [
              Icon(Icons.lock, color: AppTheme.success, size: 12),
              SizedBox(width: 6),
              Text(
                'X25519 + AES-256-GCM + HMAC-SHA256  •  ZERO PERSISTENCE',
                style: TextStyle(
                  color: AppTheme.textHint,
                  fontSize: 9,
                  letterSpacing: 0.8,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatusCell extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _StatusCell(
      {required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(label,
              style: const TextStyle(
                  color: AppTheme.textHint,
                  fontSize: 9,
                  letterSpacing: 1)),
          const SizedBox(height: 4),
          Text(value,
              style: TextStyle(
                  color: color,
                  fontSize: 16,
                  fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}

class _VertDivider extends StatelessWidget {
  const _VertDivider();

  @override
  Widget build(BuildContext context) {
    return Container(width: 1, height: 30, color: AppTheme.border);
  }
}

// -----------------------------------------------------------------------------
// Nav card
// -----------------------------------------------------------------------------

class _NavCard extends StatelessWidget {
  final String label;
  final String subtitle;
  final String route;
  final IconData icon;
  final String? badge;

  const _NavCard({
    required this.label,
    required this.subtitle,
    required this.route,
    required this.icon,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.pushNamed(context, route),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: AppTheme.border),
        ),
        child: Row(
          children: [
            Icon(icon, color: AppTheme.accent, size: 20),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: const TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.4)),
                  const SizedBox(height: 3),
                  Text(subtitle,
                      style: const TextStyle(
                          color: AppTheme.textSecondary, fontSize: 11)),
                ],
              ),
            ),
            if (badge != null)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AppTheme.success.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppTheme.success),
                ),
                child: Text(badge!,
                    style: const TextStyle(
                        color: AppTheme.success, fontSize: 11)),
              ),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right,
                color: AppTheme.textHint, size: 18),
          ],
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Section label
// -----------------------------------------------------------------------------

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(text,
        style: const TextStyle(
            color: AppTheme.textHint,
            fontSize: 9,
            letterSpacing: 1.8));
  }
}

// -----------------------------------------------------------------------------
// Identity footer
// -----------------------------------------------------------------------------

class _IdentityFooter extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return const Text(
      'EPHEMERAL IDENTITY  •  ROTATES EVERY 30s  •  AIR-GAPPED',
      textAlign: TextAlign.center,
      style: TextStyle(
        color: AppTheme.textHint,
        fontSize: 9,
        letterSpacing: 1.4,
      ),
    );
  }
}
