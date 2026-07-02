import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/relay_api.dart';
import '../models/device_view.dart';
import '../state/devices_controller.dart';
import 'package:url_launcher/url_launcher.dart';

Future<void> showDeviceDetailSheet(
  BuildContext context,
  DeviceView view,
) async {
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => _DeviceDetailSheet(view: view),
  );
}

class _DeviceDetailSheet extends StatefulWidget {
  final DeviceView view;
  const _DeviceDetailSheet({required this.view});

  @override
  State<_DeviceDetailSheet> createState() => _DeviceDetailSheetState();
}

class _DeviceDetailSheetState extends State<_DeviceDetailSheet> {
  bool _busy = false;
  late String _displayName;

  DeviceView get view => widget.view;

  @override
  void initState() {
    super.initState();
    _displayName = view.displayName;
  }

  Future<void> _rename() async {
    final controller = TextEditingController(text: _displayName);

    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename device'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Device name',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (v) {
            final t = v.trim();
            if (t.isNotEmpty) Navigator.pop(ctx, t);
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final t = controller.text.trim();
              if (t.isEmpty) return;
              Navigator.pop(ctx, t);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (newName == null || newName == _displayName) return;
    if (!mounted) return;

    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    final relay = context.read<RelayApi>();
    final devices = context.read<DevicesController>();

    try {
      await relay.renameByTraccarId(view.device.id, newName);
      await devices.refresh();
      if (!mounted) return;
      setState(() {
        _displayName = newName;
        _busy = false;
      });
      messenger.showSnackBar(
        SnackBar(content: Text('Renamed to "$newName"')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      messenger.showSnackBar(
        SnackBar(
          content: Text('Rename failed: $e'),
          backgroundColor: Colors.red.shade700,
        ),
      );
    }
  }

  Future<void> _triggerLive() async {
    final minutes = await showDialog<int>(
      context: context,
      builder: (ctx) => const _LiveDurationDialog(),
    );
    if (minutes == null) return;
    if (!mounted) return;

    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final relay = context.read<RelayApi>();

    try {
      final expiresAt = DateTime.now().toUtc().add(Duration(minutes: minutes));
      await relay.triggerLive(
        traccarDeviceId: view.device.id,
        expiresAtUtc: expiresAt,
      );
      if (!mounted) return;
      navigator.pop();
      messenger.showSnackBar(
        SnackBar(content: Text('Live mode ON for $minutes min')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      messenger.showSnackBar(
        SnackBar(
          content: Text('Live trigger failed: $e'),
          backgroundColor: Colors.red.shade700,
        ),
      );
    }
  }

  Future<void> _stopLive() async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final relay = context.read<RelayApi>();
    final devices = context.read<DevicesController>();

    try {
      await relay.stopLive(view.device.id);
      await devices.refresh();
      if (!mounted) return;
      navigator.pop();
      messenger.showSnackBar(
        const SnackBar(content: Text('Live mode stopped')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      messenger.showSnackBar(
        SnackBar(
          content: Text('Stop live failed: $e'),
          backgroundColor: Colors.red.shade700,
        ),
      );
    }
  }

  Future<void> _remove() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove device?'),
        content: Text(
          'Removing $_displayName will stop tracking it, invalidate its ingest token, '
          'and delete it from Traccar. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    if (!mounted) return;

    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final relay = context.read<RelayApi>();
    final devices = context.read<DevicesController>();

    try {
      await relay.removeByTraccarId(view.device.id);
      await devices.refresh();
      if (!mounted) return;
      navigator.pop();
      messenger.showSnackBar(
        SnackBar(content: Text('Removed $_displayName')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      messenger.showSnackBar(
        SnackBar(
          content: Text('Remove failed: $e'),
          backgroundColor: Colors.red.shade700,
        ),
      );
    }
  }

  Future<void> _openDirections() async {
    final p = view.position;
    if (p == null) return;

    // geo: URI is resolved by the system to whatever nav app the user prefers
    // (Google Maps, Waze, OsmAnd, etc.).
    final uri = Uri.parse(
      'geo:${p.latitude},${p.longitude}?q=${p.latitude},${p.longitude}(${Uri.encodeComponent(_displayName)})',
    );

    final messenger = ScaffoldMessenger.of(context);
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && mounted) {
        messenger.showSnackBar(
          const SnackBar(content: Text('No maps app found on this device')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text('Directions failed: $e'),
          backgroundColor: Colors.red.shade700,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = view.position;

    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 8,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                view.isOnline ? Icons.circle : Icons.circle_outlined,
                color: view.isOnline ? Colors.green : Colors.grey,
                size: 12,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _displayName,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.edit_outlined),
                tooltip: 'Rename',
                onPressed: _busy ? null : _rename,
              ),
            ],
          ),
          if (view.isLive) ...[
            const SizedBox(height: 8),
            _LiveBanner(expiresAt: view.liveExpiresAt),
          ],
          const SizedBox(height: 12),
          _InfoRow(label: 'Traccar ID', value: view.device.id.toString()),
          _InfoRow(
            label: 'Unique ID',
            value: view.device.uniqueId,
            monospace: true,
          ),
          _InfoRow(label: 'Status', value: view.device.status),
          if (p != null) ...[
            const Divider(height: 24),
            _InfoRow(
              label: 'Last position',
              value: '${p.latitude.toStringAsFixed(5)}, '
                  '${p.longitude.toStringAsFixed(5)}',
            ),
            _InfoRow(
              label: 'Accuracy',
              value: '${p.accuracy.toStringAsFixed(0)} m',
            ),
            _InfoRow(
              label: 'Speed',
              value: '${(p.speed * 3.6).toStringAsFixed(1)} km/h',
            ),
            _InfoRow(
              label: 'Fix time',
              value: p.fixTime.toLocal().toString(),
            ),
            if (p.batteryPercent != null)
              _InfoRow(
                label: 'Battery',
                value: '${p.batteryPercent}%'
                    '${p.isLowBattery ? " ⚠️ low" : ""}',
              ),
          ],
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: view.isLive
                ? FilledButton.icon(
                    onPressed: _busy ? null : _stopLive,
                    icon: const Icon(Icons.stop_circle_outlined),
                    label: const Text('Stop Live'),
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.red.shade700,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  )
                : FilledButton.icon(
                    onPressed: _busy ? null : _triggerLive,
                    icon: const Icon(Icons.gps_fixed),
                    label: const Text('Track Live'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed:
                      (_busy || view.position == null) ? null : _openDirections,
                  icon: const Icon(Icons.directions),
                  label: const Text('Directions'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _busy ? null : _remove,
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Remove'),
                  style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                ),
              ),
            ],
          ),
          if (_busy) ...[
            const SizedBox(height: 12),
            const LinearProgressIndicator(),
          ],
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final bool monospace;

  const _InfoRow({
    required this.label,
    required this.value,
    this.monospace = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.grey,
                  ),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: TextStyle(
                fontFamily: monospace ? 'monospace' : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LiveDurationDialog extends StatefulWidget {
  const _LiveDurationDialog();

  @override
  State<_LiveDurationDialog> createState() => _LiveDurationDialogState();
}

class _LiveDurationDialogState extends State<_LiveDurationDialog> {
  int _minutes = 30;
  static const _options = [5, 15, 30, 60, 120];

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Track Live'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('For how long?'),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            children: [
              for (final m in _options)
                ChoiceChip(
                  label: Text(m >= 60 ? '${m ~/ 60}h' : '${m}m'),
                  selected: _minutes == m,
                  onSelected: (v) {
                    if (v) setState(() => _minutes = m);
                  },
                ),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _minutes),
          child: const Text('Start'),
        ),
      ],
    );
  }
}

class _LiveBanner extends StatefulWidget {
  final DateTime? expiresAt;
  const _LiveBanner({required this.expiresAt});

  @override
  State<_LiveBanner> createState() => _LiveBannerState();
}

class _LiveBannerState extends State<_LiveBanner> {
  @override
  void initState() {
    super.initState();
    Future.doWhile(() async {
      await Future.delayed(const Duration(seconds: 15));
      if (!mounted) return false;
      setState(() {});
      return mounted;
    });
  }

  @override
  Widget build(BuildContext context) {
    final exp = widget.expiresAt;
    String detail = 'Reporter is posting at high frequency.';
    if (exp != null) {
      final remaining = exp.difference(DateTime.now());
      if (remaining.isNegative) {
        detail = 'Ending shortly...';
      } else if (remaining.inMinutes >= 1) {
        detail = 'Ends in ${remaining.inMinutes} min';
      } else {
        detail = 'Ends in ${remaining.inSeconds} s';
      }
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.green.shade600.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(Icons.gps_fixed, color: Colors.green.shade700, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'LIVE mode active · $detail',
              style: TextStyle(color: Colors.green.shade800, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}
