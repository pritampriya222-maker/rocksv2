import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/network/wifi_mesh_manager.dart';
import '../core/models/ephemeral_peer.dart';
import '../core/models/message_fragment.dart';
import '../core/models/public_alert.dart';
import '../core/models/news_post.dart';
import '../core/models/safe_route.dart';
import 'crypto_providers.dart';

import '../core/security/identity_service.dart';
import '../core/network/web_portal_manager.dart';

final webPortalProvider = Provider<WebPortalManager>((ref) {
  final mesh = ref.watch(wifiMeshManagerProvider);
  final portal = WebPortalManager(mesh);
  portal.start();
  return portal;
});


final identityServiceProvider = Provider<IdentityService>((ref) {
  return IdentityService();
});


/// Provider for the Wi-Fi Mesh Manager (Singleton)
final wifiMeshManagerProvider = Provider<WifiMeshManager>((ref) {
  final ecdh = ref.watch(ecdhManagerProvider);
  final identity = ref.watch(identityServiceProvider);
  final manager = WifiMeshManager(ecdh, identity);

  
  // Start the manager and ensure it's stopped when provider is disposed
  manager.start();
  ref.onDispose(() => manager.stop());
  
  return manager;
});

/// List of currently connected Wi-Fi peers
final navigationIndexProvider = StateProvider<int>((ref) => 0);

final connectedPeersProvider = StreamProvider<List<EphemeralPeer>>((ref) {

  final manager = ref.watch(wifiMeshManagerProvider);
  return manager.peersStream;
});

/// Stream of incoming message fragments from the Wi-Fi mesh
final incomingFragmentsProvider = StreamProvider<MessageFragment>((ref) {
  final manager = ref.watch(wifiMeshManagerProvider);
  return manager.fragmentStream;
});

final incomingAlertsProvider = StreamProvider<List<PublicAlert>>((ref) {
  final manager = ref.watch(wifiMeshManagerProvider);
  return manager.alertStream;
});

final incomingNewsProvider = StreamProvider<List<NewsPost>>((ref) {
  final manager = ref.watch(wifiMeshManagerProvider);
  return manager.newsStream;
});

final incomingRoutesProvider = StreamProvider<List<SafeRoute>>((ref) {
  final manager = ref.watch(wifiMeshManagerProvider);
  return manager.routeStream;
});
