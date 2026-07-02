import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/traccar_api.dart';
import '../auth/auth_controller.dart';
import '../state/devices_controller.dart';
import 'devices_screen.dart';
import 'map_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tab = 0;

  Future<void> _refresh() async {
    try {
      await context.read<DevicesController>().refresh();
    } on TraccarUnauthorized {
      if (mounted) {
        await context.read<AuthController>().logout();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_tab == 0 ? 'Devices' : 'Map'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _refresh,
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Sign out',
            onPressed: () async {
              await context.read<AuthController>().logout();
            },
          ),
        ],
      ),
      body: IndexedStack(
        index: _tab,
        children: const [
          DevicesScreen(),
          MapScreen(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.list), label: 'Devices'),
          NavigationDestination(icon: Icon(Icons.map), label: 'Map'),
        ],
      ),
    );
  }
}
