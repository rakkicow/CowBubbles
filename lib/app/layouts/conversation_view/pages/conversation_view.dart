import 'dart:async';
import 'package:bluebubbles/app/layouts/conversation_view/widgets/header/cupertino_header.dart';
import 'package:bluebubbles/app/layouts/conversation_view/widgets/header/material_header.dart';
import 'package:bluebubbles/app/layouts/conversation_view/widgets/text_field/conversation_text_field.dart';
import 'package:bluebubbles/app/layouts/settings/pages/profile/posterkit.dart';
import 'package:bluebubbles/app/wrappers/gradient_background_wrapper.dart';
import 'package:bluebubbles/app/wrappers/stateful_boilerplate.dart';
import 'package:bluebubbles/helpers/helpers.dart';
import 'package:bluebubbles/app/layouts/conversation_view/pages/messages_view.dart';
import 'package:bluebubbles/app/layouts/conversation_view/widgets/effects/screen_effects_widget.dart';
import 'package:bluebubbles/database/models.dart';
import 'package:bluebubbles/services/services.dart';
import 'package:bluebubbles/utils/logger/logger.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_acrylic/window_effect.dart';
import 'package:get/get.dart';
import 'package:bluebubbles/utils/cow/music_background.dart';
import 'package:bluebubbles/utils/cow/now_playing.dart';
import 'package:bluebubbles/utils/cow/tokens.dart';
import 'package:bluebubbles/utils/cow/lyric_sheet.dart';
import 'package:bluebubbles/app/layouts/conversation_view/widgets/profile_banners.dart';

class ConversationView extends StatefulWidget {
  ConversationView({
    super.key,
    required this.chat,
    this.customService,
    this.fromChatCreator = false,
    this.onInit,
  });

  final Chat chat;
  final MessagesService? customService;
  final bool fromChatCreator;
  final void Function()? onInit;

  @override
  ConversationViewState createState() => ConversationViewState();
}

class ConversationViewState extends OptimizedState<ConversationView> {
  /// lyric sheet; back closes it before the view pops
  final LyricSheetController _lyricSheet = LyricSheetController();

  late final ConversationViewController controller = cvc(chat, tag: widget.customService?.tag);

  Chat get chat => widget.chat;

  @override
  void initState() {
    super.initState();

    Logger.debug("Initializing Conversation View for ${chat.guid}");
    controller.fromChatCreator = widget.fromChatCreator;
    cm.setActiveChatSync(chat);
    cm.activeChat!.controller = controller;
    Logger.debug("Conversation View initialized for ${chat.guid}");

    if (widget.onInit != null) {
      Future.delayed(Duration.zero, widget.onInit!);
    }

    controller.loadReplyToMessageState(); // P224b
  }

  @override
  void dispose() {
    _lyricSheet.dispose();
    controller.saveReplyToMessageState(); // P8bda
    super.dispose();
  }

