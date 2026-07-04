import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';

/// Reverse geocoding via OpenStreetMap Nominatim.
///
/// Public policy: <= 1 req/sec per IP, meaningful User-Agent, cache aggressively.
/// See https://operations.osmfoundation.org/policies/nominatim/
///
/// This client:
///  - caches results in memory, keyed by lat/lon rounded to 5 decimals (~1m)
///  - serializes requests through a 1-second gate to respect the rate limit
///  - returns null on failure so callers can fall back to raw coordinates
class GeocodeService {
  static final GeocodeService instance = GeocodeService._();
  GeocodeService._();

  static const _endpoint = 'https://nominatim.openstreetmap.org/reverse';
  static const _cacheLimit = 256;

  final _cache = <String, String>{};
  DateTime _lastRequest = DateTime.fromMillisecondsSinceEpoch(0);
  Future<void>? _pendingThrottle;

  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 8),
      receiveTimeout: const Duration(seconds: 8),
      responseType: ResponseType.plain,
      headers: {
        'User-Agent': 'FamilyTrackerAdmin/1.0 (self-hosted family tracker)',
      },
    ),
  );

  /// Returns a human-friendly single-line address for [lat]/[lon],
  /// or null if the lookup fails.
  Future<String?> reverse(double lat, double lon) async {
    final key = _keyFor(lat, lon);
    final cached = _cache[key];
    if (cached != null) return cached;

    await _throttle();

    try {
      final response = await _dio.get(
        _endpoint,
        queryParameters: {
          'lat': lat.toStringAsFixed(5),
          'lon': lon.toStringAsFixed(5),
          'format': 'jsonv2',
          'zoom': '17', // road / building level
          'addressdetails': '1',
        },
      );

      if (response.statusCode != 200 || response.data is! String) return null;
      final data = jsonDecode(response.data as String);
      if (data is! Map) return null;

      final formatted = _formatAddress(Map<String, dynamic>.from(data));
      if (formatted != null) {
        _cache[key] = formatted;
        _pruneCache();
      }
      return formatted;
    } catch (_) {
      return null;
    }
  }

  Future<void> _throttle() async {
    // Serialize concurrent callers so only one passes through at a time,
    // preventing bursts that violate the Nominatim 1-req/sec policy.
    while (_pendingThrottle != null) {
      await _pendingThrottle;
    }
    final completer = Completer<void>();
    _pendingThrottle = completer.future;
    try {
      final now = DateTime.now();
      final elapsed = now.difference(_lastRequest);
      if (elapsed < const Duration(milliseconds: 1100)) {
        await Future.delayed(const Duration(milliseconds: 1100) - elapsed);
      }
      _lastRequest = DateTime.now();
    } finally {
      _pendingThrottle = null;
      completer.complete();
    }
  }

  String _keyFor(double lat, double lon) =>
      '${lat.toStringAsFixed(5)},${lon.toStringAsFixed(5)}';

  void _pruneCache() {
    if (_cache.length <= _cacheLimit) return;
    final drop = _cache.length - _cacheLimit;
    for (final k in _cache.keys.take(drop).toList()) {
      _cache.remove(k);
    }
  }

  String? _formatAddress(Map<String, dynamic> data) {
    final address = data['address'] as Map?;
    if (address == null) {
      final display = data['display_name'] as String?;
      return display?.isNotEmpty == true ? display : null;
    }

    final a = Map<String, dynamic>.from(address);
    // Pick a compact "primary line" from the specific-to-general fields.
    String? primary;
    for (final key in const [
      'road', 'pedestrian', 'footway', 'residential', 'neighbourhood',
      'suburb', 'hamlet', 'village', 'town', 'city_district', 'city',
    ]) {
      final v = a[key] as String?;
      if (v != null && v.isNotEmpty) {
        primary = v;
        break;
      }
    }

    // A locality for context.
    final locality = a['suburb'] as String? ??
        a['neighbourhood'] as String? ??
        a['hamlet'] as String? ??
        a['village'] as String? ??
        a['town'] as String? ??
        a['city'] as String?;

    final parts = <String>[
      if (primary != null) primary,
      if (locality != null && locality != primary) locality,
    ];

    if (parts.isEmpty) {
      final display = data['display_name'] as String?;
      if (display == null || display.isEmpty) return null;
      // Trim overly long display strings to first 2 parts.
      final split = display.split(',').map((s) => s.trim()).toList();
      return split.take(2).join(', ');
    }
    return parts.join(', ');
  }
}
