import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/relay_api.dart';
import '../api/traccar_api.dart';
import '../auth/auth_controller.dart';
import '../state/devices_controller.dart';
import '../state/pending_controller.dart';
import 'about_screen.dart';
import 'devices_screen.dart';
import 'map_screen.dart';
import 'pending_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tab = 0;

  Future<void> _refresh() async {
    // Capture before any await so we don't reuse BuildContext across gaps.
    final auth = context.read<AuthController>();
    final devices = context.read<DevicesController>();
    final pending = context.read<PendingController>();

    try {
      await devices.refresh();
      await pending.refresh();
    } on TraccarUnauthorized {
      await auth.logout();
    } on RelayUnauthorized {
      await auth.logout();
    }
  }

  @override
  Widget build(BuildContext context) {
    final titles = ['Devices', 'Map', 'Pending'];

    return Scaffold(
      appBar: AppBar(
        title: Text(titles[_tab]),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _refresh,
          ),
          PopupMenuButton<String>(
            onSelected: (choice) async {
              if (choice == 'about') {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const AboutScreen()),
                );
              } else if (choice == 'signout') {
                final auth = context.read<AuthController>();
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Sign out?'),
                    content: const Text(
                      'You will need to sign in again with your Traccar credentials and relay admin token.',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('Cancel'),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('Sign out'),
                      ),
                    ],
                  ),
                );
                if (confirm == true) {
                  await auth.logout();
                }
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'about', child: Text('About & Server')),
              PopupMenuItem(value: 'signout', child: Text('Sign out')),
            ],
          ),
        ],
      ),
      body: IndexedStack(
        index: _tab,
        children: const [
          DevicesScreen(),
          MapScreen(),
          PendingScreen(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.list), label: 'Devices'),
          NavigationDestination(icon: Icon(Icons.map), label: 'Map'),
          NavigationDestination(icon: _PendingIcon(), label: 'Pending'),
        ],
      ),
    );
  }
}

class _PendingIcon extends StatelessWidget {
  const _PendingIcon();

  @override
  Widget build(BuildContext context) {
    return Consumer<PendingController>(
      builder: (context, controller, _) {
        final count = controller.items.length;
        if (count == 0) return const Icon(Icons.inbox);
        return Badge(
          label: Text('$count'),
          child: const Icon(Icons.inbox),
        );
      },
    );
  }
}
