import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../auth/auth_controller.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController(text: 'admin@family-tracker.local');
  final _passCtrl = TextEditingController();
  final _tokenCtrl = TextEditingController();

  bool _busy = false;
  bool _obscurePass = true;
  bool _obscureToken = true;

  @override
  void initState() {
    super.initState();
    // Rebuild on any field change so the Sign In button enables/disables live.
    _emailCtrl.addListener(_onChange);
    _passCtrl.addListener(_onChange);
    _tokenCtrl.addListener(_onChange);
  }

  void _onChange() => setState(() {});

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    _tokenCtrl.dispose();
    super.dispose();
  }

  // ── Validators ─────────────────────────────────────────────────

  String? _validateEmail(String? v) {
    final s = v?.trim() ?? '';
    if (s.isEmpty) return 'Email is required';
    if (!s.contains('@') || !s.contains('.')) return 'Enter a valid email';
    return null;
  }

  String? _validatePassword(String? v) {
    if (v == null || v.isEmpty) return 'Password is required';
    return null;
  }

  String? _validateToken(String? v) {
    final s = v?.trim() ?? '';
    if (s.isEmpty) return 'Relay admin token is required';
    if (s.length < 3) return 'Token looks too short';
    return null;
  }

  bool get _formValid {
    return _validateEmail(_emailCtrl.text) == null &&
        _validatePassword(_passCtrl.text) == null &&
        _validateToken(_tokenCtrl.text) == null;
  }

  // ── Actions ────────────────────────────────────────────────────

  Future<void> _submit() async {
    if (_busy) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _busy = true);

    final messenger = ScaffoldMessenger.of(context);
    final auth = context.read<AuthController>();

    final ok = await auth.login(
      email: _emailCtrl.text.trim(),
      password: _passCtrl.text,
      relayAdminToken: _tokenCtrl.text.trim(),
    );

    if (!mounted) return;
    setState(() => _busy = false);

    if (!ok) {
      final err = auth.lastError ?? 'Unknown error';
      messenger.showSnackBar(
        SnackBar(content: Text(err), backgroundColor: Colors.red.shade700),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _formKey,
                autovalidateMode: AutovalidateMode.onUserInteraction,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Icon(Icons.location_on, size: 72, color: Colors.blue),
                    const SizedBox(height: 16),
                    Text(
                      'Family Tracker Admin',
                      style: Theme.of(context).textTheme.headlineSmall,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 32),
                    TextFormField(
                      controller: _emailCtrl,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      enabled: !_busy,
                      validator: _validateEmail,
                      decoration: const InputDecoration(
                        labelText: 'Traccar email',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.email_outlined),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _passCtrl,
                      obscureText: _obscurePass,
                      textInputAction: TextInputAction.next,
                      enabled: !_busy,
                      validator: _validatePassword,
                      decoration: InputDecoration(
                        labelText: 'Traccar password',
                        border: const OutlineInputBorder(),
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          icon: Icon(_obscurePass
                              ? Icons.visibility_off
                              : Icons.visibility),
                          onPressed: () =>
                              setState(() => _obscurePass = !_obscurePass),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _tokenCtrl,
                      obscureText: _obscureToken,
                      textInputAction: TextInputAction.done,
                      enabled: !_busy,
                      validator: _validateToken,
                      onFieldSubmitted: (_) => _formValid ? _submit() : null,
                      decoration: InputDecoration(
                        labelText: 'Relay admin token',
                        border: const OutlineInputBorder(),
                        prefixIcon: const Icon(Icons.key),
                        suffixIcon: IconButton(
                          icon: Icon(_obscureToken
                              ? Icons.visibility_off
                              : Icons.visibility),
                          onPressed: () =>
                              setState(() => _obscureToken = !_obscureToken),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: (_busy || !_formValid) ? null : _submit,
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
                          : const Text('Sign in'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
