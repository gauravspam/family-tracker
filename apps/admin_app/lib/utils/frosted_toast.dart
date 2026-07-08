import 'dart:ui';
import 'package:flutter/material.dart';

OverlayEntry _buildEntry(BuildContext context, Widget body, VoidCallback onDismiss) {
  final topPad = MediaQuery.of(context).padding.top;
  final headerBottom = topPad + 68;
  return OverlayEntry(
    builder: (_) => Positioned(
      left: 16,
      right: 16,
      top: headerBottom + 8,
      child: Material(
        color: Colors.transparent,
        child: Dismissible(
          key: const ValueKey('geofence_toast'),
          direction: DismissDirection.horizontal,
          onDismissed: (_) => onDismiss(),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
              child: body,
            ),
          ),
        ),
      ),
    ),
  );
}

void showGeofenceToast({
  required NavigatorState navigator,
  required bool isEnter,
  required String geoLabel,
  required String deviceName,
}) {
  final context = navigator.context;
  final scheme = Theme.of(context).colorScheme;
  final isDark = Theme.of(context).brightness == Brightness.dark;
  final accent = isEnter ? Colors.green : Colors.red;

  late final OverlayEntry entry;
  entry = _buildEntry(
    context,
    Container(
      padding: const EdgeInsets.fromLTRB(0, 14, 18, 14),
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: isDark ? 0.3 : 0.25),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.08)
              : Colors.black.withValues(alpha: 0.04),
          width: 0.5,
        ),
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
          Container(
            width: 5,
            height: 48,
            decoration: BoxDecoration(
              color: accent,
              borderRadius: const BorderRadius.only(
                topRight: Radius.circular(3),
                bottomRight: Radius.circular(3),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Icon(
            isEnter ? Icons.login_rounded : Icons.logout_rounded,
            color: accent,
            size: 22,
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${isEnter ? "Entered" : "Exited"} $geoLabel',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  color: scheme.onSurface,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                deviceName,
                style: TextStyle(
                  fontSize: 12,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ],
      ),
    ),
    () => entry.remove(),
  );

  navigator.overlay?.insert(entry);
  Future.delayed(const Duration(seconds: 4), () {
    if (entry.mounted) entry.remove();
  });
}
