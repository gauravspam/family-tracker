import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'api/traccar_api.dart';
import 'auth/auth_controller.dart';
import 'auth/session_storage.dart';
import 'auth/traccar_auth.dart';
import 'config.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'state/devices_controller.dart';
import 'ws/traccar_socket.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const AdminApp());
}

class AdminApp extends StatelessWidget {
  const AdminApp({super.key});

  @override
  Widget build(BuildContext context) {
    final sessionStorage = SessionStorage();
    final traccarApi = TraccarApi(
      baseUrl: AppConfig.traccarBaseUrl,
      storage: sessionStorage,
    );
    final socket = TraccarSocket(
      wsUrl: AppConfig.traccarWsUrl,
      storage: sessionStorage,
    );

    return MultiProvider(
      providers: [
        Provider<SessionStorage>.value(value: sessionStorage),
        Provider<TraccarApi>.value(value: traccarApi),
        ChangeNotifierProvider(
          create: (_) => AuthController(
            storage: sessionStorage,
            traccar: TraccarAuth(AppConfig.traccarBaseUrl),
          ),
        ),
        ChangeNotifierProvider(
          create: (_) => DevicesController(traccarApi),
        ),
        ChangeNotifierProvider<TraccarSocket>.value(value: socket),
      ],
      child: MaterialApp(
        title: 'Family Tracker Admin',
        theme: ThemeData(
          colorSchemeSeed: Colors.blue,
          useMaterial3: true,
        ),
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
    final authController = context.read<AuthController>();

    if (auth.phase == AuthPhase.loggedIn && !_wired) {
      _wired = true;

      _posSub = socket.positions.listen((positions) {
        devices.applyLivePositions(positions);
      });

      _unauthSub = socket.unauthorized.listen((_) {
        authController.logout();
      });

      // Initial fetch + connect
      Future.microtask(() async {
        try {
          await devices.refresh();
        } on TraccarUnauthorized {
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
