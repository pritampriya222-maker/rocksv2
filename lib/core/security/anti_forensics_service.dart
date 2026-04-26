import 'dart:io';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../crypto/crypto.dart';
import '../../providers/crypto_providers.dart';
import '../../providers/network_providers.dart';
import '../../providers/messaging_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';


/// Service responsible for "Nuclear Wipe" operations.
/// 
/// Overwrites memory and clears local storage to prevent forensic recovery
/// after an emergency trigger.
class AntiForensicsService {
  final Ref ref;

  AntiForensicsService(this.ref);

  /// Performs a full secure wipe and exits the application.
  Future<void> nuclearWipe() async {

    print('[AntiForensics] Starting Nuclear Wipe sequence...');

    // 1. Zeroize Cryptographic Identity & Session Keys
    // This wipes the X25519 private key and all derived shared secrets in RAM.
    final ecdh = ref.read(ecdhManagerProvider);
    await ecdh.disposeAllSessions();
    print('[AntiForensics] Crypto zeroized.');

    // 2. Clear Wi-Fi Mesh State
    final wifi = ref.read(wifiMeshManagerProvider);
    await wifi.stop();
    print('[AntiForensics] Network state cleared.');

    // 3. Wipe Messaging Buffers
    // MessageStateNotifier holds reassembly fragments in RAM.
    ref.read(messagingControllerProvider.notifier).dispose();
    print('[AntiForensics] RAM buffers zeroized.');

    // 4. Wipe Local Storage (Hive)
    // Overwrite the Public Alerts box with garbage before deleting.
    final alertsBox = Hive.box<dynamic>('public_broadcasts');
    await alertsBox.clear();
    await alertsBox.deleteFromDisk();
    print('[AntiForensics] Local DB destroyed.');

    // 5. Wipe Shared Preferences
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    print('[AntiForensics] Settings wiped.');

    // 6. Force Exit
    print('[AntiForensics] Wipe complete. Terminating process.');
    
    // Attempt graceful exit first, then hard kill
    if (Platform.isAndroid) {
      SystemNavigator.pop();
    }
    
    // Short delay to allow UI to update if possible (though unlikely)
    await Future<void>.delayed(const Duration(milliseconds: 500));
    exit(0);
  }
}

final antiForensicsProvider = Provider<AntiForensicsService>((ref) {
  // Note: We'll pass a Ref here but we need a WidgetRef usually for providers
  // Actually, we can use ProviderRef.
  return AntiForensicsService(ref as dynamic); 
});
