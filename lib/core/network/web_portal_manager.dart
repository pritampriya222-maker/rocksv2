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
import '../models/news_post.dart';
import '../models/safe_route.dart';

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

    _server = await io.serve(handler, InternetAddress.anyIPv4, 9000);
    print('[WebPortal] Listening on http://${_server!.address.address}:9000');


    // Bridge Mesh -> Web
    _meshManager.fragmentStream.listen(_onMeshFragment);
    _meshManager.alertStream.listen(_onMeshAlerts);
    _meshManager.newsStream.listen(_onMeshNews);
    _meshManager.routeStream.listen(_onMeshRoutes);
  }

  void _handleWebSocket(WebSocketChannel socket) {
    _activeSockets.add(socket);
    print('[WebPortal] Laptop Connected');

    socket.stream.listen((data) {
      try {
        final json = jsonDecode(data as String);
        if (json['type'] == 'msg') {
          // Relay text as a broadcast alert to the mesh
          // (Simplified for demo — full implementation would fragment & encrypt)
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

  void _onMeshNews(List<NewsPost> news) {
    final payload = jsonEncode({
      'type': 'news',
      'data': news.map((n) => n.toJson()).toList(),
    });
    _broadcastToWeb(payload);
  }

  void _onMeshRoutes(List<SafeRoute> routes) {
    final payload = jsonEncode({
      'type': 'routes',
      'data': routes.map((r) => r.toJson()).toList(),
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
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>OFFLINE MESH | Web Portal</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            background: #0a0a0a;
            color: #e0e0e0;
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, monospace;
            min-height: 100vh;
        }
        .header {
            background: linear-gradient(135deg, rgba(66,133,244,0.08), rgba(138,43,226,0.05));
            border-bottom: 1px solid rgba(255,255,255,0.06);
            padding: 16px 24px;
            display: flex;
            align-items: center;
            justify-content: space-between;
        }
        .header-left { display: flex; align-items: center; gap: 12px; }
        .status-dot {
            width: 8px; height: 8px; border-radius: 50%;
            background: #ef5350;
            animation: pulse 1.5s infinite;
        }
        .status-dot.connected { background: #66bb6a; }
        @keyframes pulse { 0%,100% { opacity: 1; } 50% { opacity: 0.4; } }
        .header h1 { font-size: 16px; font-weight: 700; letter-spacing: 3px; color: #fff; }
        .header .sub { font-size: 10px; color: #666; letter-spacing: 1px; }
        .offline-badge {
            background: rgba(239,83,80,0.1);
            border: 1px solid rgba(239,83,80,0.3);
            color: #ef5350;
            font-size: 9px;
            padding: 4px 10px;
            border-radius: 12px;
            font-weight: 700;
            letter-spacing: 1px;
        }

        .main { display: grid; grid-template-columns: 1fr 1fr; gap: 16px; padding: 20px; max-width: 1200px; margin: 0 auto; }
        @media (max-width: 768px) { .main { grid-template-columns: 1fr; } }

        .panel {
            background: #141414;
            border: 1px solid rgba(255,255,255,0.06);
            border-radius: 12px;
            overflow: hidden;
        }
        .panel-header {
            padding: 12px 16px;
            border-bottom: 1px solid rgba(255,255,255,0.04);
            display: flex;
            align-items: center;
            gap: 8px;
            font-size: 11px;
            font-weight: 700;
            letter-spacing: 1.5px;
            color: #888;
        }
        .panel-header .icon { font-size: 14px; }
        .panel-body { padding: 12px; max-height: 350px; overflow-y: auto; }
        .panel-body::-webkit-scrollbar { width: 3px; }
        .panel-body::-webkit-scrollbar-thumb { background: #333; border-radius: 3px; }

        .alert-item {
            padding: 12px;
            margin-bottom: 8px;
            border-radius: 8px;
            border-left: 3px solid;
            background: rgba(255,255,255,0.02);
        }
        .alert-item.high { border-color: #ef5350; background: rgba(239,83,80,0.05); }
        .alert-item.medium { border-color: #ffc107; background: rgba(255,193,7,0.05); }
        .alert-item.low { border-color: #66bb6a; background: rgba(102,187,106,0.05); }
        .alert-sev { font-size: 9px; font-weight: 700; letter-spacing: 1px; margin-bottom: 6px; }
        .alert-text { font-size: 13px; line-height: 1.4; }
        .alert-time { font-size: 9px; color: #555; margin-top: 6px; }

        .news-item {
            padding: 12px;
            margin-bottom: 8px;
            border-radius: 8px;
            background: rgba(255,255,255,0.02);
            border: 1px solid rgba(255,255,255,0.04);
        }
        .news-cat {
            font-size: 9px;
            font-weight: 700;
            letter-spacing: 1px;
            padding: 2px 6px;
            border-radius: 3px;
            display: inline-block;
            margin-bottom: 6px;
        }
        .news-title { font-size: 14px; font-weight: 600; margin-bottom: 4px; }
        .news-body { font-size: 12px; color: #999; }
        .news-meta { font-size: 9px; color: #555; margin-top: 6px; }

        .route-item {
            padding: 12px;
            margin-bottom: 8px;
            border-radius: 8px;
            background: rgba(255,255,255,0.02);
            display: flex;
            align-items: center;
            gap: 12px;
        }
        .route-status {
            width: 36px; height: 36px;
            border-radius: 50%;
            display: flex;
            align-items: center;
            justify-content: center;
            font-size: 16px;
        }
        .route-status.safe { background: rgba(102,187,106,0.15); }
        .route-status.caution { background: rgba(255,167,38,0.15); }
        .route-status.blocked { background: rgba(239,83,80,0.15); }
        .route-path { font-size: 13px; font-weight: 600; }
        .route-arrow { color: #4FC3F7; margin: 0 6px; }
        .route-desc { font-size: 11px; color: #777; }

        .msg-item {
            padding: 10px 14px;
            margin-bottom: 6px;
            border-radius: 8px;
            background: rgba(66,133,244,0.06);
            border: 1px solid rgba(66,133,244,0.1);
            font-size: 13px;
        }

        .input-bar {
            position: fixed;
            bottom: 0;
            left: 0;
            right: 0;
            padding: 12px 24px;
            background: #0e0e0e;
            border-top: 1px solid rgba(255,255,255,0.06);
            display: flex;
            gap: 10px;
        }
        .input-bar input {
            flex: 1;
            background: #1a1a1a;
            border: 1px solid rgba(255,255,255,0.08);
            color: #fff;
            padding: 12px 16px;
            border-radius: 24px;
            outline: none;
            font-size: 13px;
        }
        .input-bar input:focus { border-color: rgba(66,133,244,0.4); }
        .input-bar button {
            background: #4285f4;
            border: none;
            color: #fff;
            padding: 10px 20px;
            border-radius: 24px;
            cursor: pointer;
            font-weight: 700;
            font-size: 12px;
            letter-spacing: 0.5px;
        }
        .input-bar button:hover { background: #5a9aff; }

        .empty { text-align: center; padding: 40px; color: #444; font-size: 11px; letter-spacing: 1px; }
        .count-badge {
            background: rgba(255,255,255,0.05);
            padding: 2px 8px;
            border-radius: 10px;
            font-size: 10px;
            margin-left: auto;
        }
        body { padding-bottom: 70px; }
    </style>
</head>
<body>
    <div class="header">
        <div class="header-left">
            <div class="status-dot" id="statusDot"></div>
            <div>
                <h1>OFFLINE MESH</h1>
                <div class="sub">WEB PORTAL — RESILIENT COMMUNICATION</div>
            </div>
        </div>
        <div class="offline-badge">⛔ NO INTERNET</div>
    </div>

    <div class="main">
        <div class="panel">
            <div class="panel-header">
                <span class="icon">⚠️</span> EMERGENCY ALERTS
                <span class="count-badge" id="alertCount">0</span>
            </div>
            <div class="panel-body" id="alertFeed">
                <div class="empty">Waiting for alerts from mesh...</div>
            </div>
        </div>

        <div class="panel">
            <div class="panel-header">
                <span class="icon">📰</span> LOCAL NEWS
                <span class="count-badge" id="newsCount">0</span>
            </div>
            <div class="panel-body" id="newsFeed">
                <div class="empty">Waiting for news from mesh...</div>
            </div>
        </div>

        <div class="panel">
            <div class="panel-header">
                <span class="icon">🗺️</span> SAFE ROUTES
                <span class="count-badge" id="routeCount">0</span>
            </div>
            <div class="panel-body" id="routeFeed">
                <div class="empty">Waiting for route reports...</div>
            </div>
        </div>

        <div class="panel">
            <div class="panel-header">
                <span class="icon">💬</span> MESH ACTIVITY
                <span class="count-badge" id="msgCount">0</span>
            </div>
            <div class="panel-body" id="msgFeed">
                <div class="empty">Waiting for mesh traffic...</div>
            </div>
        </div>
    </div>

    <div class="input-bar">
        <input type="text" id="input" placeholder="Type message to broadcast to mesh..." />
        <button onclick="sendMsg()">SEND</button>
    </div>

    <script>
        const ws = new WebSocket(`ws://${location.host}`);
        const severities = ['LOW', 'MEDIUM', 'HIGH'];
        const sevClass = ['low', 'medium', 'high'];
        const categories = ['SAFETY', 'MEDICAL', 'SUPPLIES', 'ROUTES', 'GENERAL'];
        const catColors = ['#4FC3F7', '#EF5350', '#66BB6A', '#FFA726', '#AAAAAA'];
        const routeStatuses = ['SAFE', 'CAUTION', 'BLOCKED'];
        const routeStatusClass = ['safe', 'caution', 'blocked'];
        const routeEmoji = ['✅', '⚠️', '🚫'];
        let alertItems = [], newsItems = [], routeItems = [], msgCount = 0;

        ws.onopen = () => {
            document.getElementById('statusDot').classList.add('connected');
            addMsg('🔗 Connected to phone mesh node');
        };
        ws.onclose = () => {
            document.getElementById('statusDot').classList.remove('connected');
            addMsg('❌ Disconnected from mesh');
        };
        ws.onmessage = (e) => {
            const json = JSON.parse(e.data);
            if (json.type === 'alerts') {
                json.data.forEach(a => addAlert(a));
            } else if (json.type === 'news') {
                json.data.forEach(n => addNews(n));
            } else if (json.type === 'routes') {
                json.data.forEach(r => addRoute(r));
            } else if (json.type === 'fragment') {
                addMsg(`📦 Fragment received: shard ${json.data.i+1}/${json.data.t}`);
            }
        };

        function addAlert(a) {
            if (alertItems.find(x => x.id === a.id)) return;
            alertItems.unshift(a);
            const feed = document.getElementById('alertFeed');
            if (alertItems.length === 1) feed.innerHTML = '';
            const div = document.createElement('div');
            const sev = a.sev || 0;
            div.className = `alert-item ${sevClass[sev]}`;
            div.innerHTML = `
                <div class="alert-sev" style="color:${sev===2?'#ef5350':sev===1?'#ffc107':'#66bb6a'}">${severities[sev]}</div>
                <div class="alert-text">${a.text}</div>
                <div class="alert-time">${new Date(a.ts).toLocaleTimeString()}</div>`;
            feed.prepend(div);
            document.getElementById('alertCount').textContent = alertItems.length;
        }

        function addNews(n) {
            if (newsItems.find(x => x.id === n.id)) return;
            newsItems.unshift(n);
            const feed = document.getElementById('newsFeed');
            if (newsItems.length === 1) feed.innerHTML = '';
            const div = document.createElement('div');
            const cat = n.cat || 4;
            div.className = 'news-item';
            div.innerHTML = `
                <span class="news-cat" style="background:${catColors[cat]}20;color:${catColors[cat]}">${categories[cat]}</span>
                <div class="news-title">${n.title}</div>
                ${n.body ? `<div class="news-body">${n.body}</div>` : ''}
                <div class="news-meta">${n.hop||0} hops • ${new Date(n.ts).toLocaleTimeString()}</div>`;
            feed.prepend(div);
            document.getElementById('newsCount').textContent = newsItems.length;
        }

        function addRoute(r) {
            if (routeItems.find(x => x.id === r.id)) return;
            routeItems.unshift(r);
            const feed = document.getElementById('routeFeed');
            if (routeItems.length === 1) feed.innerHTML = '';
            const div = document.createElement('div');
            const st = r.st || 0;
            div.className = 'route-item';
            div.innerHTML = `
                <div class="route-status ${routeStatusClass[st]}">${routeEmoji[st]}</div>
                <div>
                    <div class="route-path">${r.from} <span class="route-arrow">→</span> ${r.to}</div>
                    ${r.desc ? `<div class="route-desc">${r.desc}</div>` : ''}
                </div>`;
            feed.prepend(div);
            document.getElementById('routeCount').textContent = routeItems.length;
        }

        function addMsg(text) {
            msgCount++;
            const feed = document.getElementById('msgFeed');
            if (msgCount === 1) feed.innerHTML = '';
            const div = document.createElement('div');
            div.className = 'msg-item';
            div.textContent = text;
            feed.prepend(div);
            document.getElementById('msgCount').textContent = msgCount;
        }

        function sendMsg() {
            const input = document.getElementById('input');
            if (input.value.trim()) {
                ws.send(JSON.stringify({type: 'msg', text: input.value}));
                addMsg(`📤 You: ${input.value}`);
                input.value = '';
            }
        }
        document.getElementById('input').onkeypress = (e) => { if (e.key === 'Enter') sendMsg(); };
    </script>
</body>
</html>
''';
}
