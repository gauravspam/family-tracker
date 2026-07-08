import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../api/relay_api.dart';
import '../appearance/avatar_widget.dart';
import '../appearance/avatars.dart';
import '../appearance/colors.dart';
import '../services/geocode_service.dart';
import '../models/device_view.dart';
import '../state/devices_controller.dart';
import 'package:url_launcher/url_launcher.dart';

Future<void> showDeviceDetailSheet(
  BuildContext context,
  DeviceView view, {
  void Function(int traccarId)? onFollow,
}) async {
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: Colors.transparent,
    builder: (context) => _DeviceDetailSheet(view: view, onFollow: onFollow),
  );
}

class _DeviceDetailSheet extends StatefulWidget {
  final DeviceView view;
  final void Function(int traccarId)? onFollow;
  const _DeviceDetailSheet({required this.view, this.onFollow});

  @override
  State<_DeviceDetailSheet> createState() => _DeviceDetailSheetState();
}

class _DeviceDetailSheetState extends State<_DeviceDetailSheet> {
  bool _busy = false;
  late String _displayName;
  late String? _avatarId;
  late String? _colorHex;

  DeviceView get view => widget.view;

  @override
  void initState() {
    super.initState();
    _displayName = view.displayName;
    _avatarId = view.device.avatarId;
    _colorHex = view.device.colorHex;
  }

  Future<void> _editAppearance() async {
    final result = await showModalBottomSheet<_AppearanceResult>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _AppearanceEditor(
        initialAvatarId: _avatarId ?? 'avatar_default',
        initialColorHex: _colorHex ?? DeviceColorPalette.toHex(DeviceColorPalette.defaultColor),
      ),
    );

    if (result == null) return;
    if (!mounted) return;

    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    final relay = context.read<RelayApi>();
    final devices = context.read<DevicesController>();

