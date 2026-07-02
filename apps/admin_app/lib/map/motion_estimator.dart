import 'package:latlong2/latlong.dart';
import 'package:tracker_core/tracker_core.dart';

/// Continuous position estimator for one device.
///
/// Design goals:
///  - Smooth, continuous movement between real position updates.
///  - Bounded drift when the road curves or the phone stops reporting.
///  - Graceful deceleration when we run out of confident information.
///
/// Behavior:
///  - When a new [TraccarPosition] arrives, it becomes the anchor.
///  - Between anchors, [predictAt] extrapolates using speed + course,
///    but only within [maxExtrapolation] time AND [maxExtrapolationMeters]
///    distance.
///  - Extrapolation speed decays linearly to zero across the window,
///    so the marker glides confidently at first and eases to a stop.
///  - When a new anchor arrives, [predictAt] smoothly blends toward it
///    over [blendDuration] instead of teleporting.
class MotionEstimator {
  static const Distance _distance = Distance();

  /// Minimum speed (m/s) below which we do not extrapolate at all.
  /// GPS speed / course are unreliable at very low speeds.
  static const double minMovingSpeedMs = 1.5;

  /// Maximum time we are willing to extrapolate past the last anchor.
  /// After this, marker freezes at the decayed prediction point.
  static const Duration maxExtrapolation = Duration(seconds: 6);

  /// Maximum distance (meters) we will extrapolate past the anchor,
  /// regardless of speed. Prevents highway-speed markers from shooting
  /// across the map when a post is delayed.
  static const double maxExtrapolationMeters = 100.0;

  /// Time to blend from the previously shown point to the new anchor's
  /// predicted position when a fresh anchor arrives.
  static const Duration blendDuration = Duration(milliseconds: 500);

  TraccarPosition? _anchor;

  /// The point we were displaying at the moment [_anchor] was replaced.
  /// Used as the "from" end of the blend so we don't teleport.
  LatLng? _blendFrom;
  DateTime? _blendStart;

  bool get hasAnchor => _anchor != null;
  TraccarPosition? get anchor => _anchor;

  void submit(TraccarPosition p) {
    if (_anchor == null) {
      _anchor = p;
      _blendFrom = null;
      _blendStart = null;
      return;
    }

    final now = DateTime.now();
    final currentShown = predictAt(now);
    _blendFrom = currentShown;
    _blendStart = now;
    _anchor = p;
  }

  /// Compute where the marker should be shown at [when].
  LatLng predictAt(DateTime when) {
    final a = _anchor;
    if (a == null) return const LatLng(0, 0);

    final base = _extrapolateFromAnchor(a, when);

    final bf = _blendFrom;
    final bs = _blendStart;
    if (bf != null && bs != null) {
      final elapsed = when.difference(bs);
      if (elapsed >= blendDuration) {
        _blendFrom = null;
        _blendStart = null;
        return base;
      }
      final t = elapsed.inMilliseconds / blendDuration.inMilliseconds;
      final eased = _easeOutCubic(t);
      return _lerp(bf, base, eased);
    }

    return base;
  }

  LatLng _extrapolateFromAnchor(TraccarPosition a, DateTime when) {
    final anchorPoint = LatLng(a.latitude, a.longitude);
    final elapsed = when.difference(a.fixTime);

    if (elapsed.isNegative) return anchorPoint;
    if (a.speed < minMovingSpeedMs) return anchorPoint;

    // How far into the extrapolation window are we? (0..1)
    final windowMs = maxExtrapolation.inMilliseconds;
    final elapsedMs = elapsed.inMilliseconds;
    final t = (elapsedMs / windowMs).clamp(0.0, 1.0).toDouble();

    // Linearly decay speed so the marker eases to a stop at the window edge.
    // effective speed factor: 1.0 at t=0, 0.0 at t=1
    final decay = 1.0 - t;

    // Integral of (speed * decay) over [0, elapsed]:
    //   distance = speed * elapsed * (1 - t/2)
    // (i.e. average of full speed at start and decayed speed at now)
    final elapsedSec = elapsedMs / 1000.0;
    final effectiveDistance = a.speed * elapsedSec * (1.0 - t / 2.0);

    // Enforce absolute distance cap regardless of speed.
    final capped = effectiveDistance.clamp(0.0, maxExtrapolationMeters);

    return _distance.offset(anchorPoint, capped, a.course);
  }

  LatLng _lerp(LatLng a, LatLng b, double t) {
    return LatLng(
      a.latitude + (b.latitude - a.latitude) * t,
      a.longitude + (b.longitude - a.longitude) * t,
    );
  }

  double _easeOutCubic(double t) {
    final u = 1 - t;
    return 1 - u * u * u;
  }
}
