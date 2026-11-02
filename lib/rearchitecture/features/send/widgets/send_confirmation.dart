import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/send/model/send_intent.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/extensions/buildcontext_extension.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/ltr.dart';
import 'package:zenon_syrius_wallet_flutter/utils/app_theme.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/reusable_widgets/buttons/primary_pill.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/reusable_widgets/modals/modal_chrome.dart';

/// Shows the exact captured transfer without performing any wallet operation.
class SendConfirmation extends StatelessWidget {
  /// Confirmation facts come from the original form and session.
  const SendConfirmation({
    required this.intent,
    required this.onConfirm,
    required this.onCancel,
    this.recipientName,
    this.senderName,
    this.firstTime = false,
    this.contactsUnavailable = false,
    this.hardware = false,
    super.key,
  });

  /// An immutable snapshot of the action being confirmed.
  final SendIntent intent;

  /// Explicit acceptance of only this snapshot.
  final VoidCallback onConfirm;

  /// Leaves the existing draft intact.
  final VoidCallback onCancel;

  /// Optional labels captured when the confirmation opened.
  final String? recipientName;

  /// The sender label captured from the original wallet.
  final String? senderName;

  /// The local remembered history has no send to this destination.
  final bool firstTime;

  /// An unread address book cannot establish an empty history.
  final bool contactsUnavailable;

  /// Only an actual hardware session shows a device-confirmation notice.
  final bool hardware;

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = AppTokens.of(context);
    Widget party(String? name, String address) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (name != null && name.isNotEmpty) Text(name),
        Ltr(child: SelectableText(address, style: tokens.receiveQrAddressText)),
      ],
    );
    Widget row(String label, Widget value) => Padding(
      padding: EdgeInsetsDirectional.only(bottom: tokens.transferFieldGap),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(width: 62, child: Text(label, style: tokens.captionText)),
          Expanded(child: value),
        ],
      ),
    );
    return DialogCard(
      key: const Key('send_confirmation_marker'),
      width: 440,
      radius: tokens.transferCardRadius,
      title: context.l10n.sendConfirmTitle(intent.displayAmount, intent.symbol),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          row(
            context.l10n.sendConfirmTo,
            party(recipientName, intent.toAddress),
          ),
          row(
            context.l10n.sendConfirmFrom,
            party(senderName, intent.fromAddress),
          ),
          row(
            context.l10n.plasma,
            Text(
              context.l10n.sendPlasmaPending,
              style: tokens.transferCaptionText,
            ),
          ),
          if (contactsUnavailable || firstTime)
            Padding(
              padding: EdgeInsetsDirectional.only(
                bottom: tokens.transferFieldGap,
              ),
              child: Text(
                contactsUnavailable
                    ? context.l10n.sendContactsUnavailable
                    : context.l10n.sendFirstTimeRecipient,
                style: tokens.transferCaptionText.copyWith(color: tokens.warn),
              ),
            ),
          if (hardware)
            Container(
              padding: tokens.transferWarningPadding,
              decoration: BoxDecoration(
                color: tokens.card2,
                borderRadius: BorderRadius.circular(
                  tokens.transferControlRadius,
                ),
              ),
              child: Text(
                context.l10n.sendHardwareConfirm,
                style: tokens.transferCaptionText,
              ),
            ),
        ],
      ),
      actions: <Widget>[
        TextButton(
          key: const Key('send_confirmation_cancel'),
          onPressed: onCancel,
          style: quietButtonStyle(context),
          child: Text(context.l10n.cancel),
        ),
        PrimaryPill(
          key: const Key('send_confirmation_accept'),
          onPressed: onConfirm,
          child: Text(context.l10n.send),
        ),
      ],
    );
  }
}
