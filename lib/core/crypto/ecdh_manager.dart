import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'crypto_constants.dart';
import 'secure_memory.dart';

/// Manages X25519 ephemeral keypairs and ECDH shared-secret derivation.
///
/// ## Lifecycle
///
/// 1. Instantiate once per app session.
/// 2. [rotateIdentity()] is called every [CryptoConstants.ephemeralRotationMs]
///    by [KeyRotationManager]. It generates a fresh keypair and invalidates
///    the old one.
/// 3. On receiving a BLE advertisement, call [deriveSessionKey()] with the
///    peer's advertised public key bytes.
/// 4. On peer disconnect, call [expireSession()] for that peer.
/// 5. On app shutdown, call [disposeAllSessions()].
///
/// ## Security Invariants
///
/// - Private key bytes are NEVER returned from any public method.
/// - Session keys are cached by peer fingerprint; each is individually zeroizable.
/// - [disposeAllSessions()] is the only guaranteed-clean teardown path.
/// - Every [extractBytes()] call is immediately followed by [SecureMemory.zeroize()].
class EcdhManager {
  final X25519 _x25519 = X25519();

  /// Currently active ephemeral keypair — rotated every 30 s.
  SimpleKeyPair? _currentKeyPair;

  /// Cached copy of the current public key bytes for advertisement.
  /// Rebuilt on every [rotateIdentity()].
  Uint8List? _currentPublicKeyBytes;

  /// peer-fingerprint → derived SecretKey
  ///
  /// Fingerprint is a hex string of the first
  /// [CryptoConstants.peerFingerprintBytes] bytes of the remote pubkey.
  final Map<String, SecretKey> _sessionKeys = {};

  /// peer-fingerprint → last-used epoch millisecond
  final Map<String, int> _sessionTimestamps = {};

  bool _disposed = false;

  // --------------------------------------------------------------------------
  // CONSTRUCTION
  // --------------------------------------------------------------------------

  EcdhManager();

  /// Async factory: initialise with a fresh identity.
  static Future<EcdhManager> create() async {
    final mgr = EcdhManager();
    await mgr.rotateIdentity();
    return mgr;
  }

  // --------------------------------------------------------------------------
  // IDENTITY ROTATION
  // --------------------------------------------------------------------------

  /// Generate a new ephemeral X25519 keypair and zeroize the old one.
  ///
  /// Must be called at least once before any other method.
  /// Automatically called by [KeyRotationManager.start()].
  Future<void> rotateIdentity() async {
    _ensureNotDisposed();
    await _zeroizeCurrentKeypair();

    _currentKeyPair = await _x25519.newKeyPair();

    final pubKey = await _currentKeyPair!.extractPublicKey();
    _currentPublicKeyBytes = Uint8List.fromList(pubKey.bytes);
  }

  /// Return a **defensive copy** of the current ephemeral public key bytes
  /// suitable for embedding in a BLE GATT characteristic.
  ///
  /// Always 32 bytes (X25519 public key length).
  Uint8List getCurrentPublicKeyBytes() {
    _ensureNotDisposed();
    if (_currentPublicKeyBytes == null) {
      throw StateError(
        'No active identity — call rotateIdentity() first.',
      );
    }
    // Defensive copy: callers must not hold a reference that survives rotation
    return Uint8List.fromList(_currentPublicKeyBytes!);
  }

  // --------------------------------------------------------------------------
  // SESSION KEY DERIVATION
  // --------------------------------------------------------------------------

  /// Derive (or return a cached) shared session key for [remotePublicKeyBytes].
  ///
  /// Performs ECDH X25519 and passes the raw shared secret through a
  /// one-step HKDF-equivalent (HMAC-SHA256 with an empty info string) to
  /// produce a uniformly random 32-byte key suitable for AES-256-GCM.
  ///
  /// The derived key is cached by peer fingerprint and reused within its TTL.
  /// Expired keys are re-derived transparently.
  ///
  /// Throws [ArgumentError] if [remotePublicKeyBytes] is not exactly 32 bytes.
  /// Throws [StateError] if no current keypair is available.
  Future<SecretKey> deriveSessionKey({
    required Uint8List remotePublicKeyBytes,
  }) async {
    _ensureNotDisposed();

    if (remotePublicKeyBytes.length != CryptoConstants.x25519PublicKeyLength) {
      throw ArgumentError(
        'Invalid X25519 public key length: '
        '${remotePublicKeyBytes.length} (expected '
        '${CryptoConstants.x25519PublicKeyLength})',
      );
    }

    final fingerprint = _computeFingerprint(remotePublicKeyBytes);

    // Return valid cached key if within TTL
    if (_sessionKeys.containsKey(fingerprint)) {
      if (_isSessionAlive(fingerprint)) {
        _sessionTimestamps[fingerprint] =
            DateTime.now().millisecondsSinceEpoch;
        return _sessionKeys[fingerprint]!;
      }
      // Stale — zeroize and fall through to re-derive
      await _zeroizeSession(fingerprint);
    }

    if (_currentKeyPair == null) {
      throw StateError(
        'No active keypair — call rotateIdentity() first.',
      );
    }

    // ECDH: raw shared secret
    final remotePub = SimplePublicKey(
      remotePublicKeyBytes,
      type: KeyPairType.x25519,
    );
    final rawShared = await _x25519.sharedSecretKey(
      keyPair: _currentKeyPair!,
      remotePublicKey: remotePub,
    );

    // KDF step: HMAC-SHA256(key=rawShared, data=[]) → 32 uniform bytes
    final rawBytes = await rawShared.extractBytes();
    final hkdf = Hmac.sha256();
    final derivedMac = await hkdf.calculateMac(
      const [], // empty context (sufficient for single-key derivation)
      secretKey: SecretKey(rawBytes),
    );

    // Zeroize intermediate material immediately
    SecureMemory.zeroize(rawBytes);

    final sessionKey = SecretKey(List<int>.from(derivedMac.bytes));
    _sessionKeys[fingerprint] = sessionKey;
    _sessionTimestamps[fingerprint] = DateTime.now().millisecondsSinceEpoch;

    return sessionKey;
  }

