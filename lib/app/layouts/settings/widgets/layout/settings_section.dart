import 'package:bluebubbles/helpers/types/constants.dart';
import 'package:bluebubbles/services/services.dart';
import 'package:bluebubbles/utils/cow/glass.dart';
import 'package:bluebubbles/utils/cow/tokens.dart';
import 'package:flutter/material.dart';

class SettingsSection extends StatelessWidget {
  final List<Widget> children;
  final Color backgroundColor;

  SettingsSection({required this.children, required this.backgroundColor});

  @override
  Widget build(BuildContext context) {
    final column = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: children);

    if (ss.settings.skin.value == Skins.iOS) {
      // A glass card rather than a tinted box. GlassFill instead of Glass: the
      // settings ground is a flat surface with nothing behind it to blur, so a
      // backdrop filter per section would cost frames for an identical result.
      // The rim and sheen are what make it read as glass, and both are here.
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: Space.lg),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(GlassTokens.card),
          clipBehavior: Clip.antiAlias,
          child: GlassFill(
            radius: GlassTokens.card,
            child: column,
          ),
        ),
      );
    }

    return Padding(
      padding: ss.settings.skin.value == Skins.Samsung
          ? const EdgeInsets.symmetric(vertical: 5)
          : EdgeInsets.zero,
      child: ClipRRect(
        borderRadius:
        ss.settings.skin.value == Skins.Samsung ? BorderRadius.circular(25) : BorderRadius.circular(0),
        clipBehavior: ss.settings.skin.value != Skins.Material ? Clip.antiAlias : Clip.none,
        child: Container(
          color: backgroundColor,
          child: column,
        ),
      ),
    );
  }
}
