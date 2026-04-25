import 'dart:typed_data';

/// BLE GATT UUIDs and advertisement constants.
///
/// All UUIDs follow the standard 128-bit format.
/// Custom service UUID is fixed — characteristic UUIDs are also fixed.
/// The ephemeral device UUID rotates every 30 s in the advertised LOCAL NAME,
/// not in the GATT service UUID (which stays constant for discoverability).
class BleConstants {
  BleConstants._();

  // --------------------------------------------------------------------------
  // GATT Service
  // --------------------------------------------------------------------------

  /// Primary service UUID — scanned by all mesh devices.
  /// Fixed so scanning devices can filter for mesh peers.
  static const String meshServiceUuid =
      '12345678-1234-5678-1234-56789abcdef0';

  /// Characteristic: peer writes a fragment to this slot.
  static const String fragmentWriteCharUuid =
      '12345678-1234-5678-1234-56789abcdef1';

  /// Characteristic: peer reads the local device's ephemeral public key.
  static const String pubKeyReadCharUuid =
      '12345678-1234-5678-1234-56789abcdef2';

  /// Characteristic: notify — device pushes received fragments to subscribers.
  static const String fragmentNotifyCharUuid =
      '12345678-1234-5678-1234-56789abcdef3';

  // --------------------------------------------------------------------------
  // Advertisement
  // --------------------------------------------------------------------------

  /// Local name prefix embedded in BLE advertisement payload.
  /// Followed by the first 8 chars of the ephemeral UUID.
  static const String advertisementPrefix = 'OM_';

  /// Maximum MTU size requested for fragment payloads (bytes).
  static const int preferredMtu = 512;

  /// BLE scan timeout before assuming no peers present (milliseconds).
  static const int scanTimeoutMs = 10000;

  /// How long to maintain a GATT connection before auto-disconnect (ms).
  static const int connectionTimeoutMs = 30000;

  /// Maximum concurrent GATT connections.
  static const int maxConcurrentConnections = 5;

  // --------------------------------------------------------------------------
  // Fragmentation over BLE
  // --------------------------------------------------------------------------

  /// Maximum fragment wire size that fits in a single GATT write.
  /// 512 MTU - 3 byte ATT header = 509 usable bytes.
  static const int maxGattWriteBytes = 509;

  // --------------------------------------------------------------------------
  // Fragment buffer deduplication
  // --------------------------------------------------------------------------

  /// Maximum number of seen fragment IDs to retain for deduplication.
  /// Prevents memory bloat in long-running sessions.
  static const int maxSeenFragmentIds = 500;

  // --------------------------------------------------------------------------
  // Relay jitter
  // --------------------------------------------------------------------------

  /// Minimum relay delay in milliseconds (random jitter to prevent flooding)
  static const int minRelayDelayMs = 100;

  /// Maximum relay delay in milliseconds
  static const int maxRelayDelayMs = 5000;
}

/// Represents a BLE write payload containing a serialized fragment.
///
/// Wire format over BLE:
/// ```
/// [1 byte: version] [1 byte: type] [N bytes: JSON-encoded fragment]
/// ```
class BlePacket {
  static const int version = 0x01;
  static const int typeFragment = 0x01;
  static const int typePubKey = 0x02;
  static const int typeAck = 0x03;

  final int type;
  final Uint8List payload;

  BlePacket({required this.type, required this.payload});

  /// Encode to wire bytes.
  Uint8List toBytes() {
    final out = Uint8List(2 + payload.length);
    out[0] = version;
    out[1] = type;
    out.setAll(2, payload);
    return out;
  }

  /// Decode from wire bytes.
  static BlePacket? fromBytes(Uint8List bytes) {
    if (bytes.length < 3) return null;
    if (bytes[0] != version) return null;
    return BlePacket(
      type: bytes[1],
      payload: bytes.sublist(2),
    );
  }
}
