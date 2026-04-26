import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../features/qr/qr_payload_manager.dart';

final qrPayloadManagerProvider = Provider<QrPayloadManager>((ref) {
  return QrPayloadManager();
});
