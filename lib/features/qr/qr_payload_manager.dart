import 'dart:convert';
import 'dart:io';

/// Formats encrypted fragments for high-density QR code generation and decoding.
/// 
/// Employs GZIP compression and Base64 encoding to strictly fit within QR Code 
/// data limits (Version 40 max ~2953 bytes).
class QrPayloadManager {
  /// Serializes a JSON map to a string, compresses it with GZIP, and encodes it to Base64.
  String encodeForQr(Map<String, dynamic> encryptedFragmentJson) {
    // 1. Convert JSON Map to String
    final jsonStr = jsonEncode(encryptedFragmentJson);
    
    // 2. Encode to bytes
    final bytes = utf8.encode(jsonStr);
    
    // 3. Compress using standard GZIP
    final compressedBytes = GZipCodec().encode(bytes);
    
    // 4. Encode to Base64 for safe QR text payload
    return base64Encode(compressedBytes);
  }

  /// Decodes Base64 data, decompresses with GZIP, and parses back into a JSON Map.
  /// 
  /// Throws a FormatException if the scanned data is invalid or corrupted.
  Map<String, dynamic> decodeFromQr(String base64QrData) {
    try {
      // 1. Decode Base64 string back to compressed bytes
      final compressedBytes = base64Decode(base64QrData);
      
      // 2. Decompress bytes using GZIP
      final decompressedBytes = GZipCodec().decode(compressedBytes);
      
      // 3. Decode UTF-8 bytes to JSON string
      final jsonStr = utf8.decode(decompressedBytes);
      
      // 4. Parse string back to JSON Map
      return jsonDecode(jsonStr) as Map<String, dynamic>;
    } catch (e) {
      throw FormatException('Invalid QR code format or corrupted fragment data. Ensure the correct QR was scanned. Details: $e');
    }
  }
}
