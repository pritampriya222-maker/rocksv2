import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../dashboard/dashboard_screen.dart';
import 'home_screen.dart';
import '../news/news_feed_screen.dart';
import '../routes/safe_routes_screen.dart';
import 'public_broadcast_screen.dart';
import '../../providers/network_providers.dart';
import '../../providers/alert_providers.dart';

class MainNavigationScreen extends ConsumerStatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  ConsumerState<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends ConsumerState<MainNavigationScreen> with WidgetsBindingObserver {
  final List<Widget> _screens = const [
    DashboardScreen(),
    HomeScreen(),
    NewsFeedScreen(),
    SafeRoutesScreen(),
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
    // Force the alert, news, route providers to initialize
    ref.watch(alertProvider);
    final currentIndex = ref.watch(navigationIndexProvider);
    final peerCount = ref.watch(connectedPeersProvider).valueOrNull?.length ?? 0;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF121212),
        elevation: 0,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: peerCount > 0
                    ? Colors.greenAccent.withValues(alpha: 0.15)
                    : Colors.redAccent.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(
                peerCount > 0 ? Icons.wifi_tethering : Icons.wifi_tethering_off,
                size: 16,
                color: peerCount > 0 ? Colors.greenAccent : Colors.redAccent,
              ),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'OFFLINE MESH',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    letterSpacing: 1.5,
                  ),
                ),
                Text(
                  peerCount > 0
                      ? '$peerCount Peer${peerCount > 1 ? 's' : ''} Connected'
                      : 'Discovering...',
                  style: TextStyle(
                    fontSize: 10,
                    color: peerCount > 0 ? Colors.greenAccent : Colors.grey,
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 12),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.redAccent.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.redAccent.withValues(alpha: 0.3)),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.wifi_off, size: 12, color: Colors.redAccent),
                SizedBox(width: 4),
                Text(
                  'OFFLINE',
                  style: TextStyle(
                    color: Colors.redAccent,
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      body: IndexedStack(
        index: currentIndex,
        children: _screens,
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF141414),
          border: Border(
            top: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
          ),
        ),
        child: BottomNavigationBar(
          currentIndex: currentIndex,
          onTap: (index) => ref.read(navigationIndexProvider.notifier).state = index,
          backgroundColor: Colors.transparent,
          elevation: 0,
          type: BottomNavigationBarType.fixed,
          selectedItemColor: Colors.blueAccent,
          unselectedItemColor: Colors.grey[600],
          selectedFontSize: 10,
          unselectedFontSize: 9,
          selectedLabelStyle: const TextStyle(letterSpacing: 0.5, fontWeight: FontWeight.bold),
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.dashboard_outlined),
              activeIcon: Icon(Icons.dashboard),
              label: 'DASH',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.chat_bubble_outline),
              activeIcon: Icon(Icons.chat_bubble),
              label: 'CHAT',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.newspaper_outlined),
              activeIcon: Icon(Icons.newspaper),
              label: 'NEWS',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.map_outlined),
              activeIcon: Icon(Icons.map),
              label: 'ROUTES',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.warning_amber_outlined),
              activeIcon: Icon(Icons.warning_amber),
              label: 'ALERTS',
            ),
          ],
        ),
      ),
    );
  }
}
