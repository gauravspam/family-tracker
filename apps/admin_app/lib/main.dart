import 'dart:async';

import 'package:flutter/material.dart';
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
import 'state/devices_controller.dart';
import 'state/pending_controller.dart';
import 'ws/traccar_socket.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const AdminApp());
}

class AdminApp extends StatefulWidget {
  const AdminApp({super.key});

  @override
  State<AdminApp> createState() => _AdminAppState();
}

class _AdminAppState extends State<AdminApp> {
  ServerUrls? _urls;
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
    final theme = ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: Colors.blue,
        brightness: Brightness.light,
      ),
      useMaterial3: true,
    );
    final darkTheme = ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: Colors.blue,
        brightness: Brightness.dark,
      ),
      useMaterial3: true,
    );

    if (!_loaded) {
      return MaterialApp(
        title: 'Family Tracker Admin',
        theme: theme,
        darkTheme: darkTheme,
        themeMode: ThemeMode.system,
        home: const Scaffold(body: Center(child: CircularProgressIndicator())),
      );
    }

    if (_urls == null) {
      return MaterialApp(
        title: 'Family Tracker Admin',
        theme: theme,
        darkTheme: darkTheme,
        themeMode: ThemeMode.system,
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

  const _ConfiguredApp({
    super.key,
    required this.urls,
    required this.onServerChanged,
    required this.theme,
    required this.darkTheme,
  });

  @override
  State<_ConfiguredApp> createState() => _ConfiguredAppState();
}

class _ConfiguredAppState extends State<_ConfiguredApp> {
  late final SessionStorage _sessionStorage;
  late final TraccarApi _traccarApi;
  late final RelayApi _relayApi;
  late final TraccarSocket _socket;

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
  }

  @override
  void dispose() {
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
      ],
      child: MaterialApp(
        title: 'Family Tracker Admin',
        theme: widget.theme,
        darkTheme: widget.darkTheme,
        themeMode: ThemeMode.system,
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
      });
    } else if (auth.phase == AuthPhase.loggedOut && _wired) {
      _wired = false;
      _posSub?.cancel();
      _unauthSub?.cancel();
      socket.disconnect();
    }
  }

  @override
  void dispose() {
    _posSub?.cancel();
    _unauthSub?.cancel();
    super.dispose();
  }
}
