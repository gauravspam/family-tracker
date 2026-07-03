import 'package:flutter/material.dart';

/// Curated Material-friendly palette for per-device color picking.
/// Stored in Traccar device attributes under key "color" as a #RRGGBB string.
class DeviceColorPalette {
  static const List<Color> all = [
    Color(0xFF4CAF50), // green (default)
    Color(0xFF2196F3), // blue
    Color(0xFFF44336), // red
    Color(0xFFFF9800), // orange
    Color(0xFF9C27B0), // purple
    Color(0xFF00BCD4), // cyan
    Color(0xFFE91E63), // pink
    Color(0xFF795548), // brown
    Color(0xFF607D8B), // blue-grey
    Color(0xFFFFC107), // amber
    Color(0xFF3F51B5), // indigo
    Color(0xFF009688), // teal
  ];

  static const Color defaultColor = Color(0xFF4CAF50);

  /// Parse "#RRGGBB" or "0xAARRGGBB" strings. Falls back to [defaultColor].
  static Color parse(String? s) {
    if (s == null || s.isEmpty) return defaultColor;
    var v = s.trim();
    if (v.startsWith('#')) v = v.substring(1);
    if (v.length == 6) v = 'FF$v';
    final n = int.tryParse(v, radix: 16);
    if (n == null) return defaultColor;
    return Color(n);
  }

  /// Serialise a Color to "#RRGGBB".
  static String toHex(Color c) {
    // Extract 8-bit channels without using the deprecated .value getter.
    final r = (c.r * 255).round().toRadixString(16).padLeft(2, '0');
    final g = (c.g * 255).round().toRadixString(16).padLeft(2, '0');
    final b = (c.b * 255).round().toRadixString(16).padLeft(2, '0');
    return '#${r.toUpperCase()}${g.toUpperCase()}${b.toUpperCase()}';
  }
}
