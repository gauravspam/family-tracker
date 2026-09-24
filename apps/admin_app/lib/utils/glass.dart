import 'dart:ui';

import 'package:flutter/widgets.dart';

/// Conditionally applies a backdrop blur. When [enabled] is false the child
/// is returned unwrapped so weak GPUs skip the expensive filter entirely.
///
/// Callers should raise their tint alpha when disabled (the [opaqueAlpha]
/// pattern) since there is no blur to guarantee contrast underneath.
class GlassBlur extends StatelessWidget {
  final bool enabled;
  final double sigmaX;
  final double sigmaY;
  final Widget child;

  const GlassBlur({
    super.key,
    required this.enabled,
    required this.child,
    this.sigmaX = 30,
    this.sigmaY = 30,
  });

  @override
  Widget build(BuildContext context) {
    if (!enabled) return child;
    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: sigmaX, sigmaY: sigmaY),
      child: child,
    );
  }
}
