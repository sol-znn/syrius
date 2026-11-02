import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/create_pillar_stepper/widgets/pillar_step_parts.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/features.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/registration_success/registration_confirmation.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/utils.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/ltr.dart';
import 'package:zenon_syrius_wallet_flutter/utils/utils.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/widgets.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

/// Deploy step for registering a sentinel: the review of what Register
/// sends, and Register under it.
class DeploySentinelStep extends StatefulWidget {
  /// Creates a [DeploySentinelStep].
  const DeploySentinelStep({
    required this.address,
    required this.onDeployDone,
    this.onBackPressed,
    this.onPublished,
    this.active = true,
    super.key,
  });

  /// The address the Sentinel is registered for.
  final String address;

  /// Called when deployment completes.
  final VoidCallback onDeployDone;

  /// Retains the original result before the legacy completion callback runs.
  final ValueChanged<RegistrationPublication>? onPublished;

  /// Called when the user wants to go back. No Back button when null.
  final VoidCallback? onBackPressed;

  /// Whether this is the step shown.
  final bool active;

  @override
  State<DeploySentinelStep> createState() => _DeploySentinelStepState();
}

class _DeploySentinelStepState extends State<DeploySentinelStep> {
  final GlobalKey<LoadingButtonState> _registerButtonKey = GlobalKey();

  // From the press until the bloc is done or has failed.
  bool _isSending = false;
  bool _accepted = false;
  BigInt? _submittedQsrCost;

  @override
  Widget build(BuildContext context) {
    return BlocListener<DeploySentinelBloc, DeploySentinelState>(
      listener: (_, DeploySentinelState state) => _onDeployStateChanged(state),
      child: TokenStepFrame(
        active: widget.active,
        busy: _isSending,
        onBack: widget.onBackPressed,
        // Nothing is typed here, so the frame gives the focus to Register
        // when the step opens, and Enter is then a press of it.
        body: _Review(address: widget.address),
        primary: Focus(
          canRequestFocus: false,
          skipTraversal: true,
          onKeyEvent: _onRegisterKey,
          // The key stays on a wrapper: the button is looked up under it.
          child: KeyedSubtree(
            key: const Key('sentinel_register_button'),
            child: LoadingButton(
              text: context.l10n.register,
              onPressed: _isSending || _accepted ? null : _onDeployPressed,
              circularBorderRadius: kLoadingButtonMinSize.height / 2,
              key: _registerButtonKey,
            ),
          ),
        ),
      ),
    );
  }

  /// Takes the repeats of a held key away from Register.
  ///
  /// Every step before this one can be passed with Enter on its Next, and
  /// each step hands the focus to the next one's action. A key held down
  /// would otherwise run through them all and lock 5,000 ZNN unread; a
  /// press of its own still registers.
  KeyEventResult _onRegisterKey(FocusNode node, KeyEvent event) {
    final bool activates =
        event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter ||
        event.logicalKey == LogicalKeyboardKey.space;
    return activates && event is KeyRepeatEvent
        ? KeyEventResult.handled
        : KeyEventResult.ignored;
  }

  void _onDeployStateChanged(DeploySentinelState state) {
    if (_accepted) return;
    if (state is DeploySentinelDone) {
      _accepted = true;
      final AccountBlockTemplate? block = state.accountBlock;
      if (block != null) {
        try {
          widget.onPublished?.call(
            RegistrationPublication(
              accountBlock: block,
              qsrCost: _submittedQsrCost,
            ),
          );
        } on Object {
          // Receipt display cannot replace the accepted result in the bloc.
        }
      }
      _registerButtonKey.currentState?.animateReverse();
      setState(() {
        _isSending = false;
      });
      try {
        widget.onDeployDone();
      } on Object {
        // A completion observer never retries the accepted registration.
      }
    } else if (state is DeploySentinelFailure) {
      _registerButtonKey.currentState?.animateReverse();
      setState(() {
        _isSending = false;
      });
      unawaited(
        NotificationUtils.sendNotificationError(
          state.exception,
          context.l10n.errorDeployingSentinel,
        ),
      );
    } else if (state is DeploySentinelLoading) {
      _registerButtonKey.currentState?.animateForward();
      setState(() {
        _isSending = true;
      });
    }
  }

  void _onDeployPressed() {
    if (_isSending || _accepted || !widget.active) {
      return;
    }
    if (widget.onPublished != null) {
      final FetchState<CreateSentinelQsrInfoData> state = context
          .read<CreateSentinelQsrInfoBloc>()
          .state;
      _submittedQsrCost = state is FetchPopulated<CreateSentinelQsrInfoData>
          ? state.data.cost
          : null;
    }
    setState(() {
      _isSending = true;
    });
    context.read<DeploySentinelBloc>().add(const DeploySentinelRequested());
  }
}

/// What a Sentinel is about to be registered with: the address it is
/// registered for, the ZNN that is locked and the QSR deposited for it.
///
/// A Sentinel has no name, producer address or percentages, so the Pillar's
/// review block does not fit; its lines do, and are used as they are.
class _Review extends StatelessWidget {
  const _Review({required this.address});

  final String address;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        PillarReviewRow(
          label: context.l10n.address,
          // Every character must be read: it takes a second line before it
          // is cut, and shows whole on hover. Left to right in every
          // language, at the app's start.
          value: Tooltip(
            message: address,
            child: Text(
              address,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textDirection: TextDirection.ltr,
              textAlign: ltrTextAlign(context),
              style: accFieldTextStyle(context, mono: true),
            ),
          ),
        ),
        PillarReviewRow.amount(
          context: context,
          label: context.l10n.createPillarCollateralLabel,
          amount: sentinelRegisterZnnAmount,
          token: kZnnCoin,
        ),
        const _DepositRow(),
      ],
    );
  }
}

/// The QSR deposited for the Sentinel, in the review. It is read from what
/// the QSR step fetched, and left out until that is known.
class _DepositRow extends StatelessWidget {
  const _DepositRow();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<
      CreateSentinelQsrInfoBloc,
      FetchState<CreateSentinelQsrInfoData>
    >(
      builder:
          (BuildContext context, FetchState<CreateSentinelQsrInfoData> s) =>
              switch (s) {
                FetchPopulated<CreateSentinelQsrInfoData>() =>
                  PillarReviewRow.amount(
                    context: context,
                    label: context.l10n.createSentinelDepositLabel,
                    amount: s.data.cost,
                    token: kQsrCoin,
                  ),
                _ => const SizedBox.shrink(),
              },
    );
  }
}
