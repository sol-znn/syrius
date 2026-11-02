import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/registration_success/registration_confirmation.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/extensions/buildcontext_extension.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/ltr.dart';
import 'package:zenon_syrius_wallet_flutter/utils/app_theme.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/reusable_widgets/app_lottie.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/reusable_widgets/buttons/primary_pill.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/reusable_widgets/modals/modal_chrome.dart';

/// Keeps the genuine form and its listeners mounted behind its receipt.
class RegistrationRetainedFlow extends StatelessWidget {
  /// A published result closes input without disposing any existing step.
  const RegistrationRetainedFlow({
    required this.published,
    required this.form,
    required this.receipt,
    super.key,
  });

  /// Whether the first original result has returned.
  final bool published;

  /// The same stepper, at the same position, for the entire flow.
  final Widget form;

  /// The waiting or confirmed receipt.
  final Widget receipt;

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: <Widget>[
      TickerMode(
        enabled: !published,
        child: Focus(
          canRequestFocus: false,
          skipTraversal: true,
          // ExcludeFocus leaves retained EditableText traversal latched after
          // return. This gate matches the existing step and page switchers.
          descendantsAreFocusable: !published,
          child: IgnorePointer(
            ignoring: published,
            child: ExcludeSemantics(
              excluding: published,
              child: Offstage(offstage: published, child: form),
            ),
          ),
        ),
      ),
      if (published) Positioned.fill(child: receipt),
    ],
  );
}

/// The original art is mounted only while exact confirmation is authoritative.
class RegistrationConfirmedArt extends StatelessWidget {
  /// A missing owner remains waiting, including legacy constructor callsites.
  const RegistrationConfirmedArt({
    required this.asset,
    this.confirmation,
    super.key,
  });

  /// The unchanged bundled original.
  final AppLottieAsset asset;

  /// The flow that owns the exact positive confirmation.
  final RegistrationConfirmation? confirmation;

  @override
  Widget build(BuildContext context) {
    final RegistrationConfirmation? owner = confirmation;
    if (owner == null) return const SizedBox.shrink();
    return ListenableBuilder(
      listenable: owner,
      builder: (BuildContext context, _) => owner.isConfirmed
          ? AppLottie(
              asset,
              key: ValueKey<String>(owner.publication!.hashText),
              size: AppTokens.of(context).registrationArtSize,
              repeat: false,
            )
          : const SizedBox.shrink(),
    );
  }
}

/// The registration ledger and one full-size confirmed object.
class RegistrationSuccessSurface extends StatelessWidget {
  /// Keeps waiting visible without mounting an assembly or a retry action.
  const RegistrationSuccessSurface({
    required this.asset,
    required this.heading,
    required this.viewLabel,
    required this.onView,
    required this.confirmedKey,
    this.confirmation,
    this.steps = const <String>[],
    this.facts = const <Widget>[],
    this.caption,
    this.anotherLabel,
    this.onAnother,
    super.key,
  });

  /// The original bundled object.
  final AppLottieAsset asset;

  /// Evaluated from the retained original publication.
  final String heading;

  /// The existing navigation callback's short label.
  final String viewLabel;

  /// Returns to the original owner or token list.
  final VoidCallback onView;

  /// A positive harness marker, present only after exact confirmation.
  final Key confirmedKey;

  /// A missing owner has no authority to celebrate.
  final RegistrationConfirmation? confirmation;

  /// The real form's completed stages.
  final List<String> steps;

  /// Original registration costs, when their values were established.
  final List<Widget> facts;

  /// One short line below the confirmed heading.
  final String? caption;

  /// The explicit action that starts another registration.
  final String? anotherLabel;

  /// Hidden until this original registration is confirmed.
  final VoidCallback? onAnother;

  @override
  Widget build(BuildContext context) {
    final RegistrationConfirmation? owner = confirmation;
    if (owner == null) return _buildBody(context, confirmed: false);
    return ListenableBuilder(
      listenable: owner,
      builder: (BuildContext context, _) =>
          _buildBody(context, confirmed: owner.isConfirmed),
    );
  }

