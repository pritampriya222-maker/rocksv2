import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../storage/database_service.dart';
import '../../core/ble/ble_manager.dart';
import '../../core/ble/mesh_packet_router.dart';

/// A UI model representing a plaintext public broadcast.
class PublicBroadcast {
  final String id;
  final String text;
  final int timestamp;

  PublicBroadcast({required this.id, required this.text, required this.timestamp});
}

/// Manages the logic of receiving, saving, and rebroadcasting public messages.
class GossipController extends StateNotifier<List<PublicBroadcast>> {
  final DatabaseService _dbService;
  final BleManager _bleManager;
  final Uuid _uuid = const Uuid();

  GossipController(this._dbService, this._bleManager) : super([]) {
    _loadHistory();
  }


  /// Loads historical broadcasts from the persistent local database.
  Future<void> _loadHistory() async {
    final history = await _dbService.getAllBroadcasts();
    state = history.map((b) => PublicBroadcast(
      id: b['id'] as String,
      text: b['text'] as String,
      timestamp: b['timestamp'] as int,
    )).toList();
  }

  /// Processes an incoming 0x02 public broadcast packet.
  Future<void> onBroadcastReceived(String jsonPayload) async {
    try {
      final map = jsonDecode(jsonPayload) as Map<String, dynamic>;
      final id = map['id'] as String;
      final text = map['text'] as String;
      final timestamp = map['timestamp'] as int;

      // 1. Gossip Loop Prevention
      if (await _dbService.hasBroadcast(id)) {
        // We have already seen this broadcast. Silently drop to prevent network storms.
        return; 
      }

      // 2. Save locally for historical offline access
      await _dbService.saveBroadcast(id, text, timestamp);

      // 3. Update the UI state proactively
      state = [
        PublicBroadcast(id: id, text: text, timestamp: timestamp),
        ...state,
      ];
      // Note: Re-sorting by timestamp might be necessary here if out-of-order packets arrive,
      // but inserting at the top is generally correct for real-time mesh arrival.

      // 4. Rebroadcast to all connected peers
      final encodedPacket = MeshPacketRouter.encodePublicPacket(jsonPayload);
      await _bleManager.broadcastPublicPacket(encodedPacket);
    } catch (e) {
      // Invalid JSON or missing fields, drop gracefully without crashing
    }
  }

  /// Called by the UI to originate a new public broadcast.
  Future<void> createAndSendBroadcast(String text) async {
    // 1. Generate unique identifier and timestamp
    final id = _uuid.v4();
    final timestamp = DateTime.now().millisecondsSinceEpoch;

    // 2. Save locally and immediately update UI state
    await _dbService.saveBroadcast(id, text, timestamp);
    state = [
      PublicBroadcast(id: id, text: text, timestamp: timestamp),
      ...state,
    ];

    // 3. Serialize to standard JSON
    final jsonPayload = jsonEncode({
      'id': id,
      'text': text,
      'timestamp': timestamp,
    });

    // 4. Prepend the 0x02 Multiplexer Header and broadcast via BLE
    final encodedPacket = MeshPacketRouter.encodePublicPacket(jsonPayload);
    await _bleManager.broadcastPublicPacket(encodedPacket);
  }
}

