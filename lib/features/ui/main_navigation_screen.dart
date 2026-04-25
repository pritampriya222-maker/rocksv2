import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'home_screen.dart';
import 'public_broadcast_screen.dart';

/// The primary shell of the application managing routing between operational modes.
class MainNavigationScreen extends ConsumerStatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  ConsumerState<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends ConsumerState<MainNavigationScreen> {
  int _currentIndex = 0;

  // The two distinct operational modes
  final List<Widget> _screens = const [
    HomeScreen(),
    PublicBroadcastScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    // Watch the global peer count to reassure the user that the mesh is active.
    final peerCount = ref.watch(peerCountProvider);

    return Scaffold(
      // We use a global AppBar here to display connectivity status persistently.
      // Note: If HomeScreen has its own AppBar, you would typically remove it
      // to avoid double AppBars, but nested Scaffolds are supported in Flutter.
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
          // If we are on the Secure Direct tab, show the Wipe Memory button
          if (_currentIndex == 0)
            IconButton(
              icon: const Icon(Icons.delete_forever, color: Colors.redAccent),
              tooltip: 'Wipe Memory & Exit',
              onPressed: () => _showWipeWarning(context, ref),
            ),
        ],
      ),
      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        backgroundColor: const Color(0xFF1E1E1E),
        selectedItemColor: Colors.blueAccent,
        unselectedItemColor: Colors.grey,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.lock),
            label: 'Secure Direct',
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
          'This will permanently zero-out all cryptographic keys and RAM buffers, then exit the app. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('CANCEL'),
          ),
          TextButton(
            onPressed: () {
              // Call SessionLifecycleManager.teardown()
              // Clear Riverpod state
              // Exit App
            },
            child: const Text('WIPE & EXIT', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
  }
}
