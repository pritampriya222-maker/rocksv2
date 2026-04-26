import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/ble/ble_manager.dart';
import '../core/ble/ble_peripheral_bridge.dart';
import '../core/models/ephemeral_peer.dart';
import '../core/models/message_fragment.dart';
import 'crypto_providers.dart';

// =============================================================================
// BLE PROVIDERS
// =============================================================================

/// Singleton [BlePeripheralBridge] — native advertising channel.
final blePeripheralBridgeProvider = Provider<BlePeripheralBridge>((ref) {
  final bridge = BlePeripheralBridge();
  ref.onDispose(() => bridge.stopAdvertising());
  return bridge;
});

/// Singleton [BleManager] — wired to crypto stack.
///
/// Depends on [ecdhManagerProvider] and [fragmentServiceProvider].
final bleManagerProvider = Provider<BleManager>((ref) {
  final ecdh = ref.watch(ecdhManagerProvider);
  final bridge = ref.watch(blePeripheralBridgeProvider);

  final mgr = BleManager(
    ecdhManager: ecdh,
    bridge: bridge,
  );


  ref.onDispose(() => mgr.dispose());
  return mgr;
});

// =============================================================================
// PEER STATE
// =============================================================================

/// Live list of connected peers — updated whenever BLE connection changes.
final connectedPeersProvider = StreamProvider<List<EphemeralPeer>>((ref) {
  final mgr = ref.watch(bleManagerProvider);
  return mgr.peerUpdates;
});

// =============================================================================
// FRAGMENT RECEPTION
// =============================================================================

/// Raw inbound fragment stream — all fragments this device receives over BLE.
///
/// Consumers (fragment buffer) subscribe to this and attempt decryption.
final inboundFragmentStreamProvider =
    StreamProvider<MessageFragment>((ref) {
  final mgr = ref.watch(bleManagerProvider);
  return mgr.inboundFragments;
});

// =============================================================================
// FRAGMENT BUFFER (in-RAM reassembly)
// =============================================================================

/// In-RAM buffer collecting fragments by their set ID.
///
/// Emits a complete [MessageSet] when all 3 fragments for a set arrive.
/// Automatically discards expired entries.
final fragmentBufferProvider =
    StateNotifierProvider<FragmentBufferNotifier, List<MessageSet>>((ref) {
  final notifier = FragmentBufferNotifier();

  // Feed inbound fragments into the buffer
  ref.listen(inboundFragmentStreamProvider, (_, next) {
    next.whenData((fragment) => notifier.addFragment(fragment));
  });

  return notifier;
});

/// A group of fragments sharing the same [fragmentSetId].
class MessageSet {
  final String setId;
  final Map<int, MessageFragment> fragments; // index → fragment
  final DateTime firstSeen;

  MessageSet({
    required this.setId,
    required this.firstSeen,
  }) : fragments = {};

  bool get isComplete =>
      fragments.length == 3 &&
      fragments.containsKey(0) &&
      fragments.containsKey(1) &&
      fragments.containsKey(2);

  bool get isExpired =>
      DateTime.now().difference(firstSeen).inMilliseconds > 300000;

  List<MessageFragment> get orderedFragments =>
      [0, 1, 2].map((i) => fragments[i]!).toList();
}

/// Notifier that manages the in-RAM fragment buffer.
class FragmentBufferNotifier extends StateNotifier<List<MessageSet>> {
  FragmentBufferNotifier() : super([]);

  /// Add an incoming fragment. Triggers rebuild if count changes.
  void addFragment(MessageFragment fragment) {
    // Purge expired sets first
    final now = state.where((s) => !s.isExpired).toList();

    final existingIndex =
        now.indexWhere((s) => s.setId == fragment.fragmentSetId);

    if (existingIndex == -1) {
      // New set
      final newSet = MessageSet(
        setId: fragment.fragmentSetId,
        firstSeen: DateTime.now(),
      );
      newSet.fragments[fragment.index] = fragment;
      state = [...now, newSet];
    } else {
      // Add to existing set (only if slot not already filled)
      final sets = List<MessageSet>.from(now);
      final set = sets[existingIndex];
      if (!set.fragments.containsKey(fragment.index)) {
        set.fragments[fragment.index] = fragment;
        state = sets;
      }
    }
  }

  /// Remove a set after successful reassembly.
  void removeSet(String setId) {
    state = state.where((s) => s.setId != setId).toList();
  }

  /// Remove all expired sets.
  void purgeExpired() {
    state = state.where((s) => !s.isExpired).toList();
  }
}
