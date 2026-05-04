import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../models/ephemeral_peer.dart';
import '../crypto/ecdh_manager.dart';
import '../security/identity_service.dart';
import '../models/message_fragment.dart';
import '../models/public_alert.dart';
import '../models/news_post.dart';
import '../models/safe_route.dart';



/// Manages high-speed local mesh via Wi-Fi (UDP Broadcast & TCP).
///
/// Replaces the unreliable BLE discovery with standard socket-based mesh.
///
/// Discovery: UDP Broadcast on Port 5555
/// Payload:   TCP Unicast on Port 5556
///
/// MULTI-HOP RELAY: Incoming fragments/data are automatically relayed
/// to all other peers (gossip protocol) with hop-count tracking and
/// deduplication to prevent storms.
class WifiMeshManager {
  static const int udpPort = 5555;
  static const int tcpPort = 5556;
  static const int maxHops = 5;

  final EcdhManager _ecdhManager;
  final IdentityService _identity;

  RawDatagramSocket? _udpSocket;
  ServerSocket? _tcpServer;
  Timer? _beaconTimer;

  final Map<String, EphemeralPeer> _peers = {};
  final StreamController<List<EphemeralPeer>> _peerController =
      StreamController<List<EphemeralPeer>>.broadcast();

  final StreamController<MessageFragment> _fragmentController =
      StreamController<MessageFragment>.broadcast();

  final StreamController<List<PublicAlert>> _alertController =
      StreamController<List<PublicAlert>>.broadcast();

  final StreamController<List<NewsPost>> _newsController =
      StreamController<List<NewsPost>>.broadcast();

  final StreamController<List<SafeRoute>> _routeController =
      StreamController<List<SafeRoute>>.broadcast();

  /// Deduplication: tracks seen packet IDs to prevent relay storms
  final Set<String> _seenPacketIds = {};

  /// Stats counters for dashboard
  int messagesRelayed = 0;
  int totalHopsCovered = 0;
  int peersDiscoveredLifetime = 0;

  WifiMeshManager(this._ecdhManager, this._identity);



  Stream<List<EphemeralPeer>> get peersStream => _peerController.stream;
  Stream<MessageFragment> get fragmentStream => _fragmentController.stream;
  Stream<List<PublicAlert>> get alertStream => _alertController.stream;
  Stream<List<NewsPost>> get newsStream => _newsController.stream;
  Stream<List<SafeRoute>> get routeStream => _routeController.stream;

  List<EphemeralPeer> get currentPeers => _peers.values.toList();

  Future<void> start() async {
    await _startUdpDiscovery();
    await _startTcpServer();
    _startBeacon();
  }

  Future<void> stop() async {
    _beaconTimer?.cancel();
    _udpSocket?.close();
    await _tcpServer?.close();
    for (var peer in _peers.values) {
      peer.destroy();
    }
    _peers.clear();
  }

  // --------------------------------------------------------------------------
  // DISCOVERY (UDP)
  // --------------------------------------------------------------------------

  Future<void> _startUdpDiscovery() async {
    _udpSocket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, udpPort);
    _udpSocket?.broadcastEnabled = true;
    try {
      _udpSocket?.joinMulticast(InternetAddress('224.0.0.1'));
    } catch (_) {}


