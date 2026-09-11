import 'package:bluebubbles/helpers/types/constants.dart';
import 'package:bluebubbles/helpers/ui/theme_helpers.dart';
import 'package:bluebubbles/services/services.dart';
import 'package:bluebubbles/utils/cow/tokens.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class SettingsSubtitle extends StatelessWidget {
  const SettingsSubtitle({
    super.key,
    this.subtitle,
    this.unlimitedSpace = false,
    this.bottomPadding = true,
  });

  final String? subtitle;
  final bool unlimitedSpace;
  final bool bottomPadding;

  @override
  Widget build(BuildContext context) {
    final iOS = ss.settings.skin.value == Skins.iOS;
    return Padding(
      padding: !bottomPadding ? EdgeInsets.zero : const EdgeInsets.only(bottom: Space.sm),
      child: ListTile(
        title: subtitle != null ? Text(
          subtitle!,
          style: iOS
              ? CowType.secondary(context)
              : context.theme.textTheme.bodySmall!.copyWith(color: context.theme.colorScheme.properOnSurface.withOpacity(0.75)),
          maxLines: unlimitedSpace ? 100 : 2,
          overflow: TextOverflow.ellipsis,
        ) : null,
        minVerticalPadding: 0,
        visualDensity: const VisualDensity(horizontal: 0, vertical: -4),
        dense: true,
      ),
    );
  }
}
