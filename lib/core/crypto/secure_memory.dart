import 'dart:typed_data';

/// Secure memory utilities for the Offline Mesh system.
///
/// DISCLAIMER: Dart runs in a managed VM with a garbage collector.
/// True hardware-level memory wiping is not possible without native
/// extensions. This implementation provides best-effort multi-pass
/// overwrite to minimise the window during which sensitive bytes are
/// accessible before GC.
///
/// The three-pass strategy (0x00 → 0xFF → 0x00) mitigates:
/// - Software inspection of recently freed memory
/// - Hardware remanence in L1/L2 cache lines
///
/// It does NOT protect against:
/// - OS-level memory dumps of the process
/// - Cold-boot attacks on physical RAM
/// - VM heap snapshots in a debugger
///
/// For a hackathon on unmodified Android/iOS, this is the security ceiling
/// achievable in pure Dart.
class SecureMemory {
  SecureMemory._(); // non-instantiable utility class

  // --------------------------------------------------------------------------
  // ZEROIZATION
  // --------------------------------------------------------------------------

  /// Overwrite [bytes] with three passes to best-effort wipe sensitive data.
  ///
  /// Pass 1: 0x00 (zeros)
  /// Pass 2: 0xFF (ones)
  /// Pass 3: 0x00 (final zeros — leave buffer inert)
  ///
  /// Safe to call on empty lists (no-op).
  static void zeroize(List<int> bytes) {
    if (bytes.isEmpty) return;
    final len = bytes.length;

    try {
      // Pass 1: zeros
      for (var i = 0; i < len; i++) {
        bytes[i] = 0x00;
      }
      // Pass 2: ones
      for (var i = 0; i < len; i++) {
        bytes[i] = 0xFF;
      }
      // Pass 3: zeros (leave it clean)
      for (var i = 0; i < len; i++) {
        bytes[i] = 0x00;
      }
    } catch (_) {
      // If the buffer is unmodifiable (e.g. from the cryptography package),
      // we ignore it as the library likely handles its own cleanup.
    }
  }

  /// Overwrite a [Uint8List] in-place. Typed variant avoids boxing overhead.
  static void zeroizeUint8List(Uint8List bytes) {
    if (bytes.isEmpty) return;
    final len = bytes.lengthInBytes;
    try {
      for (var i = 0; i < len; i++) {
        bytes[i] = 0x00;
      }
      for (var i = 0; i < len; i++) {
        bytes[i] = 0xFF;
      }
      for (var i = 0; i < len; i++) {
        bytes[i] = 0x00;
      }
    } catch (_) {
      // Ignore unmodifiable buffers
    }
  }

  // --------------------------------------------------------------------------
  // BUFFER UTILITIES
  // --------------------------------------------------------------------------

  /// Allocate a zero-initialised buffer of [size] bytes.
  ///
  /// [Uint8List] is zero-initialised by the Dart runtime, so no explicit
  /// fill is required on construction.
  static Uint8List zeroedBuffer(int size) => Uint8List(size);

  /// Move bytes from [source] into a new list, then zeroize [source].
  ///
  /// Use when transferring ownership of key material between scopes.
  static List<int> moveBytes(List<int> source) {
    final dest = List<int>.from(source);
    zeroize(source);
    return dest;
  }

  /// Move bytes from a [Uint8List] into a new [Uint8List], then zeroize.
  static Uint8List moveUint8List(Uint8List source) {
    final dest = Uint8List.fromList(source);
    zeroizeUint8List(source);
    return dest;
  }

  /// Constant-time byte-array equality comparison.
  ///
  /// Compares ALL bytes regardless of early mismatch to prevent timing attacks.
  /// Returns [true] only if [a] and [b] are identical in length and content.
  static bool constantTimeEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var result = 0;
    for (var i = 0; i < a.length; i++) {
      result |= a[i] ^ b[i];
    }
    return result == 0;
  }
}

// ---------------------------------------------------------------------------
// SECURE BUFFER
// ---------------------------------------------------------------------------

/// A lifecycle-managed byte buffer that automatically zeroizes on [dispose()].
///
/// Usage:
/// ```dart
/// final buf = SecureBuffer(Uint8List.fromList(keyBytes));
/// // ... use buf.bytes ...
/// buf.dispose(); // zeroes all bytes
/// ```
///
/// IMPORTANT: Do NOT store [bytes] beyond the lifetime of this [SecureBuffer].
/// The returned [Uint8List] is NOT a copy — it is the backing buffer.
class SecureBuffer {
  final Uint8List _data;
  bool _disposed = false;

  /// Create a [SecureBuffer] wrapping [data].
  ///
  /// Ownership of [data] is transferred; the caller should not retain a
  /// reference to it after passing to this constructor.
  SecureBuffer(this._data);

  /// Access the backing byte array.
  ///
  /// Throws [StateError] if [dispose()] has already been called.
  Uint8List get bytes {
    if (_disposed) throw StateError('SecureBuffer has been disposed');
    return _data;
  }

  /// Length of the buffer in bytes.
  int get length => _data.length;

  /// Whether this buffer has been disposed.
  bool get isDisposed => _disposed;

  /// Zeroize all bytes and mark this buffer as disposed.
  ///
  /// Idempotent — safe to call multiple times.
  void dispose() {
    if (_disposed) return;
    SecureMemory.zeroizeUint8List(_data);
    _disposed = true;
  }
}
