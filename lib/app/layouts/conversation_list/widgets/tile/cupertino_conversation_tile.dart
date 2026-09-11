import 'dart:async';

import 'package:bluebubbles/helpers/helpers.dart';
import 'package:bluebubbles/app/layouts/conversation_list/dialogs/conversation_peek_view.dart';
import 'package:bluebubbles/app/layouts/conversation_list/widgets/tile/conversation_tile.dart';
import 'package:bluebubbles/app/wrappers/stateful_boilerplate.dart';
import 'package:bluebubbles/database/database.dart';
import 'package:bluebubbles/database/models.dart';
import 'package:bluebubbles/services/services.dart';
import 'package:bluebubbles/utils/cow/glass.dart';
import 'package:bluebubbles/utils/cow/signature.dart';
import 'package:bluebubbles/utils/cow/tokens.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class CupertinoConversationTile extends CustomStateful<ConversationTileController> {
  CupertinoConversationTile({Key? key, required super.parentController, required this.deletedMode});

  bool deletedMode;

  @override
  State<StatefulWidget> createState() => _CupertinoConversationTileState();
}

class _CupertinoConversationTileState extends CustomState<CupertinoConversationTile, void, ConversationTileController> {
  Offset? longPressPosition;

  @override
  void initState() {
    super.initState();
    tag = controller.chat.guid;
    // keep controller in memory since the widget is part of a list
    // (it will be disposed when scrolled out of view)
    forceDelete = false;
  }

  /// chat colour; groups key on guid, 1:1 on handle
  Signature _signature(BuildContext context) => Signature.forHandle(
        controller.chat.participants.length == 1
            ? controller.chat.participants.first.address
            : controller.chat.guid,
        context.theme.brightness,
      );

  @override
  Widget build(BuildContext context) {
    final sig = _signature(context);
    return Obx(() {
      ns.listener.value;
      // unread fills, read stays flat; interaction wins
      final unread = GlobalChatService.unreadState(controller.chat.guid).value;
      final interactive = controller.shouldHighlight.value ||
          controller.shouldPartialHighlight.value ||
          controller.hoverHighlight.value;
      final filled = unread && !interactive && !widget.deletedMode;
      // theme text colours assume a flat surface
      final Color? onFill = filled ? sig.onBase : null;
      return _buildTile(context, sig, filled, interactive, onFill);
    });
  }

