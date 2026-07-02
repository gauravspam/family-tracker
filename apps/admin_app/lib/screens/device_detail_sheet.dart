import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/relay_api.dart';
import '../models/device_view.dart';
import '../state/devices_controller.dart';

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

  DeviceView get view => widget.view;

  Future<void> _triggerLive() async {
    final minutes = await showDialog<int>(
      context: context,
      builder: (context) => const _LiveDurationDialog(),
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

  Future<void> _remove() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove device?'),
        content: Text(
          'Removing ${view.displayName} will stop tracking it, invalidate its ingest token, '
          'and delete it from Traccar. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
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
        SnackBar(content: Text('Removed ${view.displayName}')),
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
                  view.displayName,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
            ],
          ),
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
          ],
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _busy ? null : _remove,
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Remove'),
                  style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _busy ? null : _triggerLive,
                  icon: const Icon(Icons.gps_fixed),
                  label: const Text('Track Live'),
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
