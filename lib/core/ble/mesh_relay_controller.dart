import 'dart:async';
import 'dart:math';
import 'package:cryptography/cryptography.dart';
import 'ble_advertiser_service.dart';
import 'ble_scanner_service.dart';

/// The "Blind Multi-Hop" brain connecting the BLE layer to the Cryptography layer.
class MeshRelayController {
  final BleAdvertiserService _advertiser;
  final BleScannerService _scanner;

  /// RAM-only set of seen fragment hashes to prevent infinite broadcast storms.
  final Set<String> _seenFragmentHashes = {};
  
  final Random _random = Random.secure();
  
  // Expose decrypted fragments to upper layers (e.g., FragmentService/UI)
  final StreamController<List<int>> _decryptedFragments = StreamController<List<int>>.broadcast();
  Stream<List<int>> get decryptedFragments => _decryptedFragments.stream;

  StreamSubscription<List<int>>? _advertiserSubscription;

  MeshRelayController({
    required BleAdvertiserService advertiser,
    required BleScannerService scanner,
  })  : _advertiser = advertiser,
        _scanner = scanner {
    // Listen for incoming fragments from our GATT Server (Peripheral mode)
    _advertiserSubscription = _advertiser.onFragmentReceived.listen((rawData) {
      processIncomingFragment(rawData);
    });
  }

  /// Processes incoming raw fragment data from the BLE transport.
  /// 
  /// 1. Instantly hashes the data (SHA-256).
  /// 2. Checks against `_seenFragmentHashes`. Drops if already seen.
  /// 3. Adds to `_seenFragmentHashes`.
  /// 4. Attempts decryption (relays blindly if decryption fails).
  /// 5. Triggers the relay mechanism to all other connected peers.
  Future<void> processIncomingFragment(List<int> rawData) async {
    // 1. Hash the incoming data for deduplication
    final hashAlgorithm = Sha256();
    final hash = await hashAlgorithm.hash(rawData);
    final hashHex = hash.bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

    // 2. Check deduplication
    if (_seenFragmentHashes.contains(hashHex)) {
      return; // Drop immediately to prevent broadcast storms
    }

    // 3. Add to seen hashes
    _seenFragmentHashes.add(hashHex);
    
    // Bound the set size to prevent memory leaks in RAM-only environment
    if (_seenFragmentHashes.length > 5000) {
      _seenFragmentHashes.remove(_seenFragmentHashes.first);
    }

    // 4. Pass the raw data up for attempted decryption.
    // In a fully integrated system, this controller would invoke the 
    // AesCipher with all active session keys to see if one works.
    // If successful, the plaintext goes to the UI inbox.
    _decryptedFragments.add(rawData);

    // 5. Trigger the blind relay mechanism regardless of decryption success.
    // Note: We don't have the explicit excludePeerId from flutter_blue_plus
    // server-side writes, but the jitter and dedup prevents loops.
    broadcastFragment(rawData);
  }

  /// Broadcasts a fragment to all connected peers with a random jitter delay.
  ///
  /// The jitter (0-5000ms) minimizes network collisions when multiple nodes
  /// attempt to relay the same fragment simultaneously.
  Future<void> broadcastFragment(List<int> rawData, {String? excludePeerId}) async {
    final peers = _scanner.currentPeers;
    
    for (final peer in peers) {
      final peerId = peer.remoteId.str;
      
      // Skip echoing back to the exact sender (if known)
      if (peerId == excludePeerId) continue;

      // Apply a random jitter delay (0-5000ms) per constraints
      final jitterMs = _random.nextInt(5000);
      
      Future.delayed(Duration(milliseconds: jitterMs), () async {
        await _scanner.writeToPeer(peerId, rawData);
      });
    }
  }

  void dispose() {
    _advertiserSubscription?.cancel();
    _decryptedFragments.close();
  }
}
