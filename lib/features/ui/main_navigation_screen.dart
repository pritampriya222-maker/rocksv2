import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'home_screen.dart';
import 'public_broadcast_screen.dart';
import 'peer_list_screen.dart';
import '../../providers/network_providers.dart';
import '../../core/security/anti_forensics_service.dart';

class MainNavigationScreen extends ConsumerStatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  ConsumerState<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends ConsumerState<MainNavigationScreen> with WidgetsBindingObserver {
  final List<Widget> _screens = const [
    HomeScreen(),
    PeerListScreen(),
    PublicBroadcastScreen(),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Re-trigger mesh discovery when app comes to foreground
      ref.read(wifiMeshManagerProvider).refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(webPortalProvider); // Initialize the portal bridge
    final currentIndex = ref.watch(navigationIndexProvider);

    final peerCount = ref.watch(connectedPeersProvider).valueOrNull?.length ?? 0;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Offline Mesh', style: TextStyle(fontWeight: FontWeight.bold)),
            Text(
              peerCount > 0 ? 'Mesh Active: $peerCount Peers' : 'Scanning Mesh...',
              style: TextStyle(
                fontSize: 12,
                color: peerCount > 0 ? Colors.greenAccent : Colors.grey,
              ),
            ),
          ],
        ),
        actions: [
          if (currentIndex == 0)
            IconButton(
              icon: const Icon(Icons.delete_forever, color: Colors.redAccent),
              tooltip: 'Wipe Memory & Exit',
              onPressed: () => _showWipeWarning(context, ref),
            ),
        ],
      ),
      body: IndexedStack(
        index: currentIndex,
        children: _screens,
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: currentIndex,
        onTap: (index) => ref.read(navigationIndexProvider.notifier).state = index,
        backgroundColor: const Color(0xFF1E1E1E),
        selectedItemColor: Colors.blueAccent,
        unselectedItemColor: Colors.grey,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.lock),
            label: 'Secure Direct',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.hub),
            label: 'Peers',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.campaign),
            label: 'Public Alerts',
          ),
        ],
      ),
    );
  }

  void _showWipeWarning(BuildContext context, WidgetRef ref) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('WIPE SECURE MEMORY?'),
        content: const Text(
          'This will permanently zero-out all cryptographic keys and RAM buffers, then exit the app.',
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
}
