import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../api/relay_api.dart';
import '../api/traccar_api.dart';
import '../auth/auth_controller.dart';
import '../state/devices_controller.dart';
import '../state/geofences_controller.dart';
import '../state/hidden_devices_controller.dart';
import '../state/pending_controller.dart';
import '../state/theme_controller.dart';
import 'about_screen.dart';
import 'devices_screen.dart';
import 'event_log_screen.dart';
import 'geofence_sheet.dart';
import 'map_screen.dart';
import 'pending_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final PageController _pageController;
  int _currentTab = 1;
  int _mapRemountSignal = 0;
  ({String name, double radius})? _pendingGeofence;
  Timer? _pendingTimer;
  bool _mapOverlayVisible = false;

  static const _tabs = [
    _TabMeta(icon: Icons.list_alt_rounded, label: 'Devices'),
    _TabMeta(icon: Icons.map_rounded, label: 'Map'),
    _TabMeta(icon: Icons.inbox_rounded, label: 'Pending'),
  ];

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: 1);
    _startPendingTimer();
    _startGeofencePollTimer();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _listenToHiddenChanges();
      _loadGeofences();
    });
  }

  @override
  void dispose() {
    _pendingTimer?.cancel();
    _geofencePollTimer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  void _listenToHiddenChanges() {
    final hidden = context.read<HiddenDevicesController>();
    hidden.addListener(_onHiddenChanged);
  }

  void _onHiddenChanged() {
    if (_currentTab == 0) {
      context.read<DevicesController>().refresh();
    }
  }

  void _startPendingTimer() {
    _pendingTimer?.cancel();
    _pendingTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted) return;
      if (_currentTab == 2) {
        context.read<PendingController>().refresh();
      }
    });
  }

  void _loadGeofences() {
    try {
      context.read<GeofencesController>().refresh();
    } catch (_) {}
  }

  Timer? _geofencePollTimer;

  void _startGeofencePollTimer() {
    _geofencePollTimer?.cancel();
    _geofencePollTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!mounted) return;
      _loadGeofences();
    });
  }

  Future<void> _onTabTapped(int index) async {
    HapticFeedback.mediumImpact();
    setState(() => _currentTab = index);
    await _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
    if (mounted) setState(() => _mapRemountSignal++);
    _onTabSelected(index);
  }

  void _onPageChanged(int index) {
    setState(() {
      _currentTab = index;
      _mapRemountSignal++;
    });
    _onTabSelected(index);
  }

  void _onTabSelected(int index) {
    Future.microtask(() {
      if (!mounted) return;
      switch (index) {
        case 0:
          context.read<DevicesController>().refresh();
        case 1:
          _loadGeofences();
        case 2:
          context.read<PendingController>().refresh();
      }
    });
  }

  void _showThemeDialog(BuildContext ctx) {
    final controller = ctx.read<ThemeController>();
    showDialog(
      context: ctx,
      builder: (dCtx) => AlertDialog(
        title: const Text('Theme'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final entry in [
              (ThemeMode.system, 'System', Icons.settings_brightness),
              (ThemeMode.light, 'Light', Icons.light_mode),
              (ThemeMode.dark, 'Dark', Icons.dark_mode),
            ])
              ListTile(
                leading: Icon(entry.$3),
                title: Text(entry.$2),
                trailing: controller.mode == entry.$1
                    ? const Icon(Icons.check, color: Colors.green)
                    : null,
                onTap: () {
                  controller.setMode(entry.$1);
                  Navigator.pop(dCtx);
                },
              ),
          ],
        ),
      ),
    );
  }

  void _showManageHidden(BuildContext ctx) {
    final hidden = ctx.read<HiddenDevicesController>();

    if (!hidden.hasPasscode) {
      _showSetPasscodeDialog(ctx, hidden);
      return;
    }

    _requirePasscode(ctx, hidden, () {
      final devices = ctx.read<DevicesController>();
      showDialog(
        context: ctx,
        builder: (dCtx) => AlertDialog(
          title: const Text('Manage Hidden'),
          content: SizedBox(
            width: double.maxFinite,
            child: devices.devices.isEmpty
                ? const Text('No devices yet.')
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final d in devices.devices)
                        CheckboxListTile(
                          title: Text(d.displayName),
                          subtitle: Text(d.device.uniqueId),
                          value: hidden.isHidden(d.device.id),
                          onChanged: (_) {
                            hidden.toggleHidden(d.device.id);
                            Navigator.pop(dCtx);
                          },
                        ),
                    ],
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dCtx);
                _showSetPasscodeDialog(ctx, hidden);
              },
              child: const Text('Change Passcode'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dCtx),
              child: const Text('Done'),
            ),
          ],
      ),
    );
  });
  }

  void _requirePasscode(BuildContext ctx, HiddenDevicesController hidden, VoidCallback onVerified) {
    final codeController = TextEditingController();
    showDialog(
      context: ctx,
      builder: (dCtx) => AlertDialog(
        title: const Text('Enter Passcode'),
        content: TextField(
          controller: codeController,
          autofocus: true,
          obscureText: true,
          keyboardType: TextInputType.number,
          maxLength: 6,
          decoration: const InputDecoration(
            labelText: 'Passcode',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (v) {
            if (hidden.verifyPasscode(v)) {
              Navigator.pop(dCtx);
              onVerified();
            }
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dCtx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (hidden.verifyPasscode(codeController.text)) {
                Navigator.pop(dCtx);
                onVerified();
              } else {
                ScaffoldMessenger.of(dCtx).showSnackBar(
                  const SnackBar(
                    content: Text('Incorrect passcode'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            child: const Text('Unlock'),
          ),
        ],
      ),
    );
  }

  void _showShowHiddenDialog(BuildContext ctx) {
    final hidden = ctx.read<HiddenDevicesController>();

    if (!hidden.hasPasscode) {
      _showSetPasscodeDialog(ctx, hidden);
      return;
    }

    if (hidden.isShowingHidden) {
      hidden.hideHidden();
      ScaffoldMessenger.of(ctx).showSnackBar(
        const SnackBar(content: Text('Hidden devices hidden')),
      );
      return;
    }

    final codeController = TextEditingController();
    showDialog(
      context: ctx,
      builder: (dCtx) => AlertDialog(
        title: const Text('Enter Passcode'),
        content: TextField(
          controller: codeController,
          autofocus: true,
          obscureText: true,
          keyboardType: TextInputType.number,
          maxLength: 6,
          decoration: const InputDecoration(
            labelText: 'Passcode',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (v) {
            if (hidden.verifyPasscode(v)) {
              hidden.showHidden();
              Navigator.pop(dCtx);
            }
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dCtx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (hidden.verifyPasscode(codeController.text)) {
                hidden.showHidden();
                Navigator.pop(dCtx);
              } else {
                ScaffoldMessenger.of(dCtx).showSnackBar(
                  const SnackBar(
                    content: Text('Incorrect passcode'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            child: const Text('Unlock'),
          ),
        ],
      ),
    );
  }

  void _showSetPasscodeDialog(BuildContext ctx, HiddenDevicesController hidden) {
    final codeController = TextEditingController();
    final confirmController = TextEditingController();

    showDialog(
      context: ctx,
      builder: (dCtx) => AlertDialog(
        title: const Text('Set Passcode'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: codeController,
              autofocus: true,
              obscureText: true,
              keyboardType: TextInputType.number,
              maxLength: 6,
              decoration: const InputDecoration(
                labelText: 'New passcode (4-6 digits)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: confirmController,
              obscureText: true,
              keyboardType: TextInputType.number,
              maxLength: 6,
              decoration: const InputDecoration(
                labelText: 'Confirm passcode',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dCtx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final code = codeController.text;
              if (code.length < 4) {
                ScaffoldMessenger.of(dCtx).showSnackBar(
                  const SnackBar(
                    content: Text('Passcode must be 4-6 digits'),
                    backgroundColor: Colors.red,
                  ),
                );
                return;
              }
              if (code != confirmController.text) {
                ScaffoldMessenger.of(dCtx).showSnackBar(
                  const SnackBar(
                    content: Text('Passcodes do not match'),
                    backgroundColor: Colors.red,
                  ),
                );
                return;
              }
              hidden.setPasscode(code);
              Navigator.pop(dCtx);
              ScaffoldMessenger.of(ctx).showSnackBar(
                const SnackBar(content: Text('Passcode set')),
              );
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _refresh() async {
    final auth = context.read<AuthController>();
    final devices = context.read<DevicesController>();
    final pending = context.read<PendingController>();
    final relay = context.read<RelayApi>();

    try {
      // Send locate to all approved devices (Device & Map tabs only)
      if (_currentTab != 2) {
        for (final d in devices.devices) {
          try {
            await relay.locateDevice(d.device.id);
          } catch (_) {
            // best-effort per device
          }
        }
      }
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
    final bottomPadding = MediaQuery.of(context).viewPadding.bottom;

    return Scaffold(
      extendBody: true,
      extendBodyBehindAppBar: true,
      body: Stack(
        children: [
          // ── Pages ─────────────────────────────────────────────────
          PageView(
            controller: _pageController,
            onPageChanged: _onPageChanged,
            // Disable swipe on map tab to avoid fighting with map pan
            physics: _currentTab == 1
                ? const NeverScrollableScrollPhysics()
                : const BouncingScrollPhysics(),
            children: [
              DevicesScreen(),
              MapScreen(
                remountSignal: _mapRemountSignal,
                pendingGeofence: _pendingGeofence,
                onPlacementStarted: () {
                  if (mounted) setState(() => _pendingGeofence = null);
                },
                onOverlayVisibilityChanged: (v) {
                  if (mounted && _mapOverlayVisible != v) {
                    setState(() => _mapOverlayVisible = v);
                  }
                },
              ),
              PendingScreen(),
            ],
          ),

          // ── Header ────────────────────────────────────────────────
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: _FloatingHeader(
              title: _tabs[_currentTab].label,
              onRefresh: _refresh,
              onTheme: () => _showThemeDialog(context),
              onGeofences: () async {
                final result = await showGeofenceSheet(context);
                if (result != null && mounted) {
                  setState(() {
                    _pendingGeofence = result;
                    _mapRemountSignal++;
                  });
                  _onTabTapped(1);
                }
              },
              onEventLog: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const EventLogScreen()),
                );
              },
              onManageHidden: () => _showManageHidden(context),
              onShowHidden: () => _showShowHiddenDialog(context),
              onAbout: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const AboutScreen()),
                );
              },
              onSignOut: () async {
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
              },
            ),
          ),

          // ── Nav pill ──────────────────────────────────────────────
          if (!_mapOverlayVisible)
            Positioned(
            bottom: bottomPadding + 16,
            left: 0,
            right: 0,
            child: Center(
              child: _PillNav(
                tabs: _tabs,
                currentIndex: _currentTab,
                onTap: _onTabTapped,
                pendingCount: context.select<PendingController, int>(
                  (c) => c.items.length,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TabMeta {
  final IconData icon;
  final String label;
  const _TabMeta({required this.icon, required this.label});
}

// ── Header ──────────────────────────────────────────────────────────────

class _FloatingHeader extends StatelessWidget {
  final String title;
  final VoidCallback onRefresh;
  final VoidCallback onTheme;
  final VoidCallback onGeofences;
  final VoidCallback onEventLog;
  final VoidCallback onManageHidden;
  final VoidCallback onShowHidden;
  final VoidCallback onAbout;
  final VoidCallback onSignOut;

  const _FloatingHeader({
    required this.title,
    required this.onRefresh,
    required this.onTheme,
    required this.onGeofences,
    required this.onEventLog,
    required this.onManageHidden,
    required this.onShowHidden,
    required this.onAbout,
    required this.onSignOut,
  });

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).viewPadding.top;
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return ClipRRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
        child: Container(
          padding: EdgeInsets.only(
            top: topPadding + 8,
            left: 20,
            right: 8,
            bottom: 12,
          ),
          decoration: BoxDecoration(
            color: scheme.surface.withValues(alpha: isDark ? 0.25 : 0.2),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.refresh_rounded, size: 22),
                tooltip: 'Refresh',
                onPressed: onRefresh,
              ),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert_rounded, size: 22),
                elevation: 2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                color: scheme.surface,
                onSelected: (choice) {
                  if (choice == 'theme') onTheme();
                  if (choice == 'geofences') onGeofences();
                  if (choice == 'event_log') onEventLog();
                  if (choice == 'manage_hidden') onManageHidden();
                  if (choice == 'show_hidden') onShowHidden();
                  if (choice == 'about') onAbout();
                  if (choice == 'signout') onSignOut();
                },
                itemBuilder: (_) {
                  final hidden = context.read<HiddenDevicesController>();
                  return [
                    const PopupMenuItem(
                      value: 'theme',
                      child: Text('Theme'),
                    ),
                    const PopupMenuItem(
                      value: 'geofences',
                      child: Text('Geofences'),
                    ),
                    const PopupMenuItem(
                      value: 'event_log',
                      child: Text('Event Log'),
                    ),
                    const PopupMenuItem(
                      value: 'manage_hidden',
                      child: Text('Manage Hidden'),
                    ),
                    PopupMenuItem(
                      value: 'show_hidden',
                      child: Text(hidden.isShowingHidden ? 'Hide Hidden' : 'Show Hidden'),
                    ),
                    const PopupMenuItem(
                      value: 'about',
                      child: Text('About & Server'),
                    ),
                    const PopupMenuItem(
                      value: 'signout',
                      child: Text('Sign out'),
                    ),
                  ];
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Pill nav ────────────────────────────────────────────────────────────

class _PillNav extends StatelessWidget {
  final List<_TabMeta> tabs;
  final int currentIndex;
  final ValueChanged<int> onTap;
  final int pendingCount;

  const _PillNav({
    required this.tabs,
    required this.currentIndex,
    required this.onTap,
    required this.pendingCount,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 60, sigmaY: 60),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          decoration: BoxDecoration(
            color: isDark
                ? Colors.grey.shade900.withValues(alpha: 0.4)
                : Colors.white.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.1)
                  : Colors.black.withValues(alpha: 0.05),
              width: 0.5,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.12),
                blurRadius: 20,
                spreadRadius: 2,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < tabs.length; i++)
                _PillNavItem(
                  icon: tabs[i].icon,
                  label: tabs[i].label,
                  selected: currentIndex == i,
                  badge: (i == 2 && pendingCount > 0) ? pendingCount : null,
                  onTap: () => onTap(i),
                  isDark: isDark,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PillNavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final int? badge;
  final VoidCallback onTap;
  final bool isDark;

  const _PillNavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.badge,
    required this.onTap,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    final iconColor = selected
        ? scheme.primary
        : isDark
            ? Colors.grey.shade400
            : Colors.grey.shade600;

    final textColor = selected
        ? scheme.primary
        : isDark
            ? Colors.grey.shade400
            : Colors.grey.shade600;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.symmetric(horizontal: 2),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? scheme.primaryContainer.withValues(alpha: isDark ? 0.3 : 0.5)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(22),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Badge(
              isLabelVisible: badge != null && badge! > 0,
              label: badge != null ? Text('$badge', style: const TextStyle(fontSize: 10)) : null,
              child: Icon(icon, color: iconColor, size: 20),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                color: textColor,
                fontSize: 11,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
