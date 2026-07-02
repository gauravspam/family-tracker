import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../api/traccar_api.dart';
import '../auth/auth_controller.dart';
import '../models/device_view.dart';
import '../state/devices_controller.dart';
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

  @override
  Widget build(BuildContext context) {
    return Consumer<DevicesController>(
      builder: (context, controller, _) {
        return Column(
          children: [
            const _ConnectionBanner(),
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
    switch (controller.phase) {
      case DevicesPhase.initial:
      case DevicesPhase.loading:
        if (controller.devices.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }
        return _buildList(controller.devices);

      case DevicesPhase.error:
        return _ErrorView(
          message: controller.lastError ?? 'Unknown error',
          onRetry: () => _refresh(context),
        );

      case DevicesPhase.ready:
        if (controller.devices.isEmpty) {
          return const _EmptyView();
        }
        return _buildList(controller.devices);
    }
  }

  Widget _buildList(List<DeviceView> devices) {
    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: devices.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
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
    final subtitleParts = <String>[];
    if (view.position != null) {
      final p = view.position!;
      subtitleParts.add(
        '${p.latitude.toStringAsFixed(5)}, ${p.longitude.toStringAsFixed(5)}',
      );
      subtitleParts.add(_relative(p.fixTime));
    } else {
      subtitleParts.add('No position yet');
    }

    final low = view.position?.isLowBattery ?? false;
    final batt = view.position?.batteryPercent;

    return ListTile(
      leading: Icon(
        view.isOnline ? Icons.circle : Icons.circle_outlined,
        color: view.isOnline ? Colors.green : Colors.grey,
        size: 14,
      ),
      title: Row(
        children: [
          Flexible(child: Text(view.displayName, overflow: TextOverflow.ellipsis)),
          if (view.isLive) ...[
            const SizedBox(width: 8),
            _LiveChip(expiresAt: view.liveExpiresAt),
          ],
        ],
      ),
      subtitle: Text(subtitleParts.join(' · ')),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (low)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Tooltip(
                message: 'Low battery ($batt%)',
                child: const Icon(
                  Icons.battery_alert,
                  color: Colors.red,
                  size: 20,
                ),
              ),
            ),
          const Icon(Icons.chevron_right),
        ],
      ),
      onTap: () => showDeviceDetailSheet(context, view),
    );
  }

  String _relative(DateTime t) {
    final diff = DateTime.now().difference(t.toLocal());
    if (diff.inSeconds < 60) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return DateFormat.yMd().add_Hm().format(t.toLocal());
  }
}

class _EmptyView extends StatelessWidget {
  const _EmptyView();

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        SizedBox(
          height: MediaQuery.of(context).size.height * 0.6,
          child: const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.devices_other, size: 72, color: Colors.grey),
                SizedBox(height: 16),
                Text('No devices yet'),
                SizedBox(height: 8),
                Text(
                  'Family members can install the Reporter app\nto request access.',
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