  /// header height, no status bar or chip
  double get _headerBase =>
      (kIsDesktop ? (!iOS ? 25 : 5) : 0) +
      90 * (iOS ? ss.settings.avatarScale.value : 0) +
      (!iOS ? kToolbarHeight : 0);

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        systemNavigationBarColor: ss.settings.immersiveMode.value
            ? Colors.transparent
            : context.theme.colorScheme.background,
        systemNavigationBarIconBrightness: context.theme.colorScheme.brightness.opposite,
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: context.theme.colorScheme.brightness.opposite,
      ),
      child: Obx(() => Theme(
        data: context.theme.copyWith(
          // in case some components still use legacy theming
          primaryColor: context.theme.colorScheme.bubble(context, chat.isIMessage),
          colorScheme: context.theme.colorScheme.copyWith(
            primary: context.theme.colorScheme.bubble(context, chat.isIMessage),
            onPrimary: context.theme.colorScheme.onBubble(context, chat.isIMessage),
            surface: ss.settings.monetTheming.value == Monet.full
                ? null
                : (context.theme.extensions[BubbleColors] as BubbleColors?)?.receivedBubbleColor,
            onSurface: ss.settings.monetTheming.value == Monet.full
                ? null
                : (context.theme.extensions[BubbleColors] as BubbleColors?)?.onReceivedBubbleColor,
            outline: controller.backgroundPoster.value != null ? Colors.white : null,
          ),
        ),
        child: PopScope(
          canPop: false,
          onPopInvoked: (didPop) async {
            if (didPop) return;
            if (_lyricSheet.isOpen) {
              _lyricSheet.close();
              return;
            }
            if (controller.inSelectMode.value) {
              controller.inSelectMode.value = false;
              controller.selected.clear();
              return;
            }
            if (controller.showAttachmentPicker) {
              controller.showAttachmentPicker = false;
              controller.updateWidgets<ConversationTextField>(null);
              return;
            }
            if (ls.isBubble) {
              SystemNavigator.pop();
            }
            controller.close();
            if (ls.isBubble) return;
            return Navigator.of(context).pop();
          },
          child: SafeArea(
            top: false,
            bottom: false,
            child: _MusicBackdrop(
              lyricSheet: _lyricSheet,
              chipBottom: _headerBase + MediaQuery.paddingOf(context).top + _chipHeight,
              builder: (context, lyricSheet) => Scaffold(
              // transparent so the artwork shows through
              backgroundColor: ss.settings.windowEffect.value != WindowEffect.disabled || cowMusic.current != null
                  ? Colors.transparent
                  : context.theme.colorScheme.background,
              extendBodyBehindAppBar: true,
              appBar: PreferredSize(
                  // chip counts toward the app bar height
                  preferredSize: Size(ns.width(context), _headerBase + (cowMusic.current != null ? _chipHeight : 0)),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // header fills the app bar, status bar included
                      SizedBox(
                        height: _headerBase + MediaQuery.paddingOf(context).top,
                        child: iOS
                            ? CupertinoHeader(controller: controller)
                            : MaterialHeader(controller: controller),
                      ),
                      if (cowMusic.current != null)
                        SizedBox(
                          height: _chipHeight,
                          child: NowPlayingChip(
                            title: cowMusic.current!.title,
                            artist: cowMusic.current!.artist,
                            art: cowMusic.current!.art,
                            waveColors: cowMusic.current!.palette.display(
                                dark: Theme.of(context).brightness == Brightness.dark),
                            playing: cowMusic.isPlaying,
                            onTap: cowMusic.playPause,
                            onNext: cowMusic.next,
                            onPrevious: cowMusic.previous,
                            onHoldStart: lyricSheet.hold,
                            onHoldMove: lyricSheet.holdMove,
                            onHoldEnd: lyricSheet.release,
                          ),
                        ),
                    ],
                  )),
              body: Actions(
                actions: {
                  if (ss.settings.enablePrivateAPI.value)
                    ReplyRecentIntent: ReplyRecentAction(widget.chat),
                  if (ss.settings.enablePrivateAPI.value)
                    HeartRecentIntent: HeartRecentAction(widget.chat),
                  if (ss.settings.enablePrivateAPI.value)
                    LikeRecentIntent: LikeRecentAction(widget.chat),
                  if (ss.settings.enablePrivateAPI.value)
                    DislikeRecentIntent: DislikeRecentAction(widget.chat),
                  if (ss.settings.enablePrivateAPI.value)
                    LaughRecentIntent: LaughRecentAction(widget.chat),
                  if (ss.settings.enablePrivateAPI.value)
                    EmphasizeRecentIntent: EmphasizeRecentAction(widget.chat),
                  if (ss.settings.enablePrivateAPI.value)
                    QuestionRecentIntent: QuestionRecentAction(widget.chat),
                  OpenChatDetailsIntent: OpenChatDetailsAction(context, widget.chat),
                },
                child: GradientBackground(
                  controller: controller,
                  child: SizedBox(
                    height: context.height,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        if (controller.backgroundPoster.value != null)
                        ImagePoster(poster: controller.backgroundPoster.value!.poster, images: controller.images),
                        const Positioned.fill(child: ScreenEffectsWidget()),
                        Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Expanded(
                              child: Stack(
                                children: [
                                  MessagesView(
                                    key: Key(chat.guid),
                                    customService: widget.customService,
                                    controller: controller,
                                  ),
                                  Align(
                                    alignment: iOS ? Alignment.bottomRight : Alignment.bottomCenter,
                                    child: Padding(
                                      padding: const EdgeInsets.only(bottom: 10, right: 10, left: 10),
                                      child: Obx(() => IgnorePointer(
                                        ignoring: controller.showScrollDown.value ? false : true,
                                        child: AnimatedOpacity(
                                          opacity: controller.showScrollDown.value ? 1 : 0,
                                          duration: const Duration(milliseconds: 300),
                                          child: iOS ? TextButton(
                                            style: TextButton.styleFrom(
                                              backgroundColor: context.theme.colorScheme.secondary,
                                              shape: const CircleBorder(),
                                              padding: const EdgeInsets.all(0),
                                              maximumSize: const Size(32, 32),
                                              minimumSize: const Size(32, 32),
                                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                            ),
                                            onPressed: controller.scrollToBottom,
                                            child: Container(
                                              constraints: const BoxConstraints(minHeight: 32, minWidth: 32),
                                              decoration: const BoxDecoration(
                                                shape: BoxShape.circle,
                                              ),
                                              padding: const EdgeInsets.only(top: 3, left: 1),
                                              alignment: Alignment.center,
                                              child: Icon(
                                                CupertinoIcons.chevron_down,
                                                color: context.theme.colorScheme.onSecondary,
                                                size: 20,
                                              ),
                                            ),
                                          ) : FloatingActionButton.small(
                                            heroTag: null,
                                            onPressed: controller.scrollToBottom,
                                            child: Icon(
                                              Icons.arrow_downward,
                                              color: context.theme.colorScheme.onSecondary,
                                            ),
                                            backgroundColor: context.theme.colorScheme.secondary,
                                          ),
                                        ),
                                      )),
                                    )
                                  )
                                ],
                              ),
                            ),
                            ProfileBanners(controller: controller),
                            Stack(
                              children: [
                                Align(
                                  alignment: Alignment.bottomCenter,
                                  child: GestureDetector(
                                    onPanUpdate: (details) {
                                      if (!mounted) return;
                                      if (ss.settings.swipeToCloseKeyboard.value &&
                                          details.delta.dy > 0 &&
                                          controller.keyboardOpen) {
                                        controller.focusNode.unfocus();
                                        controller.subjectFocusNode.unfocus();
                                      } else if (ss.settings.swipeToOpenKeyboard.value &&
                                          details.delta.dy < 0 &&
                                          !controller.keyboardOpen) {
                                        controller.focusNode.requestFocus();
                                      }
                                    },
                                    child: ConversationTextField(
                                      parentController: controller,
                                    ),
                                  ),
                                )
                              ]
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ))),
          ),
        )
      ),
    );
  }
}


