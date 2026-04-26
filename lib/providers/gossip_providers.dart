import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../features/broadcast/gossip_controller.dart';
import '../features/storage/database_service.dart';
import 'ble_providers.dart';

/// Singleton for persistent storage of public alerts.
final databaseServiceProvider = Provider<DatabaseService>((ref) {
  return DatabaseService();
});

/// Manages the logic of receiving, saving, and rebroadcasting public messages.
final gossipProvider = StateNotifierProvider<GossipController, List<PublicBroadcast>>((ref) {
  final db = ref.watch(databaseServiceProvider);
  final ble = ref.watch(bleManagerProvider);
  
  // We adapt BleManager to look like BleScannerService if needed, 
  // or we update GossipController to use BleManager.
  return GossipController(db, ble);
});
