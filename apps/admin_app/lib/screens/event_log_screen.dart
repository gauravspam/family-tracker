import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/traccar_api.dart';
import '../state/devices_controller.dart';
import '../state/geofences_controller.dart';

class EventLogScreen extends StatefulWidget {
  const EventLogScreen({super.key});

  @override
  State<EventLogScreen> createState() => _EventLogScreenState();
}

class _EventLogScreenState extends State<EventLogScreen> {
  List<_EventItem> _events = [];
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
      final api = context.read<TraccarApi>();
      final dc = context.read<DevicesController>();
      final deviceIds = dc.devices.map((d) => d.device.id).toList();
      final raw = await api.listEvents(
        deviceId: deviceIds,
        type: const ['geofenceEnter', 'geofenceExit'],
        from: DateTime.now().subtract(const Duration(days: 7)),
        to: DateTime.now(),
      );
      if (!mounted) return;
      final gc = context.read<GeofencesController>();
      final items = raw.map((e) {
        final type = e['type'] as String? ?? 'unknown';
        final deviceId = e['deviceId'] as int?;
        final geofenceId = e['geofenceId'] as int?;
        final rawAttrs = e['attributes'];
        Map<String, dynamic> attrs = {};
        if (rawAttrs is Map) {
          attrs = Map<String, dynamic>.from(rawAttrs);
        } else if (rawAttrs is String && rawAttrs.isNotEmpty) {
          try {
            final decoded = jsonDecode(rawAttrs);
            if (decoded is Map) attrs = Map<String, dynamic>.from(decoded);
          } catch (_) {}
        }
        final geoName = attrs['geofenceName']?.toString();
        final foundGeo = geofenceId != null
            ? gc.list.where((g) => g.id == geofenceId).firstOrNull
            : null;
        final geofenceName = geoName ?? foundGeo?.name ?? 'Geofence #$geofenceId';
        final deviceName = deviceId != null
            ? dc.devices.where((d) => d.device.id == deviceId).map((d) => d.displayName).firstOrNull
            : null;
        final time = e['serverTime'] as String? ?? e['eventTime'] as String?;
        return _EventItem(
          type: type == 'geofenceEnter' ? _EventType.enter : _EventType.exit,
          geofenceName: geofenceName,
          deviceName: deviceName ?? 'Device #$deviceId',
          time: time != null ? DateTime.tryParse(time) : null,
        );
      }).toList();
      items.sort((a, b) {
        final ta = a.time ?? DateTime(2000);
        final tb = b.time ?? DateTime(2000);
        return tb.compareTo(ta);
      });
      if (!mounted) return;
      setState(() {
        _events = items;
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
      body: _loading
          ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? Center(
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
                    )
              : _events.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.event_busy,
                              size: 48, color: scheme.onSurfaceVariant),
                          const SizedBox(height: 12),
                          Text('No geofence events in the last 7 days',
                              style: TextStyle(color: scheme.onSurfaceVariant)),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.separated(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        itemCount: _events.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (_, i) {
                          final e = _events[i];
                          final isEnter = e.type == _EventType.enter;
                          return ListTile(
                            contentPadding:
                                const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            leading: CircleAvatar(
                              radius: 18,
                              backgroundColor: (isEnter ? Colors.green : Colors.red)
                                  .withValues(alpha: 0.15),
                              child: Icon(
                                isEnter ? Icons.login : Icons.logout,
                                color: isEnter ? Colors.green.shade700 : Colors.red.shade400,
                                size: 20,
                              ),
                            ),
                            title: Text(
                              isEnter ? 'Entered ${e.geofenceName}' : 'Exited ${e.geofenceName}',
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            ),
                            subtitle: Text(
                              '${e.deviceName}${e.time != null ? ' · ${_formatTime(e.time!)}' : ''}',
                              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                            ),
                          );
                        },
                      ),
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

enum _EventType { enter, exit }

class _EventItem {
  final _EventType type;
  final String geofenceName;
  final String deviceName;
  final DateTime? time;
  const _EventItem({
    required this.type,
    required this.geofenceName,
    required this.deviceName,
    this.time,
  });
}
