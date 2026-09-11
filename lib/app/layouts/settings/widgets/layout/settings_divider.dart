import 'package:bluebubbles/helpers/types/constants.dart';
import 'package:bluebubbles/services/services.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class SettingsDivider extends StatelessWidget {
  final double thickness;
  final Color? color;
  final EdgeInsets padding;

  const SettingsDivider({
    this.thickness = 1,
    this.color,
    this.padding = const EdgeInsets.only(left: 66.0),
  });

  @override
  Widget build(BuildContext context) {
    if (ss.settings.skin.value == Skins.iOS) {
      // Inside a glass card the separator is a faint light line, the way an
      // etched edge catches light - the theme outline colour is too heavy
      // here and reads as a border between unrelated boxes.
      final dark = context.theme.brightness == Brightness.dark;
      return Padding(
        padding: padding,
        child: Divider(
          color: color ??
              (dark ? Colors.white.withOpacity(0.10) : Colors.black.withOpacity(0.08)),
          thickness: 0.5,
          height: 0.5,
        )
      );
    } else {
      return const SizedBox.shrink();
    }
  }
}
