import 'package:bluebubbles/helpers/helpers.dart';
import 'package:bluebubbles/services/services.dart';
import 'package:bluebubbles/utils/cow/tokens.dart';
import 'package:flutter/material.dart';

class SettingsHeader extends StatelessWidget {
  final TextStyle? iosSubtitle;
  final TextStyle? materialSubtitle;
  final String text;

  SettingsHeader({
    required this.iosSubtitle,
    required this.materialSubtitle,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    if (ss.settings.skin.value == Skins.Samsung) return const SizedBox(height: 15);
    final iOS = ss.settings.skin.value == Skins.iOS;
    // A section title, not a caption: on iOS the glass cards below carry
    // enough presence that a small grey label above them reads as an
    // afterthought. Sentence case - the old psCapitalize is kept for Material.
    return Container(
      height: iOS ? 56 : 40,
      alignment: Alignment.bottomLeft,
      color: Colors.transparent,
      child: Padding(
        padding: EdgeInsets.only(bottom: iOS ? Space.sm : 8.0, left: iOS ? Space.xl : 15),
        child: Text(
          iOS ? text : text.psCapitalize,
          style: iOS ? CowType.title(context) : materialSubtitle,
        ),
      ),
    );
  }
}