  /// Returns [true] if a valid (non-expired) session key exists for this peer.
  bool hasValidSession(Uint8List remotePublicKeyBytes) {
    if (_disposed) return false;
    final fp = _computeFingerprint(remotePublicKeyBytes);
    return _sessionKeys.containsKey(fp) && _isSessionAlive(fp);
  }

  // --------------------------------------------------------------------------
  // SESSION EXPIRATION
  // --------------------------------------------------------------------------

  /// Immediately expire and zeroize the session key for [remotePublicKeyBytes].
  ///
  /// Call this when a peer disconnects from BLE or its UUID rotates.
  Future<void> expireSession(Uint8List remotePublicKeyBytes) async {
    final fp = _computeFingerprint(remotePublicKeyBytes);
    await _zeroizeSession(fp);
  }

  /// Scan all sessions and zeroize any whose TTL has elapsed.
  ///
  /// Called periodically by [KeyRotationManager] every
  /// [CryptoConstants.sessionCleanupIntervalMs].
  Future<void> expireStaleSessions() async {
    if (_disposed) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    final stale = <String>[
      for (final entry in _sessionTimestamps.entries)
        if ((now - entry.value) > CryptoConstants.sessionKeyTtlMs) entry.key,
    ];
    for (final fp in stale) {
      await _zeroizeSession(fp);
    }
  }

  /// Zeroize ALL session keys and the current identity keypair.
  ///
  /// Must be called on app shutdown or when the [EcdhManager] is no longer
  /// needed. After this call, the instance is unusable.
  Future<void> disposeAllSessions() async {
    if (_disposed) return;
    for (final fp in List<String>.from(_sessionKeys.keys)) {
      await _zeroizeSession(fp);
    }
    await _zeroizeCurrentKeypair();
    _disposed = true;
  }

  // --------------------------------------------------------------------------
  // PRIVATE HELPERS
  // --------------------------------------------------------------------------

  /// Compute a short hex fingerprint for a public key (for map keying only).
  ///
  /// Not cryptographically collision-resistant — used only as a fast map index.
  /// Two different pubkeys could theoretically collide; the risk is negligible
  /// for the number of peers expected in a local BLE session.
  String _computeFingerprint(Uint8List pubkey) {
    final end = pubkey.length < CryptoConstants.peerFingerprintBytes
        ? pubkey.length
        : CryptoConstants.peerFingerprintBytes;
    final sb = StringBuffer();
    for (var i = 0; i < end; i++) {
      sb.write(pubkey[i].toRadixString(16).padLeft(2, '0'));
    }
    return sb.toString();
  }

  bool _isSessionAlive(String fingerprint) {
    final ts = _sessionTimestamps[fingerprint];
    if (ts == null) return false;
    return (DateTime.now().millisecondsSinceEpoch - ts) <=
        CryptoConstants.sessionKeyTtlMs;
  }

  Future<void> _zeroizeSession(String fingerprint) async {
    final key = _sessionKeys.remove(fingerprint);
    _sessionTimestamps.remove(fingerprint);
    if (key != null) {
      final bytes = await key.extractBytes();
      SecureMemory.zeroize(bytes);
    }
  }

  Future<void> _zeroizeCurrentKeypair() async {
    if (_currentKeyPair != null) {
      try {
        // Attempt to zeroize the private scalar. Not all implementations
        // support byte extraction — catch and ignore if unsupported.
        final privBytes = await _currentKeyPair!.extractPrivateKeyBytes();
        if (privBytes.isNotEmpty) {
          SecureMemory.zeroize(privBytes);
        }
      } catch (_) {
        // Extraction not supported by this implementation; best-effort only.
      }
      _currentKeyPair = null;
    }
    if (_currentPublicKeyBytes != null) {
      SecureMemory.zeroizeUint8List(_currentPublicKeyBytes!);
      _currentPublicKeyBytes = null;
    }
  }

  void _ensureNotDisposed() {
    if (_disposed) throw StateError('EcdhManager has been disposed');
  }
}