/// now-playing chip height
const double _chipHeight = 56;

/// paints the song's artwork behind the conversation
class _MusicBackdrop extends StatefulWidget {
  /// built inside the listener
  final Widget Function(BuildContext context, LyricSheetController lyricSheet) builder;

  final LyricSheetController lyricSheet;

  /// where the chip ends
  final double chipBottom;

  const _MusicBackdrop({required this.builder, required this.lyricSheet, required this.chipBottom});

  @override
  State<_MusicBackdrop> createState() => _MusicBackdropState();
}

class _MusicBackdropState extends State<_MusicBackdrop> {
  /// last track; held while the sheet closes
  NowPlaying? _shown;
  Timer? _clear;

  @override
  void dispose() {
    _clear?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: cowMusic,
      builder: (context, _) {
        final np = cowMusic.current;
        if (np != null) {
          _shown = np;
          _clear?.cancel();
          _clear = null;
        } else if (_shown != null && _clear == null) {
          // song ended under an open sheet
          if (widget.lyricSheet.isOpen) {
            WidgetsBinding.instance.addPostFrameCallback((_) => widget.lyricSheet.close());
          }
          _clear = Timer(Motion.slow + Motion.base, () {
            if (mounted) setState(() => _shown = null);
          });
        }
        final shown = _shown;
        final child = widget.builder(context, widget.lyricSheet);
        // sheet always last, conversation always inside
        return Stack(
          fit: StackFit.expand,
          children: [
            if (shown != null) MusicBackground(palette: shown.palette, art: shown.blurSource),
            // own layer
            LyricSheet(
              controller: widget.lyricSheet,
              track: shown,
              playing: cowMusic.isPlaying,
              peekTop: widget.chipBottom,
              child: RepaintBoundary(child: child),
            ),
          ],
        );
      },
    );
  }
}
