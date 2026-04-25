import 'package:offline_mesh_app/core/models/ephemeral_peer.dart';
import 'package:offline_mesh_app/core/models/message_fragment.dart';

/// BLE service interface — implemented in Prompt 5.
abstract class IBleService {
  /// Start advertising this device's ephemeral UUID + public key
  Future<void> startAdvertising({
    required String deviceUuid,
    required List<int> publicKeyBytes,
  });

  /// Stop advertising
  Future<void> stopAdvertising();

  /// Scan for nearby peers
  Stream<EphemeralPeer> scanForPeers();

  /// Send a fragment to a specific peer
  Future<void> sendFragment({
    required EphemeralPeer peer,
    required MessageFragment fragment,
  });

  /// Listen for incoming fragments
  Stream<MessageFragment> receiveFragments();

  /// Disconnect from all peers and zero session keys
  Future<void> disconnectAll();
}
