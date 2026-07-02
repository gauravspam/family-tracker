import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:tracker_core/tracker_core.dart';

import '../api/relay_api.dart';
import '../auth/auth_controller.dart';
import '../state/pending_controller.dart';

class PendingScreen extends StatefulWidget {
  const PendingScreen({super.key});

  @override
  State<PendingScreen> createState() => _PendingScreenState();
}

class _PendingScreenState extends State<PendingScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  Future<void> _refresh() async {
    final auth = context.read<AuthController>();
    try {
      await context.read<PendingController>().refresh();
    } on RelayUnauthorized {
      await auth.logout();
    }
  }

  Future<void> _approve(PendingDevice d) async {
    final name = await _askForName(d.deviceModel);
    if (name == null) return; // user cancelled
    if (!mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      await context.read<PendingController>().approve(d.id, name: name);
      messenger.showSnackBar(
        SnackBar(content: Text('Approved as "$name"')),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('Approve failed: $e'),
          backgroundColor: Colors.red.shade700,
        ),
      );
    }
  }

  Future<String?> _askForName(String suggested) async {
    final controller = TextEditingController(text: suggested);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Name this device'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Give this device a friendly name so you can tell it apart from others.',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Device name',
                hintText: "e.g. Dad's Phone",
                border: OutlineInputBorder(),
              ),
              onSubmitted: (v) {
                final trimmed = v.trim();
                if (trimmed.isNotEmpty) Navigator.pop(ctx, trimmed);
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final trimmed = controller.text.trim();
              if (trimmed.isEmpty) return;
              Navigator.pop(ctx, trimmed);
            },
            child: const Text('Approve'),
          ),
        ],
      ),
    );
  }

  Future<void> _reject(PendingDevice d) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reject device?'),
        content: Text(
          'Reject request from ${d.deviceModel}?\n\n'
          'The reporter app on that device will remain waiting until it is uninstalled or its data cleared.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Reject'),
          ),
        ],
      ),
    );

    if (confirm != true) return;
    if (!mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      await context.read<PendingController>().reject(d.id);
      messenger.showSnackBar(
        SnackBar(content: Text('Rejected ${d.deviceModel}')),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('Reject failed: $e'),
          backgroundColor: Colors.red.shade700,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<PendingController>(
      builder: (context, controller, _) {
        return RefreshIndicator(
          onRefresh: _refresh,
          child: _buildBody(context, controller),
        );
      },
    );
  }

  Widget _buildBody(BuildContext context, PendingController controller) {
    switch (controller.phase) {
      case PendingPhase.initial:
      case PendingPhase.loading:
        if (controller.items.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }
        return _buildList(controller.items);

      case PendingPhase.error:
        return _ErrorView(
          message: controller.lastError ?? 'Unknown error',
          onRetry: _refresh,
        );

      case PendingPhase.ready:
        if (controller.items.isEmpty) {
          return const _EmptyView();
        }
        return _buildList(controller.items);
    }
  }

  Widget _buildList(List<PendingDevice> items) {
    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: items.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, i) => _PendingTile(
        device: items[i],
        onApprove: () => _approve(items[i]),
        onReject: () => _reject(items[i]),
      ),
    );
  }
}

class _PendingTile extends StatelessWidget {
  final PendingDevice device;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  const _PendingTile({
    required this.device,
    required this.onApprove,
    required this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.smartphone, color: Colors.orange),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      device.deviceModel,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Android ${device.osVersion ?? "unknown"}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    Text(
                      'Requested ${DateFormat.yMd().add_Hm().format(device.createdAt.toLocal())}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onReject,
                  icon: const Icon(Icons.close),
                  label: const Text('Reject'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.icon(
                  onPressed: onApprove,
                  icon: const Icon(Icons.check),
                  label: const Text('Approve'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
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
                Icon(Icons.inbox, size: 72, color: Colors.grey),
                SizedBox(height: 16),
                Text('No pending devices'),
                SizedBox(height: 8),
                Text(
                  'When a family member installs the Reporter app,\ntheir request will appear here.',
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