  Widget _buildTile(BuildContext context, Signature sig, bool filled, bool interactive, Color? onFill) {
    final leading = ChatLeading(
      controller: controller,
      unreadIcon: UnreadIcon(parentController: controller, onFill: onFill),
    );
    final child = Material(
      color: Colors.transparent,
      child: InkWell(
        mouseCursor: MouseCursor.defer,
        onTap: () => controller.onTap(context, widget.deletedMode),
        onSecondaryTapUp: widget.deletedMode ? null : (details) => controller.onSecondaryTap(Get.context!, details),
        onLongPress: kIsDesktop || kIsWeb || widget.deletedMode
            ? null
            : () async {
                await peekChat(context, controller.chat, longPressPosition ?? Offset.zero);
              },
        onTapDown: (details) {
          longPressPosition = details.globalPosition;
        },
        child: Obx(() => ListTile(
            mouseCursor: MouseCursor.defer,
            enableFeedback: true,
            dense: ss.settings.denseChatTiles.value,
            contentPadding: const EdgeInsets.only(left: 0),
            visualDensity: ss.settings.denseChatTiles.value ? VisualDensity.compact : null,
            minVerticalPadding: ss.settings.denseChatTiles.value ? 7.5 : 10,
            horizontalTitleGap: 10,
            title: Row(
              children: [
                Expanded(
                  child: ChatTitle(
                    parentController: controller,
                    style: context.theme.textTheme.bodyLarge!.copyWith(
                        fontSize: context.theme.textTheme.bodyLarge!.fontSize! * 1.12,
                        fontWeight: filled || controller.shouldHighlight.value ? FontWeight.w600 : FontWeight.w500,
                        color: onFill ?? (controller.shouldHighlight.value ? context.theme.colorScheme.onBubble(context, controller.chat.isIMessage) : null)),
                  ),
                ),
                const SizedBox(width: 10,),
                if (!widget.deletedMode)
                CupertinoTrailing(parentController: controller, onFill: onFill),
                if (widget.deletedMode)
                Builder(builder: (context) {
                  DateTime oldestDeletion = DateTime.now();
                  for (var message in controller.chat.messages) {
                    if (message.dateDeleted == null) continue;
                    // we are less than the oldest
                    if (message.dateDeleted!.compareTo(oldestDeletion) < 0) {
                      oldestDeletion = message.dateDeleted!;
                    }
                  }

                  var deleteDate = oldestDeletion.add(const Duration(days: 30));
                  var diff = deleteDate.difference(DateTime.now());
                  String d;
                  if (diff.isNegative) {
                    d = "Pending Deletion";
                  } else if (diff.inDays != 0) {
                    d = "${diff.inDays}d";
                  } else if (diff.inHours != 0) {
                    d = "${diff.inHours}h";
                  } else {
                    d = "${diff.inMinutes}m";
                  }


                  var bodyStyle = context.theme.textTheme.bodySmall!
                      .copyWith(
                        color: controller.shouldHighlight.value
                                ? context.theme.colorScheme.onBubble(context, controller.chat.isIMessage)
                                : context.theme.colorScheme.outline,
                        fontWeight: controller.shouldHighlight.value ? FontWeight.w500 : null,
                      )
                      .apply(fontSizeFactor: 1.1);
                  return Padding(padding: const EdgeInsets.only(right: 8), child: Text(d, style: bodyStyle));
                }),
              ],
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(right: 20.0),
              child: widget.deletedMode ? Builder(builder: (context) {
                var count = controller.chat.messages.where((i) => i.dateDeleted != null).length;
                return Text("$count message${count == 1 ? '' : 's'}");
              }) : controller.subtitle ??
                  ChatSubtitle(
                    parentController: controller,
                    style: context.theme.textTheme.bodyMedium!.copyWith(
                      color: onFill?.withOpacity(0.82) ??
                          (controller.shouldHighlight.value
                              ? context.theme.colorScheme.onBubble(context, controller.chat.isIMessage).withOpacity(0.85)
                              : context.theme.colorScheme.outline),
                      height: 1.5,
                    ),
                  ),
            ),
            leading: leading)),
      ),
    );

    final tileChild = ns.isAvatarOnly(context)
        ? InkWell(
            mouseCursor: MouseCursor.defer,
            onTap: () => controller.onTap(context, widget.deletedMode),
            onSecondaryTapUp: (details) => controller.onSecondaryTap(Get.context!, details),
            onLongPress: kIsDesktop || kIsWeb
                ? null
                : () async {
                    await peekChat(context, controller.chat, longPressPosition ?? Offset.zero);
                  },
            onTapDown: (details) {
              longPressPosition = details.globalPosition;
            },
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 10.0, horizontal: (ns.width(context) - 100) / 2).add(const EdgeInsets.only(right: 15)),
              child: leading,
            ),
          )
        : child;

    return AnimatedContainer(
      duration: Motion.quick,
      curve: Motion.enter,
      margin: filled
          ? const EdgeInsets.symmetric(horizontal: Space.sm, vertical: 2)
          : EdgeInsets.zero,
      decoration: BoxDecoration(
        color: controller.shouldPartialHighlight.value
            ? context.theme.colorScheme.properSurface.lightenOrDarken(10)
            : controller.shouldHighlight.value
                ? context.theme.colorScheme.bubble(context, controller.chat.isIMessage)
                : controller.hoverHighlight.value
                    ? context.theme.colorScheme.properSurface.withOpacity(0.5)
                    : null,
        gradient: filled
            ? LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: sig.gradient,
              )
            : null,
        borderRadius: BorderRadius.circular(
            interactive ? 8 : (filled ? GlassTokens.card : 0)),
      ),
      // tinted glass, no backdrop filter - one per row
      child: filled
          ? GlassFill(
              radius: GlassTokens.card,
              fillAlpha: 0,
              child: tileChild,
            )
          : tileChild,
    );
  }
}

class CupertinoTrailing extends CustomStateful<ConversationTileController> {
  const CupertinoTrailing({Key? key, required super.parentController, this.onFill});

  /// set when the tile behind is filled
  final Color? onFill;

  @override
  State<StatefulWidget> createState() => _CupertinoTrailingState();
}

class _CupertinoTrailingState extends CustomState<CupertinoTrailing, void, ConversationTileController> {
  DateTime? dateCreated;
  late final StreamSubscription sub;
  String? cachedLatestMessageGuid = "";
  Message? cachedLatestMessage;

