import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../network/wifi_mesh_manager.dart';
import '../models/message_fragment.dart';
import '../models/public_alert.dart';

class WebPortalManager {
  final WifiMeshManager _meshManager;
  final List<WebSocketChannel> _activeSockets = [];
  HttpServer? _server;

  WebPortalManager(this._meshManager);

  Future<void> start() async {
    final handler = Cascade()
        .add(webSocketHandler(_handleWebSocket))
        .add(_handleHttpRequest)
        .handler;

    _server = await io.serve(handler, InternetAddress.anyIPv4, 8080);
    print('[WebPortal] Listening on http://${_server!.address.address}:8080');

    // Bridge Mesh -> Web
    _meshManager.fragmentStream.listen(_onMeshFragment);
    _meshManager.alertStream.listen(_onMeshAlerts);
  }

  void _handleWebSocket(WebSocketChannel socket) {
    _activeSockets.add(socket);
    print('[WebPortal] Laptop Connected');

    socket.stream.listen((data) {
      try {
        final json = jsonDecode(data as String);
        if (json['type'] == 'msg') {
          // TODO: Implement Laptop -> Mesh relay logic
          // (Requires fragmentation engine access)
        }
      } catch (_) {}
    }, onDone: () => _activeSockets.remove(socket));
  }

  Response _handleHttpRequest(Request request) {
    if (request.url.path == '' || request.url.path == 'index.html') {
      return Response.ok(_portalHtml, headers: {'content-type': 'text/html'});
    }
    return Response.notFound('Not Found');
  }

  void _onMeshFragment(MessageFragment fragment) {
    final payload = jsonEncode({
      'type': 'fragment',
      'data': fragment.toJson(),
    });
    _broadcastToWeb(payload);
  }

  void _onMeshAlerts(List<PublicAlert> alerts) {
    final payload = jsonEncode({
      'type': 'alerts',
      'data': alerts.map((a) => a.toJson()).toList(),
    });
    _broadcastToWeb(payload);
  }

  void _broadcastToWeb(String data) {
    for (final socket in _activeSockets) {
      socket.sink.add(data);
    }
  }

  static const String _portalHtml = r'''
<!DOCTYPE html>
<html>
<head>
    <title>SPY-MESH | TERMINAL</title>
    <style>
        body { background: #000; color: #0f0; font-family: monospace; margin: 0; padding: 20px; overflow: hidden; }
        #terminal { border: 1px solid #0f0; height: 80vh; overflow-y: auto; padding: 10px; margin-bottom: 20px; box-shadow: 0 0 15px #0f03; }
        .msg { margin-bottom: 10px; border-left: 3px solid #0f0; padding-left: 10px; }
        .alert { color: #f00; border-color: #f00; }
        input { background: #000; border: 1px solid #0f0; color: #0f0; padding: 10px; width: 100%; box-sizing: border-box; outline: none; }
        h1 { font-size: 1.2rem; margin-top: 0; text-transform: uppercase; letter-spacing: 5px; }
    </style>
</head>
<body>
    <h1>SPY-MESH WEB PORTAL v1.0</h1>
    <div id="terminal">
        <div class="msg">SYSTEM: Waiting for handshake with Phone Mesh...</div>
    </div>
    <input type="text" id="input" placeholder="BROADCAST TO MESH..." />

    <script>
        const terminal = document.getElementById('terminal');
        const input = document.getElementById('input');
        const ws = new WebSocket(`ws://${location.host}`);

        ws.onopen = () => log('SYSTEM: SECURE LINK ESTABLISHED');
        ws.onmessage = (e) => {
            const json = JSON.parse(e.data);
            if (json.type === 'alerts') {
                json.data.forEach(a => log(`[ALERT] ${a.text}`, 'alert'));
            } else if (json.type === 'fragment') {
                log(`[FRAGMENT] Reassembling secure packet...`);
            }
        };

        function log(msg, className = '') {
            const div = document.createElement('div');
            div.className = 'msg ' + className;
            div.innerText = msg;
            terminal.appendChild(div);
            terminal.scrollTop = terminal.scrollHeight;
        }

        input.onkeypress = (e) => {
            if (e.key === 'Enter') {
                ws.send(JSON.stringify({type: 'msg', text: input.value}));
                log(`ME: ${input.value}`);
                input.value = '';
            }
        };
    </script>
</body>
</html>
''';
}
