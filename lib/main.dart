import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:permission_handler/permission_handler.dart';
import 'features/ui/main_navigation_screen.dart';

Future<void> main() async {
  // 1. Ensure bindings are initialized before executing async configuration.
  WidgetsFlutterBinding.ensureInitialized();
  
  // 2. Synchronously initialize the local database for Public Alerts.
  // This ensures the DatabaseService is ready the moment the UI paints.
  await Hive.initFlutter();
  await Hive.openBox<dynamic>('public_broadcasts'); 

  runApp(
    // 3. Wrap the root App in a ProviderScope for Riverpod state injection.
    const ProviderScope(
      child: OfflineMeshApp(),
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
      Map<Permission, PermissionStatus> statuses;

      if (Platform.isAndroid) {
        // Android 12+ requires specific Bluetooth permissions
        statuses = await [
          Permission.bluetoothScan,
          Permission.bluetoothAdvertise,
          Permission.bluetoothConnect,
          Permission.location, // Required for BLE scanning on Android
          Permission.camera,   // Required for QR fallback
        ].request();
      } else {
        // iOS permissions
        statuses = await [
          Permission.bluetooth,
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
          _statusMessage = 'CRITICAL ERROR: Core permissions denied.\n\nOffline Mesh requires Bluetooth and Camera access to function in a blackout scenario. Please enable them in system settings.';
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
