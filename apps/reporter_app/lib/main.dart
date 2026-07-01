import 'dart:io';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';


import 'config.dart';
import 'state.dart';
import 'storage.dart';
import 'permissions.dart';
import 'location_service.dart';
import 'polling_service.dart';
import 'reconcile.dart';
import 'fcm_handler.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ReporterApp());
}

class ReporterApp extends StatelessWidget {
  const ReporterApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Family Tracker',
      theme: ThemeData(
        colorSchemeSeed: Colors.blue,
        useMaterial3: true,
      ),
      home: const ReporterHome(),
    );
  }
}

class ReporterHome extends StatefulWidget {
  const ReporterHome({super.key});

  @override
  State<ReporterHome> createState() => _ReporterHomeState();
}

class _ReporterHomeState extends State<ReporterHome> with WidgetsBindingObserver {
  String _statusText = 'Initializing...';
  ReporterState _state = const ReporterState();
  bool _bootstrapping = false;

  late final LocationService _locationService;
  late final PollingService _pollingService;
  late final Reconciler _reconciler;
  late final FCMHandler _fcmHandler; // ignore: unused_field

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _locationService = LocationService();
    _pollingService = PollingService(
      relayBaseUrl: AppConfig.relayBaseUrl,
      onApproved: (state) {
        setState(() => _state = state);
        _reconciler.reconcile();
      },
    );
    _reconciler = Reconciler(
      locationService: _locationService,
      pollingService: _pollingService,
      onNotificationUpdate: (text) {
        if (mounted) setState(() => _statusText = text);
      },
    );
    _fcmHandler = FCMHandler(onReconcile: () => _reconciler.reconcile());

    _init();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _locationService.stop();
    _pollingService.stop();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _reconciler.reconcile();
    }
  }

  Future<void> _init() async {
    final state = await ReporterStorage.load();
    setState(() => _state = state);

    if (state.isApproved) {
      await _reconciler.reconcile();
      return;
    }

    if (state.approval == ApprovalStatus.removed) {
      setState(() => _statusText = 'Device removed');
      return;
    }

    // Pending or first launch — show setup button
    setState(() => _statusText = 'Tap "Set Up" to begin');
  }

  Future<void> _bootstrap() async {
    if (_bootstrapping) return;
    setState(() {
      _bootstrapping = true;
      _statusText = 'Requesting permissions...';
    });

    // Request permissions
    final result = await Permissions.requestAll();
    if (!result.allGranted) {
      setState(() {
        _bootstrapping = false;
        _statusText = result.missing ?? 'Permission denied';
      });
      return;
    }

    setState(() => _statusText = 'Registering device...');

    try {
      // Get device info
      final androidId = await _getAndroidId();
      final deviceModel = '${Platform.operatingSystem} device';

      await ReporterStorage.saveAndroidId(androidId);

      // Send join request
      final dio = Dio(BaseOptions(baseUrl: AppConfig.relayBaseUrl));
      await dio.post('/join', data: {
        'androidId': androidId,
        'deviceModel': deviceModel,
        'fcmToken': 'fcm-not-configured-yet',
        'osVersion': Platform.operatingSystemVersion,
      });

      // Save pending state
      const state = ReporterState(approval: ApprovalStatus.pending);
      await ReporterStorage.save(state);
      setState(() => _state = state);

      await _reconciler.reconcile();
    } catch (e) {
      setState(() => _statusText = 'Registration failed: $e');
    } finally {
      setState(() => _bootstrapping = false);
    }
  }

  Future<String> _getAndroidId() async {
    // Check if we already have one stored
    final stored = await ReporterStorage.getAndroidId();
    if (stored != null) return stored;

    // Generate a stable-ish identifier
    // In production, use platform channel to get Settings.Secure.ANDROID_ID
    final now = DateTime.now().millisecondsSinceEpoch;
    return 'android-${now.toRadixString(36)}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Family Tracker')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                _iconForState(),
                size: 64,
                color: _colorForState(),
              ),
              const SizedBox(height: 24),
              Text(
                _statusText,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                'Status: ${_state.approval.name} / ${_state.mode.name}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 32),
              if (_state.approval == ApprovalStatus.pending &&
                  _statusText.contains('Set Up'))
                FilledButton.icon(
                  onPressed: _bootstrapping ? null : _bootstrap,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Set Up'),
                ),
              if (_state.approval == ApprovalStatus.pending &&
                  !_statusText.contains('Set Up'))
                const CircularProgressIndicator(),
            ],
          ),
        ),
      ),
    );
  }

  IconData _iconForState() {
    switch (_state.approval) {
      case ApprovalStatus.approved:
        return _state.isLive ? Icons.gps_fixed : Icons.gps_not_fixed;
      case ApprovalStatus.pending:
        return Icons.hourglass_top;
      case ApprovalStatus.removed:
        return Icons.block;
    }
  }

  Color _colorForState() {
    switch (_state.approval) {
      case ApprovalStatus.approved:
        return _state.isLive ? Colors.green : Colors.blue;
      case ApprovalStatus.pending:
        return Colors.orange;
      case ApprovalStatus.removed:
        return Colors.red;
    }
  }
}
