import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/traccar_api.dart';
import '../auth/auth_controller.dart';
import '../appearance/avatar_widget.dart';
import '../models/device_view.dart';
import '../state/devices_controller.dart';
import '../state/hidden_devices_controller.dart';
import '../ws/traccar_socket.dart';
import 'device_detail_sheet.dart';

class DevicesScreen extends StatelessWidget {
  const DevicesScreen({super.key});

  Future<void> _refresh(BuildContext context) async {
    try {
      await context.read<DevicesController>().refresh();
    } on TraccarUnauthorized {
      if (context.mounted) {
        await context.read<AuthController>().logout();
      }
    }
  }

  List<DeviceView> _visible(List<DeviceView> devices, BuildContext context) {
    final hidden = context.read<HiddenDevicesController>();
    if (hidden.isShowingHidden) return devices;
    return devices.where((d) => !hidden.isHidden(d.device.id)).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<DevicesController>(
      builder: (context, controller, _) {
        return Column(
          children: [
            const _ConnectionBanner(),
            _BatteryWarningBanner(devices: controller.devices),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () => _refresh(context),
                child: _buildBody(context, controller),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildBody(BuildContext context, DevicesController controller) {
    final visible = _visible(controller.devices, context);
    switch (controller.phase) {
      case DevicesPhase.initial:
      case DevicesPhase.loading:
        if (controller.devices.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }
        return _buildList(visible);

      case DevicesPhase.error:
        return _ErrorView(
          message: controller.lastError ?? 'Unknown error',
          onRetry: () => _refresh(context),
        );

      case DevicesPhase.ready:
        if (visible.isEmpty) {
          final hasHidden = controller.devices
              .any((d) => context.read<HiddenDevicesController>().isHidden(d.device.id));
          return _EmptyView(hasHidden: hasHidden);
        }
        return _buildList(visible);
    }
  }

  Widget _buildList(List<DeviceView> devices) {
    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(top: 110, bottom: 100),
      itemCount: devices.length,
      itemBuilder: (context, index) => _DeviceTile(view: devices[index]),
    );
  }
}

class _ConnectionBanner extends StatelessWidget {
  const _ConnectionBanner();

  @override
  Widget build(BuildContext context) {
    return Consumer<TraccarSocket>(
      builder: (context, socket, _) {
        final s = socket.state;
        if (s == SocketState.connected) return const SizedBox.shrink();

        final (color, text, icon) = switch (s) {
          SocketState.connecting => (Colors.orange, 'Connecting live updates...', Icons.sync),
          SocketState.reconnecting => (Colors.orange, 'Reconnecting...', Icons.sync_problem),
          SocketState.disconnected => (Colors.grey, 'Live updates offline', Icons.cloud_off),
          SocketState.connected => (Colors.green, '', Icons.check_circle),
        };

        return Container(
          width: double.infinity,
          color: color.withValues(alpha: 0.15),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Row(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 8),
              Text(text, style: TextStyle(color: color, fontSize: 12)),
            ],
          ),
        );
      },
    );
  }
}

class _DeviceTile extends StatelessWidget {
  final DeviceView view;
  const _DeviceTile({required this.view});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final p = view.position;
    final batt = p?.batteryPercent;
    final low = p?.isLowBattery ?? false;

    // Subtitle parts
    final timePart = p != null ? _relative(p.fixTime) : 'No position yet';
    final coordsPart = p != null
        ? '${p.latitude.toStringAsFixed(5)}, ${p.longitude.toStringAsFixed(5)}'
        : '';

    final card = Card(
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: view.isLive
            ? BorderSide(color: Colors.green.shade400.withValues(alpha: 0.6), width: 1.5)
            : BorderSide.none,
      ),
      child: InkWell(
        onTap: () => showDeviceDetailSheet(context, view),
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Row(
            children: [
              // Avatar with online dot
              _AvatarWithGlow(
                avatarId: view.device.avatarId,
                colorHex: view.device.colorHex,
                isOnline: view.isOnline,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Name + live chip
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            view.displayName,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        if (view.isLive) ...[
                          const SizedBox(width: 8),
                          _LiveChip(expiresAt: view.liveExpiresAt),
                        ],
                        if (view.isOrphan) ...[
                          const SizedBox(width: 8),
                          const _OrphanChip(),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    // Coordinates + time
                    if (coordsPart.isNotEmpty)
                      Text(
                        '$coordsPart · $timePart',
                        style: TextStyle(
                          fontSize: 13,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    if (coordsPart.isEmpty)
                      Text(
                        timePart,
                        style: TextStyle(
                          fontSize: 13,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    const SizedBox(height: 4),
                    // Battery row
                    if (batt != null)
                      Row(
                        children: [
                          Icon(
                            low ? Icons.battery_alert : Icons.battery_std,
                            size: 14,
                            color: low ? Colors.red : scheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '$batt%',
                            style: TextStyle(
                              fontSize: 12,
                              color: low ? Colors.red : scheme.onSurfaceVariant,
                              fontWeight: low ? FontWeight.w600 : FontWeight.normal,
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: scheme.onSurfaceVariant.withValues(alpha: 0.4),
              ),
            ],
          ),
        ),
      ),
    );
    if (view.isLive) {
      return _PulsingCard(child: card);
    }
    return card;
  }

  String _relative(DateTime t) {
    final diff = DateTime.now().difference(t.toLocal());
    if (diff.inSeconds < 60) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${t.toLocal().month}/${t.toLocal().day} ${t.toLocal().hour}:${t.toLocal().minute.toString().padLeft(2, "0")}';
  }
}

class _AvatarWithGlow extends StatelessWidget {
  final String? avatarId;
  final String? colorHex;
  final bool isOnline;

  const _AvatarWithGlow({
    required this.avatarId,
    required this.colorHex,
    required this.isOnline,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        DeviceAvatar(
          avatarId: avatarId,
          colorHex: colorHex,
          size: 48,
        ),
        Positioned(
          right: -1,
          bottom: -1,
          child: Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              color: isOnline ? Colors.green : Colors.grey,
              shape: BoxShape.circle,
              border: Border.all(
                color: Theme.of(context).cardColor,
                width: 2,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _EmptyView extends StatelessWidget {
  final bool hasHidden;
  const _EmptyView({this.hasHidden = false});

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        SizedBox(
          height: MediaQuery.of(context).size.height * 0.6,
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  hasHidden ? Icons.visibility_off : Icons.devices_other,
                  size: 72,
                  color: Colors.grey,
                ),
                const SizedBox(height: 16),
                Text(hasHidden ? 'All devices hidden' : 'No devices yet'),
                const SizedBox(height: 8),
                Text(
                  hasHidden
                      ? 'Use "Show Hidden" in the menu\nto reveal them.'
                      : 'Family members can install the Reporter app\nto request access.',
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  final Future<void> Function() onRetry;

  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        SizedBox(
          height: MediaQuery.of(context).size.height * 0.6,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.cloud_off, size: 72, color: Colors.red),
                  const SizedBox(height: 16),
                  Text(message, textAlign: TextAlign.center),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retry'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _LiveChip extends StatefulWidget {
  final DateTime? expiresAt;
  const _LiveChip({required this.expiresAt});

  @override
  State<_LiveChip> createState() => _LiveChipState();
}

class _LiveChipState extends State<_LiveChip> {
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
    String label = 'LIVE';
    if (exp != null) {
      final remaining = exp.difference(DateTime.now());
      if (remaining.isNegative) {
        label = 'LIVE (ending)';
      } else if (remaining.inMinutes >= 1) {
        label = 'LIVE ${remaining.inMinutes}m';
      } else {
        label = 'LIVE ${remaining.inSeconds}s';
      }
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.green.shade600,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _OrphanChip extends StatelessWidget {
  const _OrphanChip();

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Orphan device: exists in Traccar but the relay has no record. '
          'Safe to remove from the device details.',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: Colors.orange.shade700,
          borderRadius: BorderRadius.circular(6),
        ),
        child: const Text(
          'ORPHAN',
          style: TextStyle(
            color: Colors.white,
            fontSize: 10,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _BatteryWarningBanner extends StatelessWidget {
  final List<DeviceView> devices;
  const _BatteryWarningBanner({required this.devices});

  @override
  Widget build(BuildContext context) {
    final lowBatt = devices.where((d) {
      final p = d.position;
      return p != null && p.isLowBattery;
    }).toList();
    if (lowBatt.isEmpty) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      color: Colors.orange.withValues(alpha: 0.15),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          const Icon(Icons.battery_alert, size: 16, color: Colors.orange),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Low battery: ${lowBatt.map((d) => d.displayName).join(", ")}',
              style: const TextStyle(fontSize: 12, color: Colors.orange),
            ),
          ),
        ],
      ),
    );
  }
}

class _PulsingCard extends StatefulWidget {
  final Widget child;
  const _PulsingCard({required this.child});

  @override
  State<_PulsingCard> createState() => _PulsingCardState();
}

class _PulsingCardState extends State<_PulsingCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) {
        final t = _c.value;
        final opacity = 0.3 + (0.4 * (1 - t));
        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.green.withValues(alpha: opacity),
                blurRadius: 3 + (2 * t),
                spreadRadius: 0,
              ),
            ],
          ),
          child: widget.child,
        );
      },
    );
  }
}
