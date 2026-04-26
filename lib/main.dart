import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:permission_handler/permission_handler.dart';
import 'features/ui/main_navigation_screen.dart';
import 'providers/crypto_providers.dart';
import 'core/crypto/crypto.dart';
import 'core/security/identity_service.dart';
import 'providers/network_providers.dart';



Future<void> main() async {
  // 1. Ensure bindings are initialized before executing async configuration.
  WidgetsFlutterBinding.ensureInitialized();
  
  // 2. Synchronously initialize the local database for Public Alerts.
  await Hive.initFlutter();
  await Hive.openBox<dynamic>('public_broadcasts'); 

  // 3. Initialize Identity Service (Persistent ID)
  final identity = IdentityService();
  await identity.init();

  // 4. Initialize the entire crypto stack (Using Persistent Identity)
  final ecdh = await EcdhManager.create(identity.keyPair);
  final keyRotation = KeyRotationManager(ecdh);
  // Rotation is disabled in EcdhManager, but we keep the manager for cleanup logic.




  final container = ProviderContainer(
    overrides: [
      ecdhManagerProvider.overrideWithValue(ecdh),
      keyRotationProvider.overrideWithValue(keyRotation),
      identityServiceProvider.overrideWithValue(identity),
    ],

  );

  runApp(
    // 4. Wrap the root App in an UncontrolledProviderScope.
    UncontrolledProviderScope(
      container: container,
      child: const OfflineMeshApp(),
    ),
  );
}


class OfflineMeshApp extends StatelessWidget {
  const OfflineMeshApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Offline Mesh Communication',
      debugShowCheckedModeBanner: false,
      // Maintain the dark, high-contrast Material 3 theme.
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorSchemeSeed: Colors.blueAccent,
        scaffoldBackgroundColor: const Color(0xFF121212),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF1E1E1E),
          elevation: 0,
        ),
        floatingActionButtonTheme: const FloatingActionButtonThemeData(
          backgroundColor: Colors.blueAccent,
          foregroundColor: Colors.white,
        ),
      ),
      home: const InitializationScreen(),
    );
  }
}

/// Initialization widget that checks and requests critical permissions
/// before granting access to the MainNavigationScreen shell.
class InitializationScreen extends StatefulWidget {
  const InitializationScreen({super.key});

  @override
  State<InitializationScreen> createState() => _InitializationScreenState();
}

class _InitializationScreenState extends State<InitializationScreen> {
  bool _isLoading = true;
  String _statusMessage = 'Requesting hardware permissions...';
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _requestPermissions();
  }

  Future<void> _requestPermissions() async {
    try {
      if (Platform.isWindows) {
        // Windows doesn't require runtime permission prompts for Wi-Fi sockets.
        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute<void>(builder: (_) => const MainNavigationScreen()),
          );
        }
        return;
      }

      Map<Permission, PermissionStatus> statuses;

      if (Platform.isAndroid) {

        // Wi-Fi Mesh requires Location and Nearby Wifi (Android 13+)
        statuses = await [
          Permission.location,
          Permission.nearbyWifiDevices,
          Permission.camera,   // Required for QR fallback
        ].request();
      } else {
        // iOS permissions
        statuses = await [
          Permission.camera,
        ].request();
      }

      // Check if any critical permission was permanently denied
      bool allGranted = true;
      for (var status in statuses.values) {
        if (!status.isGranted) {
          allGranted = false;
          break;
        }
      }

      if (allGranted) {
        // Navigate to the dual-mode MainNavigationScreen
        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute<void>(builder: (_) => const MainNavigationScreen()),
          );
        }
      } else {
        setState(() {
          _isLoading = false;
          _hasError = true;
          _statusMessage = 'CRITICAL ERROR: Core permissions denied.\n\nOffline Mesh requires Wi-Fi and Camera access to function in a blackout scenario. Please enable them in system settings.';
        });
      }

    } catch (e) {
      setState(() {
        _isLoading = false;
        _hasError = true;
        _statusMessage = 'Failed to initialize hardware: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.security, size: 64, color: Colors.blueAccent),
              const SizedBox(height: 32),
              Text(
                'OFFLINE MESH',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 48),
              if (_isLoading) ...[
                const CircularProgressIndicator(),
                const SizedBox(height: 24),
              ],
              Text(
                _statusMessage,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: _hasError ? Colors.redAccent : Colors.grey,
                  height: 1.5,
                ),
              ),
              if (_hasError) ...[
                const SizedBox(height: 32),
                ElevatedButton.icon(
                  onPressed: () => openAppSettings(),
                  icon: const Icon(Icons.settings),
                  label: const Text('OPEN SETTINGS'),
                ),
              ]
            ],
          ),
        ),
      ),
    );
  }
}
