import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_mesh_app/core/ble/mesh_packet_router.dart';
import 'package:offline_mesh_app/core/ble/mesh_relay_controller.dart';
import 'package:offline_mesh_app/features/broadcast/gossip_controller.dart';

// --- FAKES FOR DEPENDENCY INJECTION ---

class FakeMeshRelayController implements MeshRelayController {
  bool wasCalled = false;
  List<int>? receivedData;

  @override
  Future<void> processIncomingFragment(List<int> rawData) async {
    wasCalled = true;
    receivedData = rawData;
  }

  // Gracefully ignore other unimplemented methods
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeGossipController implements GossipController {
  bool wasCalled = false;
  String? receivedJson;

  @override
  Future<void> onBroadcastReceived(String jsonPayload) async {
    wasCalled = true;
    receivedJson = jsonPayload;
  }

  // Gracefully ignore other unimplemented methods
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('Dual-Mode BLE Multiplexer Tests', () {
    late FakeMeshRelayController fakeRelay;
    late FakeGossipController fakeGossip;
    late MeshPacketRouter router;

    setUp(() {
      fakeRelay = FakeMeshRelayController();
      fakeGossip = FakeGossipController();
      router = MeshPacketRouter(
        relayController: fakeRelay,
        gossipController: fakeGossip,
      );
    });

    test('Encodes Private Secure Fragment correctly (0x01)', () {
      final rawData = [255, 128, 64];
      final encoded = MeshPacketRouter.encodePrivatePacket(rawData);
      
      expect(encoded.first, equals(0x01), reason: 'Must prepend 0x01 header for private mode');
      expect(encoded.sublist(1), equals(rawData), reason: 'Payload must remain intact');
    });

    test('Encodes Public Gossip Broadcast correctly (0x02)', () {
      final jsonStr = jsonEncode({"test": "alert"});
      final encoded = MeshPacketRouter.encodePublicPacket(jsonStr);
      
      expect(encoded.first, equals(0x02), reason: 'Must prepend 0x02 header for public mode');
      expect(utf8.decode(encoded.sublist(1)), equals(jsonStr), reason: 'JSON string must be correctly UTF-8 encoded');
    });

    test('Routes 0x01 packets strictly to MeshRelayController', () async {
      final rawData = [10, 20, 30];
      final packet = [0x01, ...rawData]; // 0x01 Header

      await router.routeIncomingData(packet);

      expect(fakeRelay.wasCalled, isTrue, reason: 'Private packet must trigger the secure relay controller');
      expect(fakeRelay.receivedData, equals(rawData));
      expect(fakeGossip.wasCalled, isFalse, reason: 'Gossip controller must NOT be called');
    });

    test('Routes 0x02 packets strictly to GossipController', () async {
      final jsonStr = jsonEncode({"id": "123", "text": "public alert"});
      final packet = [0x02, ...utf8.encode(jsonStr)]; // 0x02 Header

      await router.routeIncomingData(packet);

      expect(fakeGossip.wasCalled, isTrue, reason: 'Public packet must trigger the gossip controller');
      expect(fakeGossip.receivedJson, equals(jsonStr));
      expect(fakeRelay.wasCalled, isFalse, reason: 'Secure relay controller must NOT be called');
    });

    test('Gracefully ignores invalid headers', () async {
      final packet = [0xFF, 1, 2, 3]; // Unknown Header
      
      await router.routeIncomingData(packet);

      expect(fakeRelay.wasCalled, isFalse);
      expect(fakeGossip.wasCalled, isFalse);
    });
  });
}
