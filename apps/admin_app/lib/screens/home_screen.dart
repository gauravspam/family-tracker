import 'dart:ui';

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
  late final PageController _pageController;
  int _currentTab = 1;

  static const _tabs = [
    _TabMeta(icon: Icons.list_alt_rounded, label: 'Devices'),
    _TabMeta(icon: Icons.map_rounded, label: 'Map'),
    _TabMeta(icon: Icons.inbox_rounded, label: 'Pending'),
  ];

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: 1);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _onTabTapped(int index) {
    setState(() => _currentTab = index);
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  void _onPageChanged(int index) {
    setState(() => _currentTab = index);
  }

  Future<void> _refresh() async {
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
            children: const [
              DevicesScreen(),
              MapScreen(),
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
  final VoidCallback onAbout;
  final VoidCallback onSignOut;

  const _FloatingHeader({
    required this.title,
    required this.onRefresh,
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
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: EdgeInsets.only(
            top: topPadding + 8,
            left: 20,
            right: 8,
            bottom: 12,
          ),
          decoration: BoxDecoration(
            color: scheme.surface.withValues(alpha: isDark ? 0.4 : 0.25),
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
                onSelected: (choice) {
                  if (choice == 'about') onAbout();
                  if (choice == 'signout') onSignOut();
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'about', child: Text('About & Server')),
                  PopupMenuItem(value: 'signout', child: Text('Sign out')),
                ],
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
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Container(
          height: 60,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            color: isDark
                ? Colors.grey.shade900.withValues(alpha: 0.85)
                : Colors.white.withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(28),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.15),
                blurRadius: 12,
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
        margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
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
              label: badge != null ? Text('$badge') : null,
              child: Icon(icon, color: iconColor, size: 22),
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