  Widget _buildBody(BuildContext context, {required bool confirmed}) {
    final AppTokens tokens = AppTokens.of(context);
    final RegistrationPublication? publication = confirmation?.publication;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Container(
          width: tokens.registrationRailWidth,
          decoration: BoxDecoration(
            border: BorderDirectional(end: BorderSide(color: tokens.line)),
          ),
          child: SingleChildScrollView(
            padding: EdgeInsets.all(tokens.registrationInset),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: tokens.registrationActionGap,
              children: <Widget>[
                for (int i = 0; i < steps.length; i++)
                  Row(
                    children: <Widget>[
                      Icon(
                        i == steps.length - 1 && !confirmed
                            ? Icons.hourglass_empty
                            : Icons.check_circle,
                        color: i == steps.length - 1 && !confirmed
                            ? tokens.qsr
                            : tokens.znnInk,
                        size: tokens.registrationInset,
                      ),
                      SizedBox(width: tokens.inlineGap),
                      Expanded(
                        child: Text(
                          steps[i],
                          style: tokens.registrationCaptionText,
                        ),
                      ),
                    ],
                  ),
                Divider(color: tokens.line),
                ...facts,
                if (publication != null) ...<Widget>[
                  RegistrationReceiptFact(
                    label: context.l10n.registrationBlock,
                    value: _Identifier(publication.hashText),
                  ),
                  RegistrationReceiptFact(
                    label: context.l10n.address,
                    value: _Identifier(publication.ownerAddress),
                  ),
                  RegistrationReceiptFact(
                    label: context.l10n.registrationChain,
                    value: Ltr(
                      child: Text(
                        '${publication.chainId}',
                        style: tokens.dataText,
                      ),
                    ),
                  ),
                ],
                if (confirmed && onAnother != null && anotherLabel != null)
                  TextButton(
                    key: const Key('registration_another'),
                    style: quietButtonStyle(context),
                    onPressed: () {
                      if (confirmation?.isConfirmed ?? false) onAnother!();
                    },
                    child: Text(anotherLabel!),
                  ),
              ],
            ),
          ),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) =>
                SingleChildScrollView(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight,
                    ),
                    child: Padding(
                      padding: tokens.registrationPadding,
                      child: Column(
                        key: confirmed
                            ? confirmedKey
                            : const Key('registration_waiting'),
                        mainAxisAlignment: MainAxisAlignment.center,
                        spacing: tokens.registrationGap,
                        children: <Widget>[
                          if (confirmed)
                            RegistrationConfirmedArt(
                              asset: asset,
                              confirmation: confirmation,
                            )
                          else
                            SizedBox(
                              width: tokens.registrationArtSize,
                              height: tokens.registrationArtSize,
                              child: Center(
                                child: Icon(
                                  Icons.hourglass_empty,
                                  color: tokens.qsr,
                                  size: tokens.heroIconSize,
                                ),
                              ),
                            ),
                          Transform.translate(
                            offset: Offset(0, tokens.registrationHeadingOffset),
                            child: Column(
                              spacing: tokens.registrationGap,
                              children: <Widget>[
                                Text(
                                  confirmed
                                      ? heading
                                      : context.l10n.registrationWaiting,
                                  style: tokens.registrationHeadingText,
                                  textAlign: TextAlign.center,
                                ),
                                if (confirmed && caption != null)
                                  Text(
                                    caption!,
                                    style: tokens.registrationCaptionText,
                                    textAlign: TextAlign.center,
                                  ),
                                Padding(
                                  padding: EdgeInsets.only(
                                    top: tokens.registrationActionGap,
                                  ),
                                  child: Wrap(
                                    spacing: tokens.inlineGap,
                                    runSpacing: tokens.inlineGap,
                                    alignment: WrapAlignment.center,
                                    children: <Widget>[
                                      if (confirmed)
                                        PrimaryPill(
                                          onPressed: () {
                                            if (confirmation?.isConfirmed ??
                                                false) {
                                              onView();
                                            }
                                          },
                                          child: Text(viewLabel),
                                        ),
                                      OutlinedButton(
                                        style: secondaryButtonStyle(context),
                                        onPressed: onView,
                                        child: Text(
                                          context.l10n.registrationDone,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
          ),
        ),
      ],
    );
  }
}

/// One established fact from the original registration receipt.
class RegistrationReceiptFact extends StatelessWidget {
  /// Values have their own amount or identifier presentation.
  const RegistrationReceiptFact({
    required this.label,
    required this.value,
    super.key,
  });

  /// The ledger label.
  final String label;

  /// An exact amount, chain or identifier.
  final Widget value;

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = AppTokens.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: tokens.registrationGap,
      children: <Widget>[
        Text(label.toUpperCase(), style: tokens.ledgerText),
        value,
      ],
    );
  }
}

class _Identifier extends StatelessWidget {
  const _Identifier(this.value);

  final String value;

  @override
  Widget build(BuildContext context) {
    final String shortened = value.length > 12
        ? '${value.substring(0, 6)}…${value.substring(value.length - 4)}'
        : value;
    return Tooltip(
      message: value,
      child: Ltr(
        child: Text(shortened, style: AppTokens.of(context).dataText),
      ),
    );
  }
}
