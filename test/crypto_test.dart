import 'dart:convert';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_mesh_app/core/crypto/crypto.dart';
import 'package:offline_mesh_app/core/models/message_fragment.dart';

void main() {
  // ===========================================================================
  // SecureMemory
  // ===========================================================================

  group('SecureMemory', () {
    test('zeroize overwrites all bytes to 0x00', () {
      final bytes = Uint8List.fromList([1, 2, 3, 4, 5]);
      SecureMemory.zeroize(bytes);
      expect(bytes.every((b) => b == 0), isTrue);
    });

    test('zeroize no-ops on empty list', () {
      expect(() => SecureMemory.zeroize([]), returnsNormally);
    });

    test('constantTimeEquals returns true for identical arrays', () {
      final a = [1, 2, 3, 4];
      final b = [1, 2, 3, 4];
      expect(SecureMemory.constantTimeEquals(a, b), isTrue);
    });

    test('constantTimeEquals returns false for different arrays', () {
      final a = [1, 2, 3, 4];
      final b = [1, 2, 3, 5];
      expect(SecureMemory.constantTimeEquals(a, b), isFalse);
    });

    test('constantTimeEquals returns false for different lengths', () {
      expect(SecureMemory.constantTimeEquals([1, 2], [1, 2, 3]), isFalse);
    });

    test('SecureBuffer disposes correctly', () {
      final buf = SecureBuffer(Uint8List.fromList([10, 20, 30]));
      expect(buf.isDisposed, isFalse);
      buf.dispose();
      expect(buf.isDisposed, isTrue);
      expect(() => buf.bytes, throwsStateError);
    });
  });

  // ===========================================================================
  // EcdhManager
  // ===========================================================================

  group('EcdhManager', () {
    test('generates 32-byte public key', () async {
      final mgr = await EcdhManager.create();
      final pub = mgr.getCurrentPublicKeyBytes();
      expect(pub.length, equals(CryptoConstants.x25519PublicKeyLength));
      await mgr.disposeAllSessions();
    });

    test('derives deterministic session key for same peer pubkey', () async {
      final alice = await EcdhManager.create();
      final bob = await EcdhManager.create();

      final alicePub = alice.getCurrentPublicKeyBytes();
      final bobPub = bob.getCurrentPublicKeyBytes();

      final keyFromBob = await alice.deriveSessionKey(
          remotePublicKeyBytes: bobPub);
      final keyFromAlice = await bob.deriveSessionKey(
          remotePublicKeyBytes: alicePub);

      final kbBytes = await keyFromBob.extractBytes();
      final kaBytes = await keyFromAlice.extractBytes();

      expect(kbBytes, equals(kaBytes),
          reason: 'ECDH must be commutative');

      await alice.disposeAllSessions();
      await bob.disposeAllSessions();
    });

    test('throws on disposed manager', () async {
      final mgr = await EcdhManager.create();
      await mgr.disposeAllSessions();
      expect(() => mgr.getCurrentPublicKeyBytes(), throwsStateError);
    });

    test('throws on invalid pubkey length', () async {
      final mgr = await EcdhManager.create();
      expect(
        () => mgr.deriveSessionKey(remotePublicKeyBytes: Uint8List(16)),
        throwsArgumentError,
      );
      await mgr.disposeAllSessions();
    });
  });

  // ===========================================================================
  // AesCipher
  // ===========================================================================

  group('AesCipher', () {
    late SecretKey sessionKey;
    late AesCipher cipher;

    setUp(() async {
      final alice = await EcdhManager.create();
      final bob = await EcdhManager.create();
      sessionKey = await alice.deriveSessionKey(
        remotePublicKeyBytes: bob.getCurrentPublicKeyBytes(),
      );
      cipher = AesCipher();
      await alice.disposeAllSessions();
      await bob.disposeAllSessions();
    });

    test('encrypt/decrypt roundtrip succeeds', () async {
      final plaintext = Uint8List.fromList(utf8.encode('Meet at checkpoint'));
      final box = await cipher.encryptFragment(
        plaintext: plaintext,
        sessionKey: sessionKey,
        sequenceNumber: 0,
      );
      final decrypted = await cipher.decryptFragment(
        secretBox: box,
        sessionKey: sessionKey,
        sequenceNumber: 0,
      );
      expect(decrypted, isNotNull);
      expect(utf8.decode(decrypted!), equals('Meet at checkpoint'));
    });

    test('decryptFragment returns null on wrong sequence number', () async {
      final box = await cipher.encryptFragment(
        plaintext: Uint8List.fromList(utf8.encode('test')),
        sessionKey: sessionKey,
        sequenceNumber: 0,
      );
      final result = await cipher.decryptFragment(
        secretBox: box,
        sessionKey: sessionKey,
        sequenceNumber: 1, // wrong
      );
      expect(result, isNull);
    });

    test('decryptFragment returns null on wrong key', () async {
      final wrongAlice = await EcdhManager.create();
      final wrongBob = await EcdhManager.create();
      final wrongKey = await wrongAlice.deriveSessionKey(
          remotePublicKeyBytes: wrongBob.getCurrentPublicKeyBytes());

      final box = await cipher.encryptFragment(
        plaintext: Uint8List.fromList(utf8.encode('test')),
        sessionKey: sessionKey,
        sequenceNumber: 0,
      );
      final result = await cipher.decryptFragment(
        secretBox: box,
        sessionKey: wrongKey,
        sequenceNumber: 0,
      );
      expect(result, isNull);

      await wrongAlice.disposeAllSessions();
      await wrongBob.disposeAllSessions();
    });

    test('secretBoxToBytes / bytesToSecretBox roundtrip', () async {
      final plaintext = Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8]);
      final box = await cipher.encryptFragment(
        plaintext: plaintext,
        sessionKey: sessionKey,
        sequenceNumber: 2,
      );
      final wire = cipher.secretBoxToBytes(box);
      final restored = cipher.bytesToSecretBox(wire);
      final decrypted = await cipher.decryptFragment(
        secretBox: restored,
        sessionKey: sessionKey,
        sequenceNumber: 2,
      );
      expect(decrypted, equals(plaintext));
    });
  });

  // ===========================================================================
  // HmacUtil
  // ===========================================================================

  group('HmacUtil', () {
    late SecretKey sessionKey;
    late HmacUtil hmac;

    setUp(() async {
      final alice = await EcdhManager.create();
      final bob = await EcdhManager.create();
      sessionKey = await alice.deriveSessionKey(
        remotePublicKeyBytes: bob.getCurrentPublicKeyBytes(),
      );
      hmac = HmacUtil();
      await alice.disposeAllSessions();
      await bob.disposeAllSessions();
    });

    test('compute and verify MAC succeeds with correct inputs', () async {
      final ciphertext = Uint8List.fromList([10, 20, 30, 40]);
      final mac = await hmac.computeFragmentMac(
        ciphertext: ciphertext,
        sessionKey: sessionKey,
        sequenceNumber: 1,
        ttlMs: 9999999,
      );
      final valid = await hmac.verifyFragmentMac(
        ciphertext: ciphertext,
        sessionKey: sessionKey,
        sequenceNumber: 1,
        ttlMs: 9999999,
        expectedMac: mac,
      );
      expect(valid, isTrue);
    });

    test('verifyFragmentMac fails with tampered ciphertext', () async {
      final ciphertext = Uint8List.fromList([10, 20, 30, 40]);
      final mac = await hmac.computeFragmentMac(
        ciphertext: ciphertext,
        sessionKey: sessionKey,
        sequenceNumber: 0,
        ttlMs: 1000,
      );
      ciphertext[0] ^= 0xFF; // tamper
      final valid = await hmac.verifyFragmentMac(
        ciphertext: ciphertext,
        sessionKey: sessionKey,
        sequenceNumber: 0,
        ttlMs: 1000,
        expectedMac: mac,
      );
      expect(valid, isFalse);
    });
  });

  // ===========================================================================
  // FragmentService (40-30-30 split + reassembly)
  // ===========================================================================

  group('FragmentService', () {
    late SecretKey sessionKey;
    late FragmentService fragmentService;

    setUp(() async {
      final alice = await EcdhManager.create();
      final bob = await EcdhManager.create();
      sessionKey = await alice.deriveSessionKey(
        remotePublicKeyBytes: bob.getCurrentPublicKeyBytes(),
      );
      fragmentService = FragmentService();
      await alice.disposeAllSessions();
      await bob.disposeAllSessions();
    });

    test('creates exactly 3 fragments', () async {
      final plaintext = Uint8List.fromList(
        utf8.encode('Meet at checkpoint Alpha at 0800'),
      );
      final fragments = await fragmentService.createFragments(
        plaintext: plaintext,
        sessionKey: sessionKey,
      );
      expect(fragments.length, equals(3));
    });

    test('all fragments share the same fragmentSetId', () async {
      final plaintext = Uint8List.fromList(utf8.encode('Test message'));
      final fragments = await fragmentService.createFragments(
        plaintext: plaintext,
        sessionKey: sessionKey,
      );
      final id = fragments.first.fragmentSetId;
      expect(fragments.every((f) => f.fragmentSetId == id), isTrue);
    });

    test('fragments have indices 0, 1, 2', () async {
      final plaintext = Uint8List.fromList(utf8.encode('Hello World'));
      final fragments = await fragmentService.createFragments(
        plaintext: plaintext,
        sessionKey: sessionKey,
      );
      expect(fragments.map((f) => f.index).toSet(), equals({0, 1, 2}));
    });

    test('reassembly returns original plaintext', () async {
      const original = 'Meet at checkpoint Alpha at 0800 hours';
      final plaintext = Uint8List.fromList(utf8.encode(original));
      final fragments = await fragmentService.createFragments(
        plaintext: plaintext,
        sessionKey: sessionKey,
      );
      final result = await fragmentService.reassembleFragments(
        fragments: fragments,
        sessionKey: sessionKey,
      );
      expect(result, equals(original));
    });

    test('reassembly returns null with wrong session key', () async {
      final plaintext = Uint8List.fromList(utf8.encode('Secret'));
      final fragments = await fragmentService.createFragments(
        plaintext: plaintext,
        sessionKey: sessionKey,
      );

      // Wrong key
      final eve = await EcdhManager.create();
      final mallory = await EcdhManager.create();
      final wrongKey = await eve.deriveSessionKey(
        remotePublicKeyBytes: mallory.getCurrentPublicKeyBytes(),
      );
      final result = await fragmentService.reassembleFragments(
        fragments: fragments,
        sessionKey: wrongKey,
      );
      expect(result, isNull);
      await eve.disposeAllSessions();
      await mallory.disposeAllSessions();
    });

    test('reassembly returns null with only 2 fragments', () async {
      final plaintext = Uint8List.fromList(utf8.encode('Incomplete'));
      final fragments = await fragmentService.createFragments(
        plaintext: plaintext,
        sessionKey: sessionKey,
      );
      final result = await fragmentService.reassembleFragments(
        fragments: fragments.sublist(0, 2),
        sessionKey: sessionKey,
      );
      expect(result, isNull);
    });

    test('fragment JSON round-trip preserves data', () async {
      final plaintext = Uint8List.fromList(utf8.encode('Round trip'));
      final fragments = await fragmentService.createFragments(
        plaintext: plaintext,
        sessionKey: sessionKey,
      );
      final fragment = fragments[0];
      final json = fragment.toJsonString();
      final restored = MessageFragment.fromJsonString(json);

      expect(restored.fragmentSetId, equals(fragment.fragmentSetId));
      expect(restored.index, equals(fragment.index));
      expect(restored.wireBytes, equals(fragment.wireBytes));
    });
  });
}
