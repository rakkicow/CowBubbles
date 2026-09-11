import 'dart:convert';

import 'package:bluebubbles/app/components/avatars/contact_avatar_widget.dart';
import 'package:bluebubbles/database/models.dart';
import 'package:bluebubbles/helpers/helpers.dart';
import 'package:bluebubbles/services/network/backend_service.dart';
import 'package:bluebubbles/services/rustpush/rustpush_service.dart';
import 'package:bluebubbles/services/services.dart';
import 'package:bluebubbles/src/rust/api/api.dart' as api;
import 'package:bluebubbles/utils/cow/glass.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:universal_io/io.dart';

/// profile prompts, as a card above the composer
class ProfileBanners extends StatelessWidget {
  final ConversationViewController controller;
  const ProfileBanners({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final suggested = controller.suggestedContact.value;
      if (suggested != null) {
        return _card(_SuggestedContact(controller: controller, contact: suggested));
      }
      if (controller.suggestShare.value) {
        return _card(_ShareProfile(controller: controller));
      }
      return const SizedBox.shrink();
    });
  }

  Widget _card(Widget child) => Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
        child: GlassFill(
          radius: GlassTokens.card,
          padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
          child: child,
        ),
      );
}

class _SuggestedContact extends StatelessWidget {
  final ConversationViewController controller;
  final Contact contact;
  const _SuggestedContact({required this.controller, required this.contact});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (contact.avatar != null)
          ContactAvatarWidget(
            contact: contact,
            size: 38,
            preferHighResAvatar: true,
            scaleSize: false,
          ),
        if (contact.avatar != null) const SizedBox(width: 15),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("New Contact Info", style: context.theme.textTheme.titleMedium),
              Text(
                contact.displayName.replaceFirst("Maybe: ", ""),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.theme.textTheme.bodyMedium?.copyWith(color: context.theme.colorScheme.outline),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: context.theme.colorScheme.outline.withAlpha(64),
            padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 13),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            elevation: 0.0,
            minimumSize: Size.zero,
          ),
          onPressed: () async {
            var contact = controller.suggestedContact.value!;
            var existingParticipant = Handle.findOne(id: controller.chat.participants.first.id)!; // so contact field updates
            if (Platform.isAndroid) {
              var parameters = {'address': existingParticipant.address, 'address_type': existingParticipant.address.isEmail ? 'email' : 'phone'};
              parameters["name"] = contact.displayName.replaceFirst("Maybe: ", "");
              if (contact.avatar != null) parameters["image"] = base64Encode(contact.avatar!);
              if (!(existingParticipant.contact?.isShared ?? true)) {
                parameters["existing"] = existingParticipant.contact!.id;

                // contact syncing takes forever...
                var update = existingParticipant.contact!;
                update.displayName = contact.displayName.replaceFirst("Maybe: ", "");
                update.structuredName = contact.structuredName;
                update.avatar = contact.avatar;
                if (contact.id == update.id) {
                  contact = update;
                } else {
                  update.save();
                }
              }
              await mcs.invokeMethod("open-contact-form", parameters);
            } else {
              var update = existingParticipant.contact!;
              update.displayName = contact.displayName.replaceFirst("Maybe: ", "");
              update.structuredName = contact.structuredName;
              update.avatar = contact.avatar;
              update.isShared = false;
              if (contact.id == update.id) {
                contact = update;
              } else {
                update.save();
              }
            }
            if (contact.posterPath != "alreadyset") {
              controller.chat.participants.first.setPoster(contact.posterPath); // make sure we are on the same page
            }
            contact.posterPath = null;

            contact.isDismissed = true;
            contact.save();
            controller.suggestedContact.value = null;
          },
          child: Text(
            (controller.chat.participants.first.contact?.isShared ?? true) ? "Add" : "Update",
            style: context.theme.textTheme.titleMedium,
          ),
        ),
        _Dismiss(onPressed: () async {
          var contact = controller.suggestedContact.value!;
          contact.isDismissed = true;
          if (contact.posterPath != null) {
            if (contact.posterPath != "alreadyset") {
              pushService.deletePoster(contact.posterPath!);
            }
            contact.posterPath = null;
          }
          contact.save();
          controller.suggestedContact.value = null;
        }),
      ],
    );
  }
}

class _ShareProfile extends StatelessWidget {
  final ConversationViewController controller;
  const _ShareProfile({required this.controller});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        ContactAvatarWidget(
          size: 38,
          preferHighResAvatar: true,
          scaleSize: false,
        ),
        const SizedBox(width: 15),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("Share your name and photo?", style: context.theme.textTheme.titleMedium),
              Text(
                ss.settings.userName.value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.theme.textTheme.bodyMedium?.copyWith(color: context.theme.colorScheme.outline),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: context.theme.colorScheme.outline.withAlpha(64),
            padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 13),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            elevation: 0.0,
            minimumSize: Size.zero,
          ),
          onPressed: () async {
            ss.settings.sharedContacts.add(controller.chat.participants.first.address);
            ss.saveSettings();
            controller.suggestShare.value = false;
            pushService.updateShareState();

            var msg = await api.newMsg(
              conversation: api.ConversationData(participants: [RustPushBBUtils.bbHandleToRust(controller.chat.participants.first)]),
              sender: await controller.chat.ensureHandle(),
              message: api.Message.shareProfile(await api.decodeProfileMessage(s: ss.settings.shareProfileMessage.value!)),
            );
            await (backend as RustPushBackend).sendMsg(msg);
          },
          child: Text("Share", style: context.theme.textTheme.titleMedium),
        ),
        _Dismiss(onPressed: () async {
          ss.settings.dismissedContacts.add(controller.chat.participants.first.address);
          ss.saveSettings();
          controller.suggestShare.value = false;
          pushService.updateShareState();
        }),
      ],
    );
  }
}

class _Dismiss extends StatelessWidget {
  final VoidCallback onPressed;
  const _Dismiss({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: 0.5,
      child: IconButton(
        icon: Icon(
          CupertinoIcons.clear,
          color: context.theme.colorScheme.outline,
          size: 24,
        ),
        style: ElevatedButton.styleFrom(splashFactory: NoSplash.splashFactory),
        visualDensity: Platform.isAndroid ? VisualDensity.compact : null,
        onPressed: onPressed,
      ),
    );
  }
}
