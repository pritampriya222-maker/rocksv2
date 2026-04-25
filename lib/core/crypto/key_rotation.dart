import 'dart:async';
import 'dart:typed_data';
import 'ecdh_manager.dart';
import 'crypto_constants.dart';

/// Orchestrates periodic ephemeral identity rotation and session TTL cleanup.
///
/// ## Responsibilities
///
/// 1. Fire a rotation timer every [CryptoConstants.ephemeralRotationMs].
///    On each tick, a new X25519 keypair is generated and the [onRotation]
///    stream emits the new public key bytes.
/// 2. Fire a cleanup timer every [CryptoConstants.sessionCleanupIntervalMs]
///    to zeroize session keys whose TTL has elapsed.
/// 3. On [stop()], cancel all timers, close the stream, and call
///    [EcdhManager.disposeAllSessions()] to wipe all key material.
///
/// ## Integration with BLE Layer
///
/// ```dart
/// // Initialise (call once at app startup)
/// final ecdh = await EcdhManager.create();
/// final rotation = KeyRotationManager(ecdh);
/// rotation.start();
///
/// // Re-advertise BLE GATT every 30 seconds
/// rotation.onRotation.listen((newPubKeyBytes) {
///   bleAdvertiser.updatePublicKey(newPubKeyBytes);
/// });
///
/// // On app teardown
/// await rotation.stop();
/// ```
///
/// ## App Lifecycle
///
/// When the app goes to background ([AppLifecycleState.paused]) call [pause()].
/// When it resumes call [resume()]. This prevents background timer drain and
/// ensures a fresh identity is advertised after a long background stay.
class KeyRotationManager {
  final EcdhManager _ecdhManager;

  Timer? _rotationTimer;
  Timer? _cleanupTimer;

  final StreamController<Uint8List> _rotationController =
      StreamController<Uint8List>.broadcast();

  bool _running = false;
  bool _stopped = false;

  // --------------------------------------------------------------------------
  // PUBLIC INTERFACE
  // --------------------------------------------------------------------------

  /// Stream of new public key bytes emitted after each identity rotation.
  ///
  /// Subscribe before calling [start()] to avoid missing the first emission.
  Stream<Uint8List> get onRotation => _rotationController.stream;

  /// Whether the manager is actively rotating.
  bool get isRunning => _running;

  KeyRotationManager(this._ecdhManager);

  /// Start rotation and cleanup timers.
  ///
  /// Immediately performs the first rotation synchronously, then schedules
  /// subsequent rotations at [CryptoConstants.ephemeralRotationMs] intervals.
  ///
  /// Idempotent — safe to call multiple times; only starts once.
  void start() {
    if (_running || _stopped) return;
    _running = true;

    // Perform first rotation immediately so callers have a valid pubkey
    _scheduleRotation();

    // Rotation: new keypair every 30 seconds
    _rotationTimer = Timer.periodic(
      const Duration(milliseconds: CryptoConstants.ephemeralRotationMs),
      (_) => _scheduleRotation(),
    );

    // Cleanup: expire stale session keys every 10 seconds
    _cleanupTimer = Timer.periodic(
      const Duration(milliseconds: CryptoConstants.sessionCleanupIntervalMs),
      (_) => _ecdhManager.expireStaleSessions(),
    );
  }

  /// Pause timers (call when app enters background).
  ///
  /// Does NOT zeroize any keys — use [stop()] for full teardown.
  void pause() {
    if (!_running) return;
    _rotationTimer?.cancel();
    _cleanupTimer?.cancel();
    _rotationTimer = null;
    _cleanupTimer = null;
    _running = false;
  }

  /// Resume after [pause()] (call when app returns to foreground).
  ///
  /// Triggers an immediate rotation so the device has a fresh identity after
  /// a potentially long background period.
  void resume() {
    if (_running || _stopped) return;
    start(); // re-uses start() which is idempotent after _running=false reset
  }

  /// Stop all timers, close the stream, and zeroize all cryptographic material.
  ///
  /// After this call the instance is permanently unusable. Create a new
  /// [KeyRotationManager] if re-initialisation is needed.
  Future<void> stop() async {
    if (_stopped) return;
    _stopped = true;
    _running = false;

    _rotationTimer?.cancel();
    _cleanupTimer?.cancel();
    _rotationTimer = null;
    _cleanupTimer = null;

    if (!_rotationController.isClosed) {
      await _rotationController.close();
    }

    // Wipe all session keys and current keypair
    await _ecdhManager.disposeAllSessions();
  }

  // --------------------------------------------------------------------------
  // PRIVATE
  // --------------------------------------------------------------------------

  void _scheduleRotation() {
    // Dispatch async rotation without blocking the timer callback
    _performRotation().ignore();
  }

  Future<void> _performRotation() async {
    if (_stopped) return;

    try {
      await _ecdhManager.rotateIdentity();
      final pubKeyBytes = _ecdhManager.getCurrentPublicKeyBytes();

      if (!_rotationController.isClosed) {
        _rotationController.add(pubKeyBytes);
      }
    } catch (_) {
      // Rotation failure must not crash the app — silently skip.
      // The BLE layer will continue advertising the previous identity until
      // the next rotation succeeds.
    }
  }
}
