import 'package:flutter/material.dart';

import '../config/server_config.dart';

/// Shown on first launch (and via the About screen menu) to collect the
/// relay + Traccar URLs. On success, calls [onSaved] with the new URLs.
class ServerSetupScreen extends StatefulWidget {
  final ServerUrls? initial;
  final void Function(ServerUrls urls) onSaved;

  const ServerSetupScreen({
    super.key,
    this.initial,
    required this.onSaved,
  });

  @override
  State<ServerSetupScreen> createState() => _ServerSetupScreenState();
}

class _ServerSetupScreenState extends State<ServerSetupScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _relayCtrl;
  late final TextEditingController _traccarCtrl;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _relayCtrl = TextEditingController(
      text: widget.initial?.relayBaseUrl ?? '',
    );
    _traccarCtrl = TextEditingController(
      text: widget.initial?.traccarBaseUrl ?? '',
    );
    _relayCtrl.addListener(() => setState(() {}));
    _traccarCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _relayCtrl.dispose();
    _traccarCtrl.dispose();
    super.dispose();
  }

  bool get _valid =>
      ServerUrls.validateUrl(_relayCtrl.text) == null &&
      ServerUrls.validateUrl(_traccarCtrl.text) == null;

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _busy = true);

    final urls = ServerUrls(
      relayBaseUrl: _relayCtrl.text.trim(),
      traccarBaseUrl: _traccarCtrl.text.trim(),
    );

    await ServerConfig().save(urls);
    widget.onSaved(urls);

    if (!mounted) return;
    setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final isFirstRun = widget.initial == null;
    return Scaffold(
      appBar: AppBar(
        title: Text(isFirstRun ? 'Server setup' : 'Edit server URLs'),
        automaticallyImplyLeading: !isFirstRun,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            autovalidateMode: AutovalidateMode.onUserInteraction,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (isFirstRun) ...[
                  const Icon(Icons.dns_outlined, size: 64, color: Colors.blue),
                  const SizedBox(height: 12),
                  Text(
                    'Enter the URLs of your relay and Traccar servers.',
                    style: Theme.of(context).textTheme.bodyMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                ],
                TextFormField(
                  controller: _relayCtrl,
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  enabled: !_busy,
                  validator: (v) => ServerUrls.validateUrl(v),
                  decoration: const InputDecoration(
                    labelText: 'Relay URL',
                    hintText: 'http://192.168.1.35:8080',
                    helperText:
                        'Your relay service HTTP endpoint. Include the port. No trailing slash.',
                    helperMaxLines: 2,
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.hub_outlined),
                  ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _traccarCtrl,
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  enabled: !_busy,
                  validator: (v) => ServerUrls.validateUrl(v),
                  decoration: const InputDecoration(
                    labelText: 'Traccar base URL',
                    hintText: 'http://192.168.1.35:8082',
                    helperText:
                        'Your Traccar server HTTP endpoint. WebSocket URL is derived automatically.',
                    helperMaxLines: 2,
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.storage_outlined),
                  ),
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: (_busy || !_valid) ? null : _submit,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: _busy
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text(isFirstRun ? 'Continue' : 'Save'),
                ),
                if (!isFirstRun) ...[
                  const SizedBox(height: 16),
                  Text(
                    'You may need to sign in again after changing URLs.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
