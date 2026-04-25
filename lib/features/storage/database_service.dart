import 'package:hive_flutter/hive_flutter.dart';

/// Handles the persistent saving of public broadcast messages (Gossip Protocol).
/// STRICT CONSTRAINT: Private messages (0x01) must NEVER enter this service.
class DatabaseService {
  static const String _boxName = 'public_broadcasts';
  Box<dynamic>? _box;

  /// Initializes the local Hive storage mechanism.
  Future<void> init() async {
    await Hive.initFlutter();
    _box = await Hive.openBox(_boxName);
  }

  /// Saves the message if the ID does not already exist.
  Future<void> saveBroadcast(String id, String text, int timestamp) async {
    final box = _box ?? await Hive.openBox(_boxName);
    
    if (!box.containsKey(id)) {
      await box.put(id, {
        'id': id,
        'text': text,
        'timestamp': timestamp,
      });
    }
  }

  /// Checks if a message has already been received.
  /// Crucial for Gossip Loop Prevention to avoid infinite network storms.
  Future<bool> hasBroadcast(String id) async {
    final box = _box ?? await Hive.openBox(_boxName);
    return box.containsKey(id);
  }

  /// Retrieves the historical list of messages for the UI, sorted by timestamp descending.
  Future<List<Map<String, dynamic>>> getAllBroadcasts() async {
    final box = _box ?? await Hive.openBox(_boxName);
    
    // Hive stores JSON-like maps as Map<dynamic, dynamic>, requiring a cast.
    final broadcasts = box.values.map((e) {
      final map = e as Map;
      return {
        'id': map['id'] as String,
        'text': map['text'] as String,
        'timestamp': map['timestamp'] as int,
      };
    }).toList();

    // Sort descending by timestamp (newest first)
    broadcasts.sort((a, b) => (b['timestamp'] as int).compareTo(a['timestamp'] as int));
    
    return broadcasts;
  }
}
