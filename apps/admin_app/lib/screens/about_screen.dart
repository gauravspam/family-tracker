import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

import '../auth/session_storage.dart';
import '../config/server_config.dart';
import 'server_setup_screen.dart';
import '../ws/traccar_socket.dart';

class AboutScreen extends StatefulWidget {
  const AboutScreen({super.key});

  @override
  State<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends State<AboutScreen> {
  Future<_AboutData>? _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_AboutData> _load() async {
    final info = await PackageInfo.fromPlatform();
    final storage = SessionStorage();
    final email = await storage.getTraccarEmail();
    final userId = await storage.getTraccarUserId();

    return _AboutData(
      appName: info.appName,
      appVersion: '${info.version}+${info.buildNumber}',
      packageName: info.packageName,
      traccarEmail: email ?? '(unknown)',
      traccarUserId: userId?.toString() ?? '(unknown)',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('About & Server')),
      body: FutureBuilder<_AboutData>(
        future: _future,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final d = snapshot.data!;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _sectionHeader(context, 'App'),
              _row(context, 'Name', d.appName),
              _row(context, 'Version', d.appVersion),
              _row(context, 'Package', d.packageName, monospace: true),
              const SizedBox(height: 24),
              _sectionHeader(context, 'Signed in as'),
              _row(context, 'Email', d.traccarEmail),
              _row(context, 'Traccar user id', d.traccarUserId),
              const SizedBox(height: 24),
              _sectionHeader(context, 'Server endpoints'),
              Builder(
                builder: (ctx) {
                  final urls = Provider.of<ServerUrls>(ctx);
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _row(ctx, 'Traccar REST', urls.traccarBaseUrl, copyable: true, monospace: true),
                      _row(ctx, 'Traccar WebSocket', urls.traccarWsUrl, copyable: true, monospace: true),
                      _row(ctx, 'Relay', urls.relayBaseUrl, copyable: true, monospace: true),
                      const SizedBox(height: 12),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: () async {
                            final onChanged = Provider.of<void Function(ServerUrls)>(
                              ctx,
                              listen: false,
                            );
                            await Navigator.of(ctx).push(
                              MaterialPageRoute(
                                builder: (_) => ServerSetupScreen(
                                  initial: urls,
                                  onSaved: (u) {
                                    onChanged(u);
                                    Navigator.of(ctx).pop();
                                  },
                                ),
                              ),
                            );
                          },
                          icon: const Icon(Icons.edit_outlined, size: 16),
                          label: const Text('Change server URLs'),
                        ),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 24),
              _sectionHeader(context, 'Live'),
              _liveConnection(context),
            ],
          );
        },
      ),
    );
  }

  Widget _sectionHeader(BuildContext ctx, String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        label,
        style: Theme.of(ctx).textTheme.titleSmall?.copyWith(
              color: Theme.of(ctx).colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }

  Widget _row(
    BuildContext ctx,
    String label,
    String value, {
    bool copyable = false,
    bool monospace = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(
              label,
              style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                    color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                  ),
            ),
          ),
          Expanded(
            child: copyable
                ? InkWell(
                    onTap: () async {
                      await Clipboard.setData(ClipboardData(text: value));
                      if (ctx.mounted) {
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          const SnackBar(
                            content: Text('Copied'),
                            duration: Duration(seconds: 2),
                          ),
                        );
                      }
                    },
                    borderRadius: BorderRadius.circular(4),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 2),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text(
                              value,
                              style: TextStyle(
                                fontFamily: monospace ? 'monospace' : null,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Icon(
                            Icons.copy_outlined,
                            size: 14,
                            color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                          ),
                        ],
                      ),
                    ),
                  )
                : Text(
                    value,
                    style: TextStyle(fontFamily: monospace ? 'monospace' : null),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _liveConnection(BuildContext ctx) {
    return Consumer<TraccarSocket>(
      builder: (ctx, socket, _) {
        final (color, label) = switch (socket.state) {
          SocketState.connected => (Colors.green, 'Connected'),
          SocketState.connecting => (Colors.orange, 'Connecting...'),
          SocketState.reconnecting => (Colors.orange, 'Reconnecting...'),
          SocketState.disconnected => (Colors.grey, 'Disconnected'),
        };
        final last = socket.lastMessageAt;
        final lastLabel = last == null
            ? 'no messages yet'
            : 'last message ${_ago(last)}';

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                ),
                const SizedBox(width: 10),
                Text(label),
                const SizedBox(width: 12),
                Text(
                  lastLabel,
                  style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                        color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  String _ago(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inSeconds < 60) return '${d.inSeconds}s ago';
    if (d.inMinutes < 60) return '${d.inMinutes}m ago';
    return '${d.inHours}h ago';
  }
}

class _AboutData {
  final String appName;
  final String appVersion;
  final String packageName;
  final String traccarEmail;
  final String traccarUserId;

  const _AboutData({
    required this.appName,
    required this.appVersion,
    required this.packageName,
    required this.traccarEmail,
    required this.traccarUserId,
  });
}
