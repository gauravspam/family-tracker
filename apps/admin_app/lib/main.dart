import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:provider/provider.dart';

import 'api/relay_api.dart';
import 'api/traccar_api.dart';
import 'auth/auth_controller.dart';
import 'auth/session_storage.dart';
import 'auth/traccar_auth.dart';
import 'config/server_config.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'screens/server_setup_screen.dart';
import 'services/connectivity_monitor.dart';
import 'services/fcm_service.dart';
import 'state/devices_controller.dart';
import 'state/geofences_controller.dart';
import 'state/hidden_devices_controller.dart';
import 'state/pending_controller.dart';
import 'state/theme_controller.dart';
import 'utils/crash_log.dart';
import 'ws/traccar_socket.dart';

/// Top-level background message handler (must not be a class method).
@pragma('vm:entry-point')
Future<void> _firebaseBgHandler(RemoteMessage message) async {
  final data = message.data;
  final title = data['title'] ?? 'Geofence Alert';
  final body = data['body'] ?? '';

  final plugin = FlutterLocalNotificationsPlugin();
  const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
  await plugin.initialize(const InitializationSettings(android: androidSettings));

  await plugin.show(
    DateTime.now().millisecondsSinceEpoch ~/ 1000,
    title,
    body,
    const NotificationDetails(
      android: AndroidNotificationDetails(
        'geofence_alerts',
        'Geofence Alerts',
        channelDescription: 'When a family member enters or exits a geofence',
        importance: Importance.high,
        priority: Priority.high,
        playSound: true,
        enableVibration: true,
        icon: '@mipmap/ic_launcher',
      ),
    ),
  );
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Register background handler before Firebase init
  FirebaseMessaging.onBackgroundMessage(_firebaseBgHandler);

  try {
    await FcmService.init();
  } catch (_) {
    // Firebase unavailable — FCM alerts won't work, app continues normally.
  }
  try {
    await CrashLog.init();
  } catch (_) {
    // Crash reporting unavailable — app continues normally.
  }
  runApp(const AdminApp());
}

class AdminApp extends StatefulWidget {
  const AdminApp({super.key});

  @override
  State<AdminApp> createState() => _AdminAppState();
}

class _AdminAppState extends State<AdminApp> {
  ServerUrls? _urls;
  final _themeController = ThemeController();
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final urls = await ServerConfig().load();
    setState(() {
      _urls = urls;
      _loaded = true;
    });
  }

  void _onServerChanged(ServerUrls urls) {
    setState(() => _urls = urls);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _themeController,
      builder: (context, _) => _buildApp(context),
    );
  }

  Widget _buildApp(BuildContext context) {
    final theme = ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF007AFF), // iOS system blue
        brightness: Brightness.light,
      ),
      useMaterial3: true,
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      ),
      dividerTheme: const DividerThemeData(space: 0, thickness: 0.5),
    );
    final darkTheme = ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF0A84FF), // iOS system blue dark
        brightness: Brightness.dark,
      ),
      useMaterial3: true,
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        color: const Color(0xFF1C1C1E), // iOS dark card
      ),
      dividerTheme: const DividerThemeData(space: 0, thickness: 0.5),
      scaffoldBackgroundColor: Colors.black,
    );

    if (!_loaded) {
      return MaterialApp(
        title: 'Family Tracker Admin',
        theme: theme,
        darkTheme: darkTheme,
        themeMode: _themeController.mode,
        home: const Scaffold(body: Center(child: CircularProgressIndicator())),
      );
    }

    if (_urls == null) {
      return MaterialApp(
        title: 'Family Tracker Admin',
        theme: theme,
        darkTheme: darkTheme,
        themeMode: _themeController.mode,
        home: ServerSetupScreen(
          onSaved: _onServerChanged,
        ),
      );
    }

    return _ConfiguredApp(
      key: ValueKey('${_urls!.relayBaseUrl}|${_urls!.traccarBaseUrl}'),
      urls: _urls!,
      onServerChanged: _onServerChanged,
      theme: theme,
      darkTheme: darkTheme,
      themeController: _themeController,
    );
  }
}

/// Builds the provider tree bound to a specific set of server URLs.
/// When URLs change, a new instance replaces the old (via ValueKey) so all
/// clients are rebuilt cleanly with the new endpoints.
class _ConfiguredApp extends StatefulWidget {
  final ServerUrls urls;
  final void Function(ServerUrls) onServerChanged;
  final ThemeData theme;
  final ThemeData darkTheme;
  final ThemeController themeController;

  const _ConfiguredApp({
    super.key,
    required this.urls,
    required this.onServerChanged,
    required this.theme,
    required this.darkTheme,
    required this.themeController,
  });

