import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/crypto/crypto.dart';

// =============================================================================
// CRYPTO LAYER PROVIDERS
//
// Dependency graph:
//
//   ecdhManagerProvider
//       └─► keyRotationProvider
//       └─► fragmentServiceProvider (via aesCipherProvider + hmacUtilProvider)
//
// All providers are kept alive for the app lifetime.
// On app shutdown, keyRotationProvider.stop() zeroizes everything.
// =============================================================================

// -----------------------------------------------------------------------------
// EcdhManager
// -----------------------------------------------------------------------------

/// Singleton [EcdhManager] — created asynchronously (needs async init).
///
/// Use [ecdhManagerProvider] in a widget/service that already awaits
/// [appCryptoInitProvider].
final ecdhManagerProvider = Provider<EcdhManager>((ref) {
  // EcdhManager.create() is called via appCryptoInitProvider.
  // This provider is overridden once init completes.
  throw UnimplementedError(
    'ecdhManagerProvider must be overridden after async init.',
  );
});

// -----------------------------------------------------------------------------
// KeyRotationManager
// -----------------------------------------------------------------------------

/// Singleton [KeyRotationManager] — wired to the [EcdhManager].
///
/// Automatically starts timers and exposes [onRotation] stream.
/// Call [ref.read(keyRotationProvider).stop()] on app teardown.
final keyRotationProvider = Provider<KeyRotationManager>((ref) {
  throw UnimplementedError(
    'keyRotationProvider must be overridden after async init.',
  );
});

// -----------------------------------------------------------------------------
// AesCipher & HmacUtil
// -----------------------------------------------------------------------------

/// Shared [AesCipher] instance — stateless, safe to reuse.
final aesCipherProvider = Provider<AesCipher>((_) => AesCipher());

/// Shared [HmacUtil] instance — stateless, safe to reuse.
final hmacUtilProvider = Provider<HmacUtil>((_) => HmacUtil());

// -----------------------------------------------------------------------------
// FragmentService
// -----------------------------------------------------------------------------

/// [FragmentService] — uses [AesCipher] and [HmacUtil] internally.
final fragmentServiceProvider =
    Provider<FragmentService>((_) => FragmentService());

// -----------------------------------------------------------------------------
// ASYNC INITIALIZER
// -----------------------------------------------------------------------------

/// Async provider that initialises the entire crypto stack at startup.
///
/// Usage in [main()]:
/// ```dart
/// void main() async {
///   WidgetsFlutterBinding.ensureInitialized();
///   final container = ProviderContainer();
///   await container.read(appCryptoInitProvider.future);
///   runApp(
///     UncontrolledProviderScope(
///       container: container,
///       child: const OfflineMeshApp(),
///     ),
///   );
/// }
/// ```
///
/// Alternatively, override providers inside [ProviderScope.overrides] after
/// awaiting the future in a loading screen.
final appCryptoInitProvider = FutureProvider<void>((ref) async {
  final ecdh = await EcdhManager.create();

  // Override the placeholder providers with real instances
  // Note: Direct override not possible in Riverpod without container access.
  // Instead, this provider is used as a readiness flag; concrete instances
  // are injected via ProviderScope.overrides in main() — see below.
  ref.onDispose(() async {
    await ecdh.disposeAllSessions();
  });
});