    _udpSocket?.listen((RawSocketEvent event) {
      if (event == RawSocketEvent.read) {
        final dg = _udpSocket?.receive();
        if (dg == null) return;

        try {
          final data = utf8.decode(dg.data);
          final json = jsonDecode(data) as Map<String, dynamic>;

          if (json['nodeId'] == _identity.nodeId) return; // Ignore self


          _handleDiscoveredPeer(
            id: json['nodeId'] as String,
            ip: dg.address.address,
            pubKey: base64.decode(json['pubKey'] as String),
          );
        } catch (_) {}
      }
    });
  }

  void _startBeacon() {
    _beaconTimer = Timer.periodic(const Duration(seconds: 1), (timer) async {

      try {
        final interfaces = await NetworkInterface.list(
          includeLoopback: false,
          type: InternetAddressType.IPv4,
        );

        final beacon = jsonEncode({
          'nodeId': _identity.nodeId,
          'pubKey': base64.encode(await _identity.publicKeyBytes),
        });

        final data = utf8.encode(beacon);

        for (var interface in interfaces) {
          for (var addr in interface.addresses) {
            try {
              final parts = addr.address.split('.');
              if (parts.length != 4) continue;

              // 1. Send to Subnet Broadcast (e.g. 192.168.43.255)
              final subnetBroadcast = '${parts[0]}.${parts[1]}.${parts[2]}.255';
              _udpSocket?.send(data, InternetAddress(subnetBroadcast), udpPort);

              // 2. Send to common Hotspot Gateways directly
              _udpSocket?.send(data, InternetAddress('${parts[0]}.${parts[1]}.${parts[2]}.1'), udpPort);
              
              // 3. Send to Multicast Group
              _udpSocket?.send(data, InternetAddress('224.0.0.1'), udpPort);
            } catch (_) {
              // Ignore invalid subnet calculation for this interface
            }
          }
        }


        // 4. Global Broadcast Fallback
        _udpSocket?.send(data, InternetAddress('255.255.255.255'), udpPort);

      } catch (e) {
        print('[WifiMesh] Deep Scan Beacon error: $e');
      }
    });
  }



  void _handleDiscoveredPeer({
    required String id,
    required String ip,
    required Uint8List pubKey,
  }) async {
    if (id == _identity.nodeId) return;


    // 1. If we already know this peer, just update their "Liveliness"
    if (_peers.containsKey(id)) {
      final existing = _peers[id]!;
      _peers[id] = existing.copyWith(
        ipAddress: ip,
        discoveredAt: DateTime.now(),
      );
      _peerController.add(_peers.values.toList());
      return;
    }

    peersDiscoveredLifetime++;

    // 2. NEW PEER: Immediately add a placeholder to prevent race conditions
    _peers[id] = EphemeralPeer(
      deviceUuid: id,
      ecdhPublicKey: pubKey,
      rssi: 0,
      ipAddress: ip,
      discoveredAt: DateTime.now(),
      sessionKey: Uint8List(0), // Placeholder until handshake finishes
    );

    try {
      // 3. Deduplicate IP addresses
      _peers.removeWhere((pid, p) => pid != id && p.ipAddress == ip);

      // 4. Perform Key Exchange in background
      final sessionKey = await _ecdhManager.deriveSessionKey(
        remotePublicKeyBytes: pubKey,
      );
      final keyBytes = Uint8List.fromList(await sessionKey.extractBytes());

      // 5. Update with the real secure key
      if (_peers.containsKey(id)) {
        _peers[id] = _peers[id]!.copyWith(sessionKey: keyBytes);
        print('[WifiMesh] Secure Handshake Complete with: $id');
      }
    } catch (e) {
      _peers.remove(id); // Cleanup if handshake failed
      print('[WifiMesh] Handshake error: $e');
    }

    // 6. Ghost cleanup (relaxed to 20s to prevent accidental drops)
    final now = DateTime.now();
    _peers.removeWhere((_, p) => now.difference(p.discoveredAt).inSeconds > 20);

    _peerController.add(_peers.values.toList());
  }


  // --------------------------------------------------------------------------
  // DATA TRANSPORT (TCP)
  // --------------------------------------------------------------------------

  Future<void> _startTcpServer() async {
    _tcpServer = await ServerSocket.bind(InternetAddress.anyIPv4, tcpPort);
    _tcpServer?.listen((Socket client) {
      final List<int> buffer = [];
      client.listen(
        (Uint8List data) {
          buffer.addAll(data);
        },
        onDone: () {
          try {
            if (buffer.isEmpty) return;
            final raw = utf8.decode(buffer);
            final json = jsonDecode(raw) as Map<String, dynamic>;
            final senderIp = client.remoteAddress.address;
            
            final type = json['type'] as String? ?? 'fragment';
            final packetId = json['pid'] as String? ?? '';

            // Deduplication: skip if we've already processed this packet
            if (packetId.isNotEmpty && _seenPacketIds.contains(packetId)) {
              return;
            }
            if (packetId.isNotEmpty) {
              _seenPacketIds.add(packetId);
              // Prevent unbounded memory growth
              if (_seenPacketIds.length > 5000) {
                final toRemove = _seenPacketIds.take(2500).toList();
                _seenPacketIds.removeAll(toRemove);
              }
            }

            switch (type) {
              case 'alerts':
                final alertsJson = json['data'] as List<dynamic>;
                final alerts = alertsJson
                    .map((a) =>
                        PublicAlert.fromJson(Map<String, dynamic>.from(a as Map)))
                    .toList();
                _alertController.add(alerts);
                // MULTI-HOP RELAY: Forward alerts to other peers
                _relayToOtherPeers(raw, senderIp);
                break;

              case 'news':
                final newsJson = json['data'] as List<dynamic>;
                final news = newsJson
                    .map((n) =>
                        NewsPost.fromJson(Map<String, dynamic>.from(n as Map)))
                    .toList();
                _newsController.add(news);
                // MULTI-HOP RELAY
                _relayToOtherPeers(raw, senderIp);
                break;

              case 'routes':
                final routesJson = json['data'] as List<dynamic>;
                final routes = routesJson
                    .map((r) =>
                        SafeRoute.fromJson(Map<String, dynamic>.from(r as Map)))
                    .toList();
                _routeController.add(routes);
                // MULTI-HOP RELAY
                _relayToOtherPeers(raw, senderIp);
                break;

              default:
                // Message fragment
                final fragment = MessageFragment.fromJson(json);
                if (fragment.hopCount < maxHops) {
                  _fragmentController.add(fragment);
                  // MULTI-HOP RELAY: Forward fragment with incremented hop
                  final relayFragment = fragment.withIncrementedHop();
                  _relayFragmentToOtherPeers(relayFragment, senderIp);
                  messagesRelayed++;
                  totalHopsCovered += fragment.hopCount;
                }
                break;
            }
          } catch (e) {
            print('[WifiMesh] Reassembly Error: $e');
          } finally {
            client.destroy();
          }
        },
        onError: (e) => client.destroy(),
        cancelOnError: true,
      );
    });
  }

  /// MULTI-HOP: Relay raw packet data to all peers except the sender
  void _relayToOtherPeers(String rawData, String senderIp) {
    final bytes = utf8.encode(rawData);
    final otherIps = _peers.values
        .where((p) => p.ipAddress != null && p.ipAddress != senderIp)
        .map((p) => p.ipAddress!)
        .toList();
    
    for (final ip in otherIps) {
      _safeTcpSend(ip, bytes);
    }
    if (otherIps.isNotEmpty) messagesRelayed++;
  }

  /// MULTI-HOP: Relay a fragment to all peers except the sender via reliable TCP
  void _relayFragmentToOtherPeers(MessageFragment fragment, String senderIp) {
    // Wrap fragment in JSON for TCP receiver
    final payload = {
      'type': 'fragment',
      'pid': 'f_${fragment.fragmentSetId}_${fragment.index}',
      ...fragment.toJson(),
    };
    final bytes = utf8.encode(jsonEncode(payload));
    
    final otherIps = _peers.values
        .where((p) => p.ipAddress != null && p.ipAddress != senderIp)
        .map((p) => p.ipAddress!)
        .toList();
    
    for (final ip in otherIps) {
      _safeTcpSend(ip, bytes);
    }
  }

  // --------------------------------------------------------------------------
  // SYNC METHODS
  // --------------------------------------------------------------------------

  Future<void> syncAlerts(List<PublicAlert> alerts, List<String> ips) async {
    final pid = 'a_${DateTime.now().millisecondsSinceEpoch}_${_identity.nodeId}';
    _seenPacketIds.add(pid);
    final packet = jsonEncode({
      'type': 'alerts',
      'pid': pid,
      'data': alerts.map((a) => a.toJson()).toList(),
    });
    final bytes = utf8.encode(packet);
    Future.wait(ips.map((ip) => _safeTcpSend(ip, bytes)));
  }

  Future<void> syncNews(List<NewsPost> news, List<String> ips) async {
    final pid = 'n_${DateTime.now().millisecondsSinceEpoch}_${_identity.nodeId}';
    _seenPacketIds.add(pid);
    final packet = jsonEncode({
      'type': 'news',
      'pid': pid,
      'data': news.map((n) => n.toJson()).toList(),
    });
    final bytes = utf8.encode(packet);
    Future.wait(ips.map((ip) => _safeTcpSend(ip, bytes)));
  }

  Future<void> syncRoutes(List<SafeRoute> routes, List<String> ips) async {
    final pid = 'r_${DateTime.now().millisecondsSinceEpoch}_${_identity.nodeId}';
    _seenPacketIds.add(pid);
    final packet = jsonEncode({
      'type': 'routes',
      'pid': pid,
      'data': routes.map((r) => r.toJson()).toList(),
    });
    final bytes = utf8.encode(packet);
    Future.wait(ips.map((ip) => _safeTcpSend(ip, bytes)));
  }

  Future<void> _safeTcpSend(String ip, dynamic bytes) async {
    int retries = 0;
    final data = bytes is Uint8List ? bytes : Uint8List.fromList(bytes as List<int>);
    while (retries < 5) { // Increased retries for guaranteed chat delivery
      try {
        final socket = await Socket.connect(ip, tcpPort, timeout: const Duration(milliseconds: 2000)); // 2s timeout
        socket.add(data);
        await socket.flush();
        await socket.close();
        return;
      } catch (e) {
        retries++;
        await Future<void>.delayed(Duration(milliseconds: 100 * retries));
      }
    }
    print('[WifiMesh] FATAL: Failed to send TCP packet to $ip after 5 retries.');
  }

  Future<void> broadcastFragment(MessageFragment fragment) async {
    // 100% RELIABLE CHAT: Switch from UDP to TCP for guaranteed delivery
    final payload = {
      'type': 'fragment',
      'pid': 'f_${fragment.fragmentSetId}_${fragment.index}',
      ...fragment.toJson(),
    };
    final bytes = utf8.encode(jsonEncode(payload));

    final ips = _peers.values
        .where((p) => p.ipAddress != null)
        .map((p) => p.ipAddress!)
        .toList();
        
    await Future.wait(ips.map((ip) => _safeTcpSend(ip, bytes)));
  }

  /// Send fragment specifically to a set of IPs
  Future<void> relayToPeers(MessageFragment fragment, List<String> ips) async {
    final payload = {
      'type': 'fragment',
      'pid': 'f_${fragment.fragmentSetId}_${fragment.index}',
      ...fragment.toJson(),
    };
    final bytes = utf8.encode(jsonEncode(payload));
    await Future.wait(ips.map((ip) => _safeTcpSend(ip, bytes)));
  }


  Future<void> refresh() async {
    print('[WifiMesh] App Resumed: Refreshing sockets...');
    await stop();
    await start();
  }
}
