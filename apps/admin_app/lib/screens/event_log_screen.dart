import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/relay_api.dart';
import '../models/geofence_event.dart';
import '../services/connectivity_monitor.dart';

class EventLogScreen extends StatefulWidget {
  const EventLogScreen({super.key});

  @override
  State<EventLogScreen> createState() => _EventLogScreenState();
}

class _EventLogScreenState extends State<EventLogScreen> {
  List<GeofenceEvent> _events = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final relay = context.read<RelayApi>();
      final events = await relay.listGeofenceEvents();
      if (!mounted) return;
      setState(() {
        _events = events;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hasCached = _events.isNotEmpty;

    Widget body;
    if (_loading && !hasCached) {
      body = const Center(child: CircularProgressIndicator());
    } else if (_error != null && !hasCached) {
      body = Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, color: scheme.error, size: 48),
            const SizedBox(height: 12),
            Text('Failed to load events',
                style: TextStyle(color: scheme.error)),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                _error!,
                style: TextStyle(color: scheme.error, fontSize: 12),
                textAlign: TextAlign.center,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(height: 8),
            TextButton(onPressed: _load, child: const Text('Retry')),
          ],
        ),
      );
    } else if (_events.isEmpty) {
      body = Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.event_busy,
                size: 48, color: scheme.onSurfaceVariant),
            const SizedBox(height: 12),
            Text('No geofence events recorded yet',
                style: TextStyle(color: scheme.onSurfaceVariant)),
            const SizedBox(height: 4),
            Text(
              'Events are captured when the webhook fires',
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      );
    } else {
      body = RefreshIndicator(
        onRefresh: _load,
        child: ListView.separated(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          itemCount: _events.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (_, i) {
            final e = _events[i];
            return ListTile(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              leading: CircleAvatar(
                radius: 18,
                backgroundColor: (e.isEnter ? Colors.green : Colors.red)
                    .withValues(alpha: 0.15),
                child: Icon(
                  e.isEnter ? Icons.login : Icons.logout,
                  color: e.isEnter ? Colors.green.shade700 : Colors.red.shade400,
                  size: 20,
                ),
              ),
              title: Text(
                '${e.label} ${e.geofenceName}',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: Text(
                '${e.deviceName} · ${_formatTime(e.createdAt)}',
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              ),
            );
          },
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Geofence Events'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _load,
          ),
        ],
      ),
      body: Column(
        children: [
          // Stale data banner when offline
          Consumer<ConnectivityMonitor>(
            builder: (context, cm, _) {
              if (cm.isOnline || !hasCached) return const SizedBox.shrink();
              return Container(
                width: double.infinity,
                color: Colors.orange.withValues(alpha: 0.1),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: Row(
                  children: [
                    Icon(Icons.cloud_off, size: 14, color: Colors.orange.shade700),
                    const SizedBox(width: 8),
                    Text(
                      'Showing cached events — offline',
                      style: TextStyle(color: Colors.orange.shade700, fontSize: 11),
                    ),
                  ],
                ),
              );
            },
          ),
          Expanded(child: body),
        ],
      ),
    );
  }

  String _formatTime(DateTime t) {
    final now = DateTime.now();
    final diff = now.difference(t);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}
