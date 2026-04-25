import 'package:flutter_test/flutter_test.dart';
import 'package:cryptography/cryptography.dart';
import 'package:offline_mesh_app/core/crypto/aes_cipher.dart';
import 'dart:typed_data';

void main() {
  group('Cryptography Tests', () {
    test('KeyDerivation_YieldsIdenticalSharedSecrets', () async {
      // Setup X25519 algorithm
      final x25519 = X25519();
      
      // Generate two keypairs representing Alice and Bob
      final aliceKeyPair = await x25519.newKeyPair();
      final bobKeyPair = await x25519.newKeyPair();

      final alicePub = await aliceKeyPair.extractPublicKey();
      final bobPub = await bobKeyPair.extractPublicKey();

      // Alice derives session key using Bob's public key
      final aliceSharedSecret = await x25519.sharedSecretKey(
        keyPair: aliceKeyPair,
        remotePublicKey: bobPub,
      );

      // Bob derives session key using Alice's public key
      final bobSharedSecret = await x25519.sharedSecretKey(
        keyPair: bobKeyPair,
        remotePublicKey: alicePub,
      );

      // Extract raw bytes to verify mathematical identity
      final aliceBytes = await aliceSharedSecret.extractBytes();
      final bobBytes = await bobSharedSecret.extractBytes();

      expect(aliceBytes, equals(bobBytes), reason: 'Shared secrets must match identically on both ends');
    });

    test('AesGcmCipher_EncryptDecrypt_Success', () async {
      final cipher = AesCipher();
      final sessionKey = await AesGcm.with256bits().newSecretKey();
      
      final plaintext = Uint8List.fromList('Test secure message for demonstration'.codeUnits);
      
      // Encrypt the fragment
      final secretBox = await cipher.encryptFragment(
        plaintext: plaintext,
        sessionKey: sessionKey,
        sequenceNumber: 0,
      );
      
      // Decrypt the fragment successfully
      final decrypted = await cipher.decryptFragment(
        secretBox: secretBox,
        sessionKey: sessionKey,
        sequenceNumber: 0,
      );
      
      expect(decrypted, equals(plaintext), reason: 'Decrypted bytes should exactly match original plaintext');
      
      // Tamper with the ciphertext to simulate an attack or corruption
      final tamperedCiphertext = Uint8List.fromList(secretBox.cipherText);
      tamperedCiphertext[0] ^= 0xFF; // Flip bits in the first byte
      
      final tamperedBox = SecretBox(
        tamperedCiphertext,
        nonce: secretBox.nonce,
        mac: secretBox.mac,
      );
      
      // Assert that decryptFragment gracefully handles the SecretBoxAuthenticationError
      // Our implementation catches the error and returns null to prevent side-channel timing attacks
      final failedDecryption = await cipher.decryptFragment(
        secretBox: tamperedBox,
        sessionKey: sessionKey,
        sequenceNumber: 0,
      );
      
      expect(failedDecryption, isNull, reason: 'Tampered ciphertext must fail HMAC validation and return null');
    });
  });
}
