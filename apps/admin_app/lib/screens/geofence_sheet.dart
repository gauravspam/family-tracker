import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tracker_core/tracker_core.dart';

import '../state/geofences_controller.dart';

/// Returns (name, radiusMeters) when user wants to add a geofence,
/// or null if dismissed.
Future<({String name, double radius})?> showGeofenceSheet(BuildContext context) async {
  final controller = context.read<GeofencesController>();
  if (controller.phase == GeofencesPhase.initial) {
    await controller.refresh();
  }
  if (!context.mounted) return null;
  return showModalBottomSheet<({String name, double radius})>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => ChangeNotifierProvider.value(
      value: controller,
      child: const _GeofenceSheetBody(),
    ),
  );
}

class _GeofenceSheetBody extends StatefulWidget {
  const _GeofenceSheetBody();

  @override
  State<_GeofenceSheetBody> createState() => _GeofenceSheetBodyState();
}

class _GeofenceSheetBodyState extends State<_GeofenceSheetBody> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<GeofencesController>().refresh();
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Geofences',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              FilledButton.icon(
                onPressed: () => _add(context),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Consumer<GeofencesController>(
            builder: (context, gc, _) {
              switch (gc.phase) {
                case GeofencesPhase.loading:
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: CircularProgressIndicator(),
                    ),
                  );
                case GeofencesPhase.error:
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        children: [
                          Icon(Icons.error_outline, color: scheme.error, size: 32),
                          const SizedBox(height: 8),
                          Text('Failed to load geofences',
                              style: TextStyle(color: scheme.error)),
                          TextButton(
                            onPressed: () => gc.refresh(),
                            child: const Text('Retry'),
                          ),
                        ],
                      ),
                    ),
                  );
                case GeofencesPhase.initial:
                case GeofencesPhase.ready:
                  if (gc.list.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(
                        child: Text('No geofences yet. Tap "Add" to create one.'),
                      ),
                    );
                  }
                  return ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 360),
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: gc.list.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (_, i) => _GeoItem(geofence: gc.list[i]),
                    ),
                  );
              }
            },
          ),
        ],
      ),
    );
  }

  Future<void> _add(BuildContext context) async {
    final name = await _promptName(context);
    if (name == null || !context.mounted) return;
    Navigator.pop(context, (name: name, radius: 100.0));
  }

  Future<String?> _promptName(BuildContext context) => showDialog<String>(
    context: context,
    builder: (ctx) {
      final c = TextEditingController();
      return AlertDialog(
        title: const Text('Geofence name'),
        content: TextField(
          controller: c,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'e.g. Home, School, Office',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (v) {
            final t = v.trim();
            if (t.isNotEmpty) Navigator.pop(ctx, t);
          },
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              final t = c.text.trim();
              if (t.isNotEmpty) Navigator.pop(ctx, t);
            },
            child: const Text('Place on Map'),
          ),
        ],
      );
    },
  );
}

class _GeoItem extends StatelessWidget {
  final TraccarGeofence geofence;
  const _GeoItem({required this.geofence});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final area = geofence.area;
    final summary = _parseSummary(area);
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      leading: CircleAvatar(
        radius: 18,
        backgroundColor: scheme.primary.withValues(alpha: 0.15),
        child: Icon(Icons.circle_outlined, color: scheme.primary, size: 20),
      ),
      title: Text(geofence.name, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(summary, style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
      trailing: IconButton(
        icon: Icon(Icons.delete_outline, color: Colors.red.shade400, size: 20),
        onPressed: () => _delete(context),
      ),
    );
  }

  String _parseSummary(String area) {
    try {
      if (area.toUpperCase().startsWith('CIRCLE')) {
        final parts = area.replaceAll(RegExp(r'[CIRCLE\s()]'), '').split(',');
        if (parts.length >= 2) {
          return 'Circle · ${parts[1].trim()}m radius';
        }
      }
      if (area.toUpperCase().startsWith('POLYGON')) {
        return 'Polygon';
      }
    } catch (_) {}
    return area;
  }

  Future<void> _delete(BuildContext context) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete geofence?'),
        content: Text('Remove "${geofence.name}"? This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm != true || !context.mounted) return;
    try {
      await context.read<GeofencesController>().delete(geofence.id);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Deleted "${geofence.name}"')),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Delete failed: $e'), backgroundColor: Colors.red.shade700),
      );
    }
  }
}
