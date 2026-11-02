import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/extensions/buildcontext_extension.dart';
import 'package:zenon_syrius_wallet_flutter/utils/app_colors.dart';
import 'package:zenon_syrius_wallet_flutter/utils/app_theme.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/reusable_widgets/modals/frosted_route.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/reusable_widgets/modals/modal_chrome.dart';

/// A warning with a "Cancel" and one action. Completes with whether the
/// action was pressed.
///
/// When [onActionButtonPressed] is given it replaces both buttons' handlers,
/// and the caller closes the dialog.
Future<bool> showWarningDialog({
  required BuildContext context,
  required String title,
  required String description,
  required String buttonText,
  VoidCallback? onActionButtonPressed,
}) async {
  bool isPressed = false;
  await showFrostedDialog<void>(
    context: context,
    builder: (BuildContext context) => DialogCard(
      icon: const Icon(
        Icons.warning_amber_rounded,
        size: 20,
        color: AppColors.warn,
      ),
      title: title,
      body: Text(description),
      actions: <Widget>[
        TextButton(
          onPressed:
              onActionButtonPressed ??
              () {
                Navigator.pop(context);
              },
          style: quietButtonStyle(context),
          child: Text(context.l10n.cancel),
        ),
        OutlinedButton(
          onPressed:
              onActionButtonPressed ??
              () {
                isPressed = true;
                Navigator.pop(context);
              },
          child: Text(
            buttonText.isEmpty ? context.l10n.commonOk : buttonText,
          ),
        ),
      ],
    ),
    barrierDismissible: false,
  );
  return isPressed;
}

/// A question answered with "No" or "Yes". Completes with the answer, or
/// null when the dialog was dismissed.
Future<bool?> showDialogWithNoAndYesOptions({
  required BuildContext context,
  required String title,
  required bool isBarrierDismissible,
  Widget? content,
  String? description,
}) => showFrostedDialog<bool>(
  barrierDismissible: isBarrierDismissible,
  context: context,
  builder: (BuildContext context) => DialogCard(
    title: title,
    body: content ?? Text(description!),
    actions: <Widget>[
      TextButton(
        key: const Key('dialog_no_button'),
        style: quietButtonStyle(context),
        onPressed: () {
          Navigator.pop(context, false);
        },
        child: Text(context.l10n.commonNo),
      ),
      OutlinedButton(
        key: const Key('dialog_yes_button'),
        onPressed: () {
          Navigator.pop(context, true);
        },
        child: Text(context.l10n.commonYes),
      ),
    ],
  ),
);

/// Shows [content], usually a `BaseModal`, centred over the page.
Future<Object?> showCustomDialog({
  required BuildContext context,
  required Widget content,
}) => Navigator.of(context, rootNavigator: true).push<Object?>(
  FrostedDialogRoute<Object?>(
    barrierLabel: '',
    transitionDuration: const Duration(milliseconds: 240),
    transitionBuilder:
        (
          BuildContext context,
          Animation<double> animation,
          Animation<double> secondaryAnimation,
          Widget child,
        ) {
          // A driven animation holds no listener of its own, so building one
          // per rebuild leaks nothing.
          final Animation<double> curve = animation.drive(
            CurveTween(curve: AppTokens.of(context).spring),
          );
          return FadeTransition(
            opacity: curve,
            child: AnimatedBuilder(
              animation: curve,
              child: child,
              builder: (BuildContext context, Widget? child) =>
                  Transform.translate(
                    offset: Offset(0, 6 * (1 - curve.value)),
                    child: child,
                  ),
            ),
          );
        },
    pageBuilder:
        (
          BuildContext context,
          Animation<double> animation,
          Animation<double> secondaryAnimation,
        ) => Center(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(kCardRadius),
            child: content,
          ),
        ),
  ),
);