    try {
      await relay.setAppearance(
        traccarDeviceId: view.device.id,
        avatarId: result.avatarId,
        colorHex: result.colorHex,
      );
      await devices.refresh();
      if (!mounted) return;
      setState(() {
        _avatarId = result.avatarId;
        _colorHex = result.colorHex;
        _busy = false;
      });
      messenger.showSnackBar(
        const SnackBar(content: Text('Appearance updated')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      messenger.showSnackBar(
        SnackBar(
          content: Text('Appearance update failed: $e'),
          backgroundColor: Colors.red.shade700,
        ),
      );
    }
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
    if (!mounted) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final relay = context.read<RelayApi>();
    final devices = context.read<DevicesController>();

    try {
      final expiresAt = DateTime.now().toUtc().add(const Duration(minutes: 30));
      await relay.triggerLive(
        traccarDeviceId: view.device.id,
        expiresAtUtc: expiresAt,
      );
      await devices.refresh();
      if (!mounted) return;
      navigator.pop();
      messenger.showSnackBar(
        const SnackBar(content: Text('Live mode ON')),
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

  Future<void> _locateDevice() async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    final relay = context.read<RelayApi>();

    try {
      await relay.locateDevice(view.device.id);
      if (!mounted) return;
      setState(() => _busy = false);
      messenger.showSnackBar(
        const SnackBar(content: Text('Location refresh sent')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      messenger.showSnackBar(
        SnackBar(
          content: Text('Refresh failed: $e'),
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

  Future<void> _ring() async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    final relay = context.read<RelayApi>();

    try {
      await relay.ringDevice(view.device.id);
      if (!mounted) return;
      setState(() => _busy = false);
      messenger.showSnackBar(
        const SnackBar(content: Text('Ringing device...')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      messenger.showSnackBar(
        SnackBar(
          content: Text('Ring failed: $e'),
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
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
        child: Container(
          decoration: BoxDecoration(
            color: isDark
                ? const Color(0xFF1C1C1E).withValues(alpha: 0.75)
                : Colors.white.withValues(alpha: 0.75),
          ),
          child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Hero section ──────────────────────────────────────────
            Row(
              children: [
                GestureDetector(
                  onTap: _busy ? null : _editAppearance,
                  child: Stack(
                    children: [
                      DeviceAvatar(
                        avatarId: _avatarId,
                        colorHex: _colorHex,
                        size: 48,
                      ),
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: Container(
                          width: 16,
                          height: 16,
                          decoration: BoxDecoration(
                            color: view.isOnline ? Colors.green : Colors.grey,
                            shape: BoxShape.circle,
                            border: Border.all(color: scheme.surface, width: 2),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _displayName,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        view.isOnline ? 'Online now' : 'Offline',
                        style: TextStyle(
                          fontSize: 12,
                          color: view.isOnline
                              ? Colors.green.shade600
                              : Colors.grey,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _IconButton(
                      icon: Icons.refresh,
                      tooltip: 'Refresh location',
                      onPressed: _busy ? null : _locateDevice,
                    ),
                    const SizedBox(width: 4),
                    _IconButton(
                      icon: Icons.palette_outlined,
                      tooltip: 'Appearance',
                      onPressed: _busy ? null : _editAppearance,
                    ),
                    const SizedBox(width: 4),
                    _IconButton(
                      icon: Icons.edit_outlined,
                      tooltip: 'Rename',
                      onPressed: _busy ? null : _rename,
                    ),
                  ],
                ),
              ],
            ),

            // ── Live banner ──────────────────────────────────────────
            if (view.isLive) ...[
              const SizedBox(height: 10),
              _LiveBanner(expiresAt: view.liveExpiresAt),
            ],

            // ── Info card ────────────────────────────────────────────
            const SizedBox(height: 14),
            _Card(
              children: [
                _InfoRow(
                  icon: Icons.tag,
                  label: 'ID',
                  value: view.device.id.toString(),
                ),
                _Divider(),
                _InfoRow(
                  icon: Icons.info_outline,
                  label: 'Status',
                  value: view.device.status,
                ),
              ],
            ),

            // ── Position card ────────────────────────────────────────
            if (p != null) ...[
              const SizedBox(height: 10),
              _Card(
                children: [
                  _InfoRow(
                    icon: Icons.location_on_outlined,
                    label: 'Coordinates',
                    value: '${p.latitude.toStringAsFixed(5)}, ${p.longitude.toStringAsFixed(5)}',
                    copyable: true,
                  ),
                  _Divider(),
                  _AddressRow(latitude: p.latitude, longitude: p.longitude),
                  if (p.speed > 0) ...[
                    _Divider(),
                    _InfoRow(
                      icon: Icons.speed,
                      label: 'Speed',
                      value: '${(p.speed * 3.6).toStringAsFixed(1)} km/h',
                    ),
                  ],
                  _Divider(),
                  _InfoRow(
                    icon: Icons.sensors,
                    label: 'Accuracy',
                    value: '${p.accuracy.toStringAsFixed(0)} m',
                  ),
                  if (p.batteryPercent != null) ...[
                    _Divider(),
                    _InfoRow(
                      icon: p.isLowBattery
                          ? Icons.battery_alert
                          : Icons.battery_std,
                      label: 'Battery',
                      value: '${p.batteryPercent}%',
                      valueColor: p.isLowBattery ? Colors.red : null,
                    ),
                  ],
                ],
              ),
            ],

            const SizedBox(height: 16),
            // ── Primary action ───────────────────────────────────────
            SizedBox(
              width: double.infinity,
              child: view.isLive
                  ? _PrimaryButton(
                      onPressed: _busy ? null : _stopLive,
                      icon: Icons.stop_circle_outlined,
                      label: 'Stop Live',
                      destructive: true,
                    )
                  : _PrimaryButton(
                      onPressed: _busy ? null : _triggerLive,
                      icon: Icons.gps_fixed,
                      label: 'Track Live',
                    ),
            ),

            // ── Secondary actions ────────────────────────────────────
            const SizedBox(height: 8),
            Row(
              children: [
                _SecondaryButton(
                  icon: Icons.directions_rounded,
                  label: 'Route',
                  onTap: (_busy || view.position == null) ? null : _openDirections,
                ),
                const SizedBox(width: 8),
                _SecondaryButton(
                  icon: Icons.notifications_active_outlined,
                  label: 'Ring',
                  onTap: _busy ? null : _ring,
                ),
                const SizedBox(width: 8),
                _SecondaryButton(
                  icon: Icons.delete_outline_rounded,
                  label: 'Remove',
                  onTap: _busy ? null : _remove,
                  destructive: true,
                ),
              ],
            ),

            // ── Tertiary actions ─────────────────────────────────────
            if (widget.onFollow != null && view.position != null) ...[
              const SizedBox(height: 8),
              _TertiaryButton(
                icon: Icons.my_location,
                label: 'Follow on map',
                onTap: _busy
                    ? null
                    : () {
                        Navigator.of(context).pop();
                        widget.onFollow!(view.device.id);
                      },
              ),
            ],
            const SizedBox(height: 8),

            // ── Busy indicator ───────────────────────────────────────
            if (_busy) ...[
              const SizedBox(height: 12),
              const LinearProgressIndicator(),
            ],
            const SizedBox(height: 8),
          ],
        ),
      ),
    ),
  ),
),
);
  }
}

// ── Apple-style components ─────────────────────────────────────────────

class _Card extends StatelessWidget {
  final List<Widget> children;
  const _Card({required this.children});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            color: isDark
                ? const Color(0xFF1C1C1E).withValues(alpha: 0.25)
                : Colors.white.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.08)
                  : Colors.black.withValues(alpha: 0.04),
              width: 0.5,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: children,
          ),
        ),
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(left: 44),
      child: Divider(
        height: 0,
        thickness: 0.5,
        color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.06),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final bool copyable;
  final Color? valueColor;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    this.copyable = false,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(icon, size: 18, color: scheme.onSurfaceVariant),
          const SizedBox(width: 12),
          SizedBox(
            width: 88,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: copyable
                ? GestureDetector(
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: value));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Copied'), duration: Duration(seconds: 1)),
                      );
                    },
                    child: Row(
                      children: [
                        Flexible(
                          child: Text(
                            value,
                            style: TextStyle(
                              fontSize: 14,
                              color: valueColor ?? scheme.onSurface,
                              fontWeight: FontWeight.w500,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Icon(Icons.copy_outlined, size: 14, color: scheme.onSurfaceVariant),
                      ],
                    ),
                  )
                : SelectableText(
                    value,
                    style: TextStyle(
                      fontSize: 14,
                      color: valueColor ?? scheme.onSurface,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _IconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  const _IconButton({
    required this.icon,
    required this.tooltip,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Opacity(
      opacity: onPressed == null ? 0.4 : 1.0,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 20, color: scheme.primary),
          ),
        ),
      ),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final IconData icon;
  final String label;
  final bool destructive;

  const _PrimaryButton({
    this.onPressed,
    required this.icon,
    required this.label,
    this.destructive = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Opacity(
      opacity: onPressed == null ? 0.4 : 1.0,
      child: SizedBox(
        width: double.infinity,
        child: TextButton(
          onPressed: onPressed,
          style: TextButton.styleFrom(
            backgroundColor: destructive
                ? Colors.red.withValues(alpha: 0.15)
                : scheme.primary,
            foregroundColor: destructive ? Colors.red : scheme.onPrimary,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 20),
              const SizedBox(width: 8),
              Text(label, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }
}

class _SecondaryButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool destructive;

  const _SecondaryButton({
    required this.icon,
    required this.label,
    this.onTap,
    this.destructive = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fg = destructive ? Colors.red : scheme.primary;

    return Expanded(
      child: Opacity(
        opacity: onTap == null ? 0.4 : 1.0,
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: fg.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: fg, size: 24),
                const SizedBox(height: 4),
                Text(
                  label,
                  style: TextStyle(
                    color: fg,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TertiaryButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  const _TertiaryButton({
    required this.icon,
    required this.label,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Opacity(
      opacity: onTap == null ? 0.4 : 1.0,
      child: SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: onTap,
          icon: Icon(icon, size: 18),
          label: Text(label),
          style: OutlinedButton.styleFrom(
            foregroundColor: scheme.onSurfaceVariant,
            side: BorderSide(color: scheme.outlineVariant),
            padding: const EdgeInsets.symmetric(vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      ),
    );
  }
}




class _LiveBanner extends StatelessWidget {
  final DateTime? expiresAt;
  const _LiveBanner({required this.expiresAt});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.green.shade600.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.gps_fixed, color: Colors.green.shade700, size: 18),
          const SizedBox(width: 8),
          Text(
            'LIVE mode active.',
            style: TextStyle(
              color: Colors.green.shade800,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _AppearanceResult {
  final String avatarId;
  final String colorHex;
  const _AppearanceResult({required this.avatarId, required this.colorHex});
}

class _AppearanceEditor extends StatefulWidget {
  final String initialAvatarId;
  final String initialColorHex;

  const _AppearanceEditor({
    required this.initialAvatarId,
    required this.initialColorHex,
  });

  @override
  State<_AppearanceEditor> createState() => _AppearanceEditorState();
}

class _AppearanceEditorState extends State<_AppearanceEditor> {
  late String _avatarId;
  late String _colorHex;

  @override
  void initState() {
    super.initState();
    _avatarId = widget.initialAvatarId;
    _colorHex = widget.initialColorHex;
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 8,
          bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  DeviceAvatar(
                    avatarId: _avatarId,
                    colorHex: _colorHex,
                    size: 56,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Preview',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                'Avatar',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                    ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final preset in AvatarCatalog.all)
                    GestureDetector(
                      onTap: () => setState(() => _avatarId = preset.id),
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: _avatarId == preset.id
                                ? Theme.of(context).colorScheme.primary
                                : Colors.transparent,
                            width: 3,
                          ),
                        ),
                        child: DeviceAvatar(
                          avatarId: preset.id,
                          colorHex: _colorHex,
                          size: 44,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 20),
              Text(
                'Color',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                    ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final c in DeviceColorPalette.all)
                    GestureDetector(
                      onTap: () => setState(
                        () => _colorHex = DeviceColorPalette.toHex(c),
                      ),
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: c,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: _colorHex == DeviceColorPalette.toHex(c)
                                ? Theme.of(context).colorScheme.primary
                                : Colors.transparent,
                            width: 3,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => Navigator.pop(
                        context,
                        _AppearanceResult(
                          avatarId: _avatarId,
                          colorHex: _colorHex,
                        ),
                      ),
                      child: const Text('Save'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AddressRow extends StatefulWidget {
  final double latitude;
  final double longitude;
  const _AddressRow({required this.latitude, required this.longitude});

  @override
  State<_AddressRow> createState() => _AddressRowState();
}

class _AddressRowState extends State<_AddressRow> {
  String? _address;
  bool _loading = true;
  bool _failed = false;
  bool _expanded = false;

  @override
  void initState() {
    super.initState();
    _lookup();
  }

  @override
  void didUpdateWidget(_AddressRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.latitude != widget.latitude ||
        oldWidget.longitude != widget.longitude) {
      setState(() {
        _address = null;
        _loading = true;
        _failed = false;
        _expanded = false;
      });
      _lookup();
    }
  }

  Future<void> _lookup() async {
    final result = await GeocodeService.instance
        .reverse(widget.latitude, widget.longitude);
    if (!mounted) return;
    setState(() {
      _address = result;
      _loading = false;
      _failed = result == null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    Widget content;
    if (_loading) {
      content = Row(
        children: [
          const SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 8),
          Text('Looking up...',
              style: TextStyle(fontSize: 14, color: scheme.onSurfaceVariant)),
        ],
      );
    } else if (_failed || _address == null) {
      content = GestureDetector(
        onTap: () {
          setState(() {
            _loading = true;
            _failed = false;
          });
          _lookup();
        },
        child: Row(
          children: [
            Icon(Icons.refresh, size: 14, color: scheme.onSurfaceVariant),
            const SizedBox(width: 6),
            Text('Unavailable · tap retry',
                style: TextStyle(fontSize: 14, color: scheme.onSurfaceVariant)),
          ],
        ),
      );
    } else {
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    _address!,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                    maxLines: _expanded ? 3 : 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 6),
                GestureDetector(
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: _address!));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Copied'), duration: Duration(seconds: 1)),
                    );
                  },
                  child: Icon(Icons.copy_outlined, size: 14, color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          if (_expanded && _address!.length > 60)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                _address!,
                style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
              ),
            ),
        ],
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.home_outlined, size: 18, color: scheme.onSurfaceVariant),
          const SizedBox(width: 12),
          SizedBox(
            width: 88,
            child: Text(
              'Address',
              style: TextStyle(fontSize: 14, color: scheme.onSurfaceVariant),
            ),
          ),
          Expanded(child: content),
        ],
      ),
    );
  }
}

