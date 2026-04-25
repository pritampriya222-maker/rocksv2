import 'package:flutter/material.dart';
import 'package:offline_mesh_app/features/messaging/messaging_screen.dart';
import 'package:offline_mesh_app/features/peers/peers_screen.dart';
import 'package:offline_mesh_app/features/qr/qr_screen.dart';
import 'package:offline_mesh_app/features/home/home_screen.dart';

/// Named route registry. All screens registered here.
class AppRouter {
  static const String home      = '/';
  static const String messaging = '/messaging';
  static const String peers     = '/peers';
  static const String qr        = '/qr';

  static Map<String, WidgetBuilder> get routes => {
    home:      (_) => const HomeScreen(),
    messaging: (_) => const MessagingScreen(),
    peers:     (_) => const PeersScreen(),
    qr:        (_) => const QrScreen(),
  };
}
