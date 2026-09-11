import 'dart:ui';

import 'package:bluebubbles/helpers/helpers.dart';
import 'package:bluebubbles/app/layouts/conversation_list/pages/conversation_list.dart';
import 'package:bluebubbles/app/layouts/conversation_list/widgets/header/header_widgets.dart';
import 'package:bluebubbles/app/layouts/conversation_list/pages/search/search_view.dart';
import 'package:bluebubbles/app/wrappers/fade_on_scroll.dart';
import 'package:bluebubbles/services/services.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:bluebubbles/utils/cow/glass.dart';
import 'package:bluebubbles/utils/cow/tokens.dart';

/// round glass header button, no backdrop blur
class _HeaderGlassButton extends StatelessWidget {
  const _HeaderGlassButton({
    required this.icon,
    required this.onTap,
    required this.label,
    this.focusNode,
    this.size = 20,
  });

  final IconData icon;
  final VoidCallback onTap;
  final String label;
  final FocusNode? focusNode;
  final double size;

  @override
  Widget build(BuildContext context) {
    final button = PressScale(
      onTap: onTap,
      scale: 0.9,
      semanticLabel: label,
      child: GlassFill(
        radius: GlassTokens.capsule,
        child: SizedBox(
          width: 36,
          height: 36,
          child: Icon(icon, color: context.theme.colorScheme.onSurface, size: size),
        ),
      ),
    );
    return focusNode == null ? button : Focus(focusNode: focusNode, child: button);
  }
}

class CupertinoHeader extends StatelessWidget {
  const CupertinoHeader({Key? key, required this.controller});

  final ConversationListController controller;

  static double topMarginFor(BuildContext context) =>
      context.orientation == Orientation.landscape && context.isPhone
          ? 20
          : kIsDesktop || kIsWeb
              ? 40
              : kToolbarHeight + 30;

  /// what the list has to clear: margin, panel, bottom gap
  static double heightFor(BuildContext context) => topMarginFor(context) + 68 + 5;

  @override
  Widget build(BuildContext context) {
    final double topMargin = topMarginFor(context);

    return RepaintBoundary(
      child: Container(
          margin: EdgeInsets.only(
            top: topMargin,
            left: Space.md,
            right: Space.md,
            bottom: 5,
          ),
          // glass panel
          child: Glass(
            radius: GlassTokens.panel,
            padding: const EdgeInsets.fromLTRB(Space.lg, Space.md, Space.md, Space.md),
            child: Obx(() {
            ns.listener.value;
            return Row(
              mainAxisAlignment: ns.isAvatarOnly(context) ? MainAxisAlignment.center : MainAxisAlignment.spaceBetween,
              children: <Widget>[
                if (!ns.isAvatarOnly(context))
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(right: 10.0),
                      child: Text(
                        controller.showArchivedChats
                            ? "Archive"
                            : controller.showUnknownSenders
                                ? "Unknown Senders"
                                : controller.showDeletedMessages
                                    ? "Recently Deleted"
                                    : "CowMessages",
                        style: CowType.display(context).copyWith(fontSize: 30),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                if (ns.isAvatarOnly(context))
                  Material(
                    color: Colors.transparent,
                    shape: const CircleBorder(),
                    clipBehavior: Clip.antiAlias,
                    child: OverflowMenu(extraItems: true, controller: controller),
                  ),
                if (!ns.isAvatarOnly(context))
                  Row(
                    mainAxisSize: MainAxisSize.max,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      SyncIndicator(size: 16),
                      const SizedBox(width: 10.0),
                      _HeaderGlassButton(
                        icon: CupertinoIcons.search,
                        size: 18,
                        label: "Search",
                        onTap: () {
                          ns.pushLeft(context, SearchView());
                        },
                      ),
                      const SizedBox(width: 10.0),
                      if (ss.settings.moveChatCreatorToHeader.value)
                        CallbackShortcuts(
                          bindings: {
                            const SingleActivator(LogicalKeyboardKey.arrowLeft): () {
                              if (!FocusScope.of(context).focusInDirection(TraversalDirection.left)) {
                                FocusScope.of(context).previousFocus();
                              }
                            },
                            const SingleActivator(LogicalKeyboardKey.enter): () => controller.openNewChatCreator(context),
                            const SingleActivator(LogicalKeyboardKey.select): () => controller.openNewChatCreator(context),
                            const SingleActivator(LogicalKeyboardKey.space): () => controller.openNewChatCreator(context),
                          },
                          child: _HeaderGlassButton(
                            icon: CupertinoIcons.pencil,
                            label: "New message",
                            focusNode: controller.newMessageFocusNode,
                            onTap: () => controller.openNewChatCreator(context),
                          ),
                        ),
                      if (ss.settings.moveChatCreatorToHeader.value && ss.settings.cameraFAB.value && !kIsWeb && !kIsDesktop)
                        const SizedBox(width: 10.0),
                      if (ss.settings.moveChatCreatorToHeader.value && ss.settings.cameraFAB.value && !kIsWeb && !kIsDesktop)
                        _HeaderGlassButton(
                          icon: CupertinoIcons.camera,
                          label: "Open camera",
                          onTap: () => controller.openCamera(context),
                        ),
                      if (ss.settings.moveChatCreatorToHeader.value) const SizedBox(width: 10.0),
                      const Material(
                        color: Colors.transparent,
                        shape: CircleBorder(),
                        clipBehavior: Clip.antiAlias,
                        child: OverflowMenu(),
                      ),
                    ],
                  ),
              ],
            );
          }),
          ),
        ),
    );
  }
}

class CupertinoMiniHeader extends StatelessWidget {
  const CupertinoMiniHeader({Key? key, required this.controller});

  final ConversationListController controller;

  @override
  Widget build(BuildContext context) {
    final double topMargin = context.orientation == Orientation.landscape && context.isPhone
        ? 20
        : kIsDesktop || kIsWeb
            ? 60
            : kToolbarHeight + 30;

    return IgnorePointer(
      child: FadeOnScroll(
        scrollController: controller.iosScrollController,
        fullOpacityOffset: topMargin + 15,
        child: ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
            child: Obx(() {
              ns.listener.value;
              return GlassFill(
                radius: 0,
                child: Container(
                  width: ns.width(context),
                  height: (topMargin - 20).clamp(kIsDesktop ? 65 : 40, double.infinity),
                  alignment: Alignment.bottomCenter,
                  child: Padding(
                    padding: EdgeInsets.only(bottom: kIsDesktop ? 10 : 5),
                    child: Text(
                      controller.showArchivedChats
                          ? "Archive"
                          : controller.showUnknownSenders
                          ? "Unknown Senders"
                          : "CowMessages",
                      style: CowType.title(context),
                    ),
                  ),
                ),
              );
            })
          ),
        ),
      ),
    );
  }
}