  @override
  void initState() {
    super.initState();
    tag = controller.chat.guid;
    // keep controller in memory since the widget is part of a list
    // (it will be disposed when scrolled out of view)
    forceDelete = false;
    cachedLatestMessage = controller.chat.latestMessage;
    cachedLatestMessageGuid = cachedLatestMessage?.guid;
    dateCreated = cachedLatestMessage?.dateCreated;
    // run query after render has completed
    if (!kIsWeb) {
      updateObx(() {
        final latestMessageQuery = (Database.messages.query(Message_.dateDeleted.isNull())
              ..link(Message_.chat, Chat_.guid.equals(controller.chat.guid))
              ..order(Message_.dateCreated, flags: Order.descending))
            .watch();

        sub = latestMessageQuery.listen((Query<Message> query) async {
          final message = await runAsync(() {
            return query.findFirst();
          });
          if (message != null &&
              ss.settings.statusIndicatorsOnChats.value &&
              (message.dateDelivered != cachedLatestMessage?.dateDelivered || message.dateRead != cachedLatestMessage?.dateRead)) {
            setState(() {});
          }
          cachedLatestMessage = message;
          // check if we really need to update this widget
          if (message != null && message.guid != cachedLatestMessageGuid) {
            if (dateCreated != message.dateCreated) {
              setState(() {
                dateCreated = message.dateCreated;
              });
            }
          }
          cachedLatestMessageGuid = message?.guid;
        });
      });
    } else {
      sub = WebListeners.newMessage.listen((tuple) {
        if (tuple.item2?.guid == controller.chat.guid && (dateCreated == null || tuple.item1.dateCreated!.isAfter(dateCreated!))) {
          cachedLatestMessage = tuple.item1;
          setState(() {
            dateCreated = tuple.item1.dateCreated;
          });
          cachedLatestMessageGuid = tuple.item1.guid;
        }
      });
    }
  }

  @override
  void dispose() {
    sub.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // follow the fill
    final Color quiet = widget.onFill?.withOpacity(0.78) ??
        (controller.shouldHighlight.value
            ? context.theme.colorScheme.onBubble(context, controller.chat.isIMessage)
            : context.theme.colorScheme.outline);

    return Padding(
      padding: const EdgeInsets.only(right: 15),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Obx(() {
            String indicatorText = "";
            if (ss.settings.statusIndicatorsOnChats.value && (cachedLatestMessage?.isFromMe ?? false) && !controller.chat.isGroup) {
              Indicator show = cachedLatestMessage?.indicatorToShow ?? Indicator.NONE;
              if (show != Indicator.NONE) {
                indicatorText = show.name.toLowerCase().capitalizeFirst!;
              }
            }

            return Text(
              (cachedLatestMessage?.error ?? 0) > 0
                  ? "Error"
                  // fix layout
                  : "${indicatorText.isNotEmpty && indicatorText != "None" ? "$indicatorText " : ""}${buildDate(cachedLatestMessage?.chatViewDate)}",
              textAlign: TextAlign.right,
              style: context.theme.textTheme.bodySmall!
                  .copyWith(
                    color: (cachedLatestMessage?.error ?? 0) > 0
                        ? context.theme.colorScheme.error
                        : quiet,
                    fontWeight: widget.onFill != null || controller.shouldHighlight.value ? FontWeight.w500 : null,
                  )
                  .apply(fontSizeFactor: 1.1),
              overflow: TextOverflow.clip,
            );
          }),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                CupertinoIcons.forward,
                color: quiet,
                size: 15,
              ),
              if (controller.chat.muteType == "mute")
                Padding(
                    padding: const EdgeInsets.only(top: 5.0),
                    child: Icon(
                      CupertinoIcons.bell_slash_fill,
                      color: quiet,
                      size: 12,
                    ))
            ],
          ),
        ],
      ),
    );
  }
}

class UnreadIcon extends CustomStateful<ConversationTileController> {
  const UnreadIcon({Key? key, required super.parentController, this.onFill});

  /// quiet dot on a filled tile
  final Color? onFill;

  @override
  State<StatefulWidget> createState() => _UnreadIconState();
}

class _UnreadIconState extends CustomState<UnreadIcon, void, ConversationTileController> {

  @override
  void initState() {
    super.initState();
    tag = controller.chat.guid;
    // keep controller in memory since the widget is part of a list
    // (it will be disposed when scrolled out of view)
    forceDelete = false;
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 5.0, right: 5.0),
      child: Obx(() => GlobalChatService.unreadState(controller.chat.guid).value
          ? Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(35),
                color: widget.onFill ?? context.theme.colorScheme.primary,
              ),
              width: 10,
              height: 10,
            )
          : const SizedBox(width: 10),
      )
    );
  }
}
