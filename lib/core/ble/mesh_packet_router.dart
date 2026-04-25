import 'dart:convert';
import 'mesh_relay_controller.dart';
import '../../features/broadcast/gossip_controller.dart';

/// Inspects incoming BLE byte arrays and routes them to the correct subsystem.
/// Implements the Dual-Mode multiplexing (0x01 Private, 0x02 Public).
class MeshPacketRouter {
  final MeshRelayController _relayController;
  final GossipController _gossipController;

  static const int headerPrivate = 0x01;
  static const int headerPublic = 0x02;

  MeshPacketRouter({
    required MeshRelayController relayController,
    required GossipController gossipController,
  })  : _relayController = relayController,
        _gossipController = gossipController;

  /// Entry point for all incoming BLE characteristic writes.
  Future<void> routeIncomingData(List<int> rawPayload) async {
    if (rawPayload.isEmpty) return;

    // Extract the multiplexing header
    final header = rawPayload[0];
    final remainingBytes = rawPayload.sublist(1);

    if (header == headerPrivate) {
      // Route 0x01 to the RAM-only secure private relay subsystem
      await _relayController.processIncomingFragment(remainingBytes);
    } else if (header == headerPublic) {
      // Route 0x02 to the persistent database-backed public gossip subsystem
      try {
        final jsonPayload = utf8.decode(remainingBytes);
        await _gossipController.onBroadcastReceived(jsonPayload);
      } catch (e) {
        // Drop invalid or corrupted UTF-8 payloads silently
      }
    } else {
      // Unknown header, drop packet
    }
  }

  /// Prepends the 0x01 header for private encrypted fragments.
  static List<int> encodePrivatePacket(List<int> fragmentData) {
    return [headerPrivate, ...fragmentData];
  }

  /// Prepends the 0x02 header for public broadcast JSON strings.
  static List<int> encodePublicPacket(String jsonString) {
    return [headerPublic, ...utf8.encode(jsonString)];
  }
}
