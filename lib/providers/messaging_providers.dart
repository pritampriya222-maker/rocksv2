import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../features/messaging/message_state_provider.dart';
import '../features/messaging/fragmentation_engine.dart';
import 'crypto_providers.dart';
import 'network_providers.dart';

/// Singleton [FragmentationEngine].
final fragmentationEngineProvider = Provider<FragmentationEngine>((ref) {
  return FragmentationEngine();
});

/// [MessageStateNotifier] — manages reassembly and decryption of messages.
final messagingControllerProvider =
    StateNotifierProvider<MessageStateNotifier, List<DisplayMessage>>((ref) {
  final aes = ref.watch(aesCipherProvider);
  final engine = ref.watch(fragmentationEngineProvider);
  final ecdh = ref.watch(ecdhManagerProvider);

  final notifier = MessageStateNotifier(
    aesCipher: aes,
    fragmentationEngine: engine,
  );


  // Subscribe to inbound fragments via Wi-Fi Mesh
  ref.listen(incomingFragmentsProvider, (_, next) {
    next.whenData((fragment) {
      final peers = ref.read(connectedPeersProvider).valueOrNull ?? [];
      notifier.onFragmentReceived(fragment, peers, ecdh);
    });
  });

  return notifier;

});


// Extension to add sendMessage capability to the notifier if needed,
// or we can add it to the class itself.
extension MessageStateNotifierExt on MessageStateNotifier {
  Future<void> sendMessage(String text) async {
    // This logic is mostly in MessagingScreen._sendMessage
    // We should move it to a controller or the notifier.
  }
}
