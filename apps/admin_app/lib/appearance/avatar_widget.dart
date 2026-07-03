import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'avatars.dart';
import 'colors.dart';

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

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: showBorder ? Border.all(color: Colors.white, width: 2) : null,
        boxShadow: showBorder
            ? const [
                BoxShadow(
                    color: Colors.black26, blurRadius: 4, offset: Offset(0, 2)),
              ]
            : null,
      ),
      padding: EdgeInsets.all(size * 0.12),
      child: SvgPicture.asset(
        avatar.asset,
        fit: BoxFit.contain,
        placeholderBuilder: (_) => Icon(
          Icons.person,
          color: Colors.white,
          size: size * 0.5,
        ),
      ),
    );
  }
}
