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
  
  // 2. Synchronously initialize the local database for all features.
  await Hive.initFlutter();
  await Hive.openBox<dynamic>('public_broadcasts'); 
  await Hive.openBox<dynamic>('local_news');
  await Hive.openBox<dynamic>('safe_routes');

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
          backgroundColor: Color(0xFF121212),
          elevation: 0,
        ),
        floatingActionButtonTheme: const FloatingActionButtonThemeData(
          backgroundColor: Colors.blueAccent,
          foregroundColor: Colors.white,
        ),
        cardTheme: CardThemeData(
          color: const Color(0xFF1E1E1E),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFF2A2A2A),
          hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.3)),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Colors.blueAccent, width: 1.5),
          ),
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

class _InitializationScreenState extends State<InitializationScreen>
    with SingleTickerProviderStateMixin {
  bool _isLoading = true;
  String _statusMessage = 'Initializing secure mesh...';
  bool _hasError = false;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _requestPermissions();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _requestPermissions() async {
    try {
      if (Platform.isWindows) {
        // Windows doesn't require runtime permission prompts for Wi-Fi sockets.
        await Future<void>.delayed(const Duration(milliseconds: 800));
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
      backgroundColor: const Color(0xFF0A0A0A),
      body: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Animated mesh icon
              AnimatedBuilder(
                animation: _pulseAnimation,
                builder: (context, child) {
                  return Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          Colors.blueAccent.withValues(alpha: 0.2 * _pulseAnimation.value),
                          Colors.transparent,
                        ],
                      ),
                    ),
                    child: Icon(
                      Icons.wifi_tethering,
                      size: 64,
                      color: Colors.blueAccent.withValues(alpha: _pulseAnimation.value),
                    ),
                  );
                },
              ),
              const SizedBox(height: 32),
              const Text(
                'OFFLINE MESH',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 4,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'RESILIENT COMMUNICATION',
                style: TextStyle(
                  fontSize: 11,
                  letterSpacing: 3,
                  color: Colors.blueAccent.withValues(alpha: 0.7),
                ),
              ),
              const SizedBox(height: 48),
              if (_isLoading) ...[
                SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.blueAccent.withValues(alpha: 0.6),
                  ),
                ),
                const SizedBox(height: 24),
              ],
              Text(
                _statusMessage,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: _hasError ? Colors.redAccent : Colors.grey,
                  height: 1.5,
                  fontSize: 12,
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
