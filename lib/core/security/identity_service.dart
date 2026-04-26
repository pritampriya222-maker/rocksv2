import 'dart:convert';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:shared_preferences/shared_preferences.dart';

class IdentityService {
  static const _keyNodeId = 'mesh_node_id';
  static const _keyPrivateKey = 'mesh_private_key';

  String? _cachedNodeId;
  KeyPair? _cachedKeyPair;

  final _algorithm = X25519();

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    
    // Load or generate Node ID
    _cachedNodeId = prefs.getString(_keyNodeId);
    if (_cachedNodeId == null) {
      _cachedNodeId = 'Node_${DateTime.now().millisecondsSinceEpoch % 1000000}';
      await prefs.setString(_keyNodeId, _cachedNodeId!);
    }

    // Load or generate KeyPair
    final privKeyB64 = prefs.getString(_keyPrivateKey);
    if (privKeyB64 != null) {
      final privBytes = base64.decode(privKeyB64);
      _cachedKeyPair = await _algorithm.newKeyPairFromSeed(privBytes);
    } else {
      _cachedKeyPair = await _algorithm.newKeyPair();
      final priv = await _cachedKeyPair!.extract();
      await prefs.setString(_keyPrivateKey, base64.encode((priv as SimpleKeyPairData).bytes));
    }


  }

  String get nodeId => _cachedNodeId ?? 'Unknown';
  KeyPair get keyPair => _cachedKeyPair!;
  
  Future<Uint8List> get publicKeyBytes async {
    final pk = await _cachedKeyPair!.extractPublicKey();
    return Uint8List.fromList((pk as SimplePublicKey).bytes);
  }


  Future<void> nuclearWipe() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    _cachedNodeId = null;
    _cachedKeyPair = null;
  }
}
