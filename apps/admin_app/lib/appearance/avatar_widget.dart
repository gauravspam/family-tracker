import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'avatars.dart';
import 'colors.dart';

/// Displays a device avatar: emoji SVG on a white circle, surrounded by a
/// colored ring that represents the per-device color.
class DeviceAvatar extends StatelessWidget {
  final String? avatarId;
  final String? colorHex;
  final double size;
  final bool showBorder;

  const DeviceAvatar({
    super.key,
    required this.avatarId,
    required this.colorHex,
    this.size = 40,
    this.showBorder = true,
  });

  @override
  Widget build(BuildContext context) {
    final color = DeviceColorPalette.parse(colorHex);
    final avatar = AvatarCatalog.find(avatarId);
    final ringWidth = (size * 0.08).clamp(2.0, 4.0);
    final innerSize = size - ringWidth * 2;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: color, width: ringWidth),
        boxShadow: showBorder
            ? const [
                BoxShadow(
                    color: Colors.black26, blurRadius: 4, offset: Offset(0, 2)),
              ]
            : null,
      ),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
        ),
        padding: EdgeInsets.all(innerSize * 0.08),
        child: SvgPicture.asset(
          avatar.asset,
          fit: BoxFit.contain,
          placeholderBuilder: (_) => Icon(
            Icons.person,
            color: Colors.grey,
            size: innerSize * 0.5,
          ),
        ),
      ),
    );
  }
}
