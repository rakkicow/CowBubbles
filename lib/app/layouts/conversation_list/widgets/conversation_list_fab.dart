import 'package:bluebubbles/app/layouts/conversation_list/pages/conversation_list.dart';
import 'package:bluebubbles/app/wrappers/stateful_boilerplate.dart';
import 'package:bluebubbles/app/wrappers/theme_switcher.dart';
import 'package:bluebubbles/helpers/helpers.dart';
import 'package:bluebubbles/services/services.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:bluebubbles/utils/cow/glass.dart';
import 'package:bluebubbles/utils/cow/tokens.dart';

class ConversationListFAB extends CustomStateful<ConversationListController> {
  const ConversationListFAB({Key? key, required super.parentController});

  @override
  State<StatefulWidget> createState() => _ConversationListFABState();
}

class _ConversationListFABState extends CustomState<ConversationListFAB, void, ConversationListController> {
  void _focusBackToList() {
    if (!FocusScope.of(context).focusInDirection(TraversalDirection.left)) {
      FocusScope.of(context).previousFocus();
    }
  }

  Map<ShortcutActivator, VoidCallback> get _newMessageShortcuts => {
    const SingleActivator(LogicalKeyboardKey.arrowLeft): _focusBackToList,
    const SingleActivator(LogicalKeyboardKey.enter): () => controller.openNewChatCreator(context),
    const SingleActivator(LogicalKeyboardKey.select): () => controller.openNewChatCreator(context),
    const SingleActivator(LogicalKeyboardKey.space): () => controller.openNewChatCreator(context),
  };

  @override
  void initState() {
    super.initState();

    controller.materialScrollController.addListener(() {
      if (!material) return;
      if (controller.materialScrollStartPosition - controller.materialScrollController.offset < -75
          && controller.materialScrollController.position.userScrollDirection == ScrollDirection.reverse
          && controller.showMaterialFABText) {
        setState(() {
          controller.showMaterialFABText = false;
        });
      } else if (controller.materialScrollStartPosition - controller.materialScrollController.offset > 75
          && controller.materialScrollController.position.userScrollDirection == ScrollDirection.forward
          && !controller.showMaterialFABText) {
        setState(() {
          controller.showMaterialFABText = true;
        });
      }
    });
    ns.listener.stream.listen((event) {
      if (!mounted) return;
      if (ns.isAvatarOnly(context) && controller.showMaterialFABText) {
        setState(() {
          controller.showMaterialFABText = false;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final widget = Obx(() => Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        if (ss.settings.cameraFAB.value && iOS && !kIsWeb && !kIsDesktop)
          PressScale(
            onTap: () => controller.openCamera(context),
            scale: 0.92,
            semanticLabel: "Open camera",
            child: GlassFill(
              radius: GlassTokens.capsule,
              padding: const EdgeInsets.all(12),
              child: Icon(
                CupertinoIcons.camera,
                size: 20,
                color: context.theme.colorScheme.onSurface,
              ),
            ),
          ),
        if (ss.settings.cameraFAB.value && iOS && !kIsWeb && !kIsDesktop)
          const SizedBox(
            height: 10,
          ),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            if (chats.chats.isEmpty && chats.loadedChatBatch.value)
            Text("Start a Chat >", style: context.textTheme.labelLarge?.copyWith(color: Colors.white)),
            if (chats.chats.isEmpty)
            const SizedBox(width: 16),
            CallbackShortcuts(
              bindings: _newMessageShortcuts,
              child: Focus(
                focusNode: controller.newMessageFocusNode,
                child: PressScale(
                  onTap: () => controller.openNewChatCreator(context),
                  onLongPress: iOS || !ss.settings.cameraFAB.value || kIsWeb || kIsDesktop
                      ? null : () => controller.openCamera(context),
                  scale: 0.92,
                  semanticLabel: "New message",
                  // A capsule with a label rather than a round button: on a
                  // glass surface the word is what makes the control legible,
                  // the icon alone reads as decoration.
                  child: GlassFill(
                    radius: GlassTokens.capsule,
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          iOS ? CupertinoIcons.pencil : Icons.message,
                          color: context.theme.colorScheme.onSurface,
                          size: 20,
                        ),
                        const SizedBox(width: Space.sm),
                        Text(
                          "New",
                          style: CowType.name(context).copyWith(fontSize: 15),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        )
      ],
    ));

    return ThemeSwitcher(
      iOSSkin: widget,
      materialSkin: AnimatedCrossFade(
        crossFadeState: controller.selectedChats.isEmpty
            ? CrossFadeState.showFirst : CrossFadeState.showSecond,
        alignment: Alignment.center,
        duration: const Duration(milliseconds: 300),
        secondChild: const SizedBox.shrink(),
        firstChild: SizedBox(
          width: ns.width(context),
          height: 125,
          child: Stack(
            alignment: Alignment.bottomCenter,
            clipBehavior: Clip.none,
            children: [
              AnimatedOpacity(
                opacity: !controller.showMaterialFABText ? 1 : 0,
                duration: const Duration(milliseconds: 300),
                child: FloatingActionButton.small(
                  heroTag: null,
                  onPressed: () async {
                    await controller.materialScrollController.animateTo(0, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
                    setState(() {
                      controller.showMaterialFABText = true;
                    });
                  },
                  child: Icon(
                    Icons.arrow_upward,
                    color: context.theme.colorScheme.onSecondary,
                  ),
                  backgroundColor: context.theme.colorScheme.secondary,
                ),
              ),
              Positioned(
                right: material ? 15 : 0,
                child: InkWell(
                  onLongPress: ss.settings.cameraFAB.value && !kIsWeb && !kIsDesktop
                      ? () => controller.openCamera(context) : null,
                  child: Container(
                    height: 65,
                    padding: const EdgeInsets.only(right: 4.5, bottom: 9),
                    child: CallbackShortcuts(
                      bindings: _newMessageShortcuts,
                      child: FloatingActionButton(
                        focusNode: controller.newMessageFocusNode,
                        backgroundColor: context.theme.colorScheme.primaryContainer,
                        shape: const CircleBorder(),
                        child: Padding(
                          padding: const EdgeInsets.only(left: 5.0, right: 5.0, top: 2),
                          child: Icon(
                            CupertinoIcons.bubble_left,
                            color: context.theme.colorScheme.onPrimaryContainer,
                            size: 24,
                          ),
                        ),
                        onPressed: () => controller.openNewChatCreator(context),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      samsungSkin: widget,
    );
  }
}
