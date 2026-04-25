import 'package:flutter_test/flutter_test.dart';
import 'package:offline_mesh_app/features/messaging/fragmentation_engine.dart';
import 'package:offline_mesh_app/features/qr/qr_payload_manager.dart';

void main() {
  group('Application Logic & QR Payload Tests', () {
    test('FragmentationEngine_SplitsAndReassembles', () {
      final engine = FragmentationEngine();
      final plaintext = 'A' * 100; // Exact 100-character test string
      
      // Execute the 40-30-30 split
      final chunks = engine.splitMessage(plaintext);
      
      expect(chunks.length, 3, reason: 'Message must be split into exactly 3 chunks');
      
      // Verify length constraints
      expect(chunks[0].length, 40, reason: 'Chunk 0 should be 40%');
      expect(chunks[1].length, 30, reason: 'Chunk 1 should be 30%');
      expect(chunks[2].length, 30, reason: 'Chunk 2 should be 30%');
      
      final chunksMap = {
        0: chunks[0],
        1: chunks[1],
        2: chunks[2],
      };
      
      // Reassemble and verify integrity
      final reassembled = engine.reassembleMessage(chunksMap);
      expect(reassembled, equals(plaintext), reason: 'Reassembled string must perfectly match the original plaintext');
    });

    test('QrPayloadManager_EncodesAndDecodesBase64Gzip', () {
      final qrManager = QrPayloadManager();
      
      // Create a dummy EncryptedFragment JSON map
      final Map<String, dynamic> dummyFragmentJson = {
        'id': 'test-set-id-123',
        'i': 1,
        't': 3,
        'w': 'mock-wire-bytes-base64',
        'h': 'mock-hmac-tag-base64',
        'ts': 1690000000000,
        'ttl': 300000,
        'hop': 0,
      };
      
      // Encode
      final encodedPayload = qrManager.encodeForQr(dummyFragmentJson);
      
      // Assert output is a valid Base64 string and non-empty
      expect(encodedPayload, isNotEmpty);
      expect(() => qrManager.decodeFromQr(encodedPayload), returnsNormally);
      
      // Decode
      final decodedMap = qrManager.decodeFromQr(encodedPayload);
      
      // Verify fields survived compression and decoding
      expect(decodedMap['id'], equals('test-set-id-123'));
      expect(decodedMap['i'], equals(1));
      expect(decodedMap['t'], equals(3));
      expect(decodedMap['w'], equals('mock-wire-bytes-base64'));
    });
  });
}