  @override
  State<_ConfiguredApp> createState() => _ConfiguredAppState();
}

class _ConfiguredAppState extends State<_ConfiguredApp> {
  late final SessionStorage _sessionStorage;
  late final TraccarApi _traccarApi;
  late final RelayApi _relayApi;
  late final TraccarSocket _socket;
  late final ConnectivityMonitor _connectivity;

  @override
  void initState() {
    super.initState();
    _sessionStorage = SessionStorage();
    _traccarApi = TraccarApi(
      baseUrl: widget.urls.traccarBaseUrl,
      storage: _sessionStorage,
    );
    _relayApi = RelayApi(
      baseUrl: widget.urls.relayBaseUrl,
      storage: _sessionStorage,
    );
    _socket = TraccarSocket(
      wsUrl: widget.urls.traccarWsUrl,
      storage: _sessionStorage,
    );
    _connectivity = ConnectivityMonitor(widget.urls.relayBaseUrl);
  }

  @override
  void dispose() {
    _connectivity.dispose();
    _socket.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<SessionStorage>.value(value: _sessionStorage),
        Provider<TraccarApi>.value(value: _traccarApi),
        Provider<RelayApi>.value(value: _relayApi),
        Provider<ServerUrls>.value(value: widget.urls),
        Provider<void Function(ServerUrls)>.value(value: widget.onServerChanged),
        ChangeNotifierProvider(
          create: (_) => AuthController(
            storage: _sessionStorage,
            traccar: TraccarAuth(widget.urls.traccarBaseUrl),
          ),
        ),
        ChangeNotifierProvider(create: (_) => DevicesController(_traccarApi, _relayApi)),
        ChangeNotifierProvider(create: (_) => PendingController(_relayApi)),
        ChangeNotifierProvider<TraccarSocket>.value(value: _socket),
        ChangeNotifierProvider<ConnectivityMonitor>.value(value: _connectivity),
        ChangeNotifierProvider<ThemeController>.value(value: widget.themeController),
        ChangeNotifierProvider(create: (_) => GeofencesController(_traccarApi)),
        ChangeNotifierProvider(create: (_) => HiddenDevicesController()),
      ],
      child: MaterialApp(
        title: 'Family Tracker Admin',
        theme: widget.theme,
        darkTheme: widget.darkTheme,
        themeMode: widget.themeController.mode,
        navigatorKey: FcmService.navigatorKey,
        home: const _RootRouter(),
      ),
    );
  }
}

class _RootRouter extends StatefulWidget {
  const _RootRouter();

  @override
  State<_RootRouter> createState() => _RootRouterState();
}

class _RootRouterState extends State<_RootRouter> {
  StreamSubscription<List<Map<String, dynamic>>>? _posSub;
  StreamSubscription<void>? _unauthSub;
  bool _wired = false;

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthController>(
      builder: (context, auth, _) {
        _wireLiveUpdates(auth);
        switch (auth.phase) {
          case AuthPhase.checking:
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          case AuthPhase.loggedOut:
            return const LoginScreen();
          case AuthPhase.loggedIn:
            return const HomeScreen();
        }
      },
    );
  }

  void _wireLiveUpdates(AuthController auth) {
    final socket = context.read<TraccarSocket>();
    final devices = context.read<DevicesController>();
    final pending = context.read<PendingController>();
    final authController = context.read<AuthController>();

    if (auth.phase == AuthPhase.loggedIn && !_wired) {
      _wired = true;

      _posSub = socket.positions.listen(devices.applyLivePositions);
      _unauthSub = socket.unauthorized.listen((_) => authController.logout());

      context.read<ConnectivityMonitor>().start();

      // Capture relay API reference before the async gap.
      final relay = context.read<RelayApi>();
      Future.microtask(() async {
        try {
          await devices.refresh();
        } on TraccarUnauthorized {
          await authController.logout();
          return;
        }
        try {
          await pending.refresh();
        } on RelayUnauthorized {
          await authController.logout();
          return;
        }
        await socket.connect();
        _registerFcm(relay);
      });
    } else if (auth.phase == AuthPhase.loggedOut && _wired) {
      _wired = false;
      _posSub?.cancel();
      _unauthSub?.cancel();
      context.read<ConnectivityMonitor>().stop();
      socket.disconnect();
    }
  }

  void _registerFcm(RelayApi relay) {
    final token = FcmService.token;
    if (token == null) return;
    relay.registerFcmToken(token).catchError((_) {});
  }

  @override
  void dispose() {
    _posSub?.cancel();
    _unauthSub?.cancel();
    super.dispose();
  }
}
