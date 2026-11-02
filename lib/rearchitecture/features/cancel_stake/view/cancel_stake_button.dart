import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/main.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/cancel_stake/bloc/cancel_stake_bloc.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/card_parts/card_parts.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/utils.dart';
import 'package:zenon_syrius_wallet_flutter/utils/utils.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/widgets.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

/// Button that handles the stake cancellation flow.
class CancelStakeButton extends StatelessWidget {
  /// Creates a [CancelStakeButton].
  const CancelStakeButton({
    required this.stakeHash,
    required this.amount,
    required this.onCancelled,
    this.label,
    this.style,
    super.key,
  });

  /// Hash of the stake entry that should be cancelled.
  final Hash stakeHash;

  /// The ZNN staked, in the smallest unit: the confirmation names it, so a
  /// click on the wrong row is caught before it is sent.
  final BigInt amount;

  /// Called after the stake cancellation succeeds.
  final VoidCallback onCancelled;

  /// The row's localized action label. Null keeps the compact Cancel action.
  final String? label;

  /// The enclosing table's secondary button style.
  final ButtonStyle? style;

  @override
  Widget build(BuildContext context) {
    return BlocProvider<CancelStakeBloc>(
      create: (_) => CancelStakeBloc(
        accountBlockUtils: AccountBlockUtils(),
        zenon: zenon!,
        zenonAddressUtils: ZenonAddressUtils(),
      ),
      child: Row(
        mainAxisAlignment: .center,
        mainAxisSize: .min,
        children: <Widget>[
          // Keep the original control within its cell as text grows.
          Flexible(
            child: BlocConsumer<CancelStakeBloc, CancelStakeState>(
              listener: (BuildContext context, CancelStakeState state) {
                if (state is CancelStakeDone) {
                  onCancelled();
                } else if (state is CancelStakeFailure) {
                  unawaited(
                    NotificationUtils.sendNotificationError(
                      state.exception,
                      context.l10n.errorWhileCancellingStake,
                    ),
                  );
                }
              },
              builder: (BuildContext context, CancelStakeState state) {
                return switch (state) {
                  CancelStakeLoading() => const SyriusLoadingWidget(size: 25),
                  _ => _buildButton(context),
                };
              },
            ),
          ),
        ],
      ),
    );
  }

  OutlinedButton _buildButton(BuildContext context) {
    Future<void> cancel() async {
      final CancelStakeBloc cancelStakeBloc = context.read<CancelStakeBloc>();
      final bool? cancellationConfirmed = await showDialogWithNoAndYesOptions(
        isBarrierDismissible: false,
        context: context,
        title: context.l10n.cancel,
        // Keep the same confirmation for both stake cancellation controls.
        description:
            'Cancel the stake of '
            '${cardAmount(amount, kZnnCoin.decimals, kZnnCoin.symbol)}?',
      );

      if (cancellationConfirmed ?? false) {
        cancelStakeBloc.add(
          CancelStakeRequested(stakeHash: stakeHash),
        );
      }
    }

    final ButtonStyle buttonStyle =
        style ?? cardSecondaryButtonStyle(context, line: AppColors.errorColor);
    if (label != null) {
      return OutlinedButton(
        style: buttonStyle,
        onPressed: cancel,
        child: Text(label!),
      );
    }
    return OutlinedButton.icon(
      style: buttonStyle,
      onPressed: cancel,
      label: Text(context.l10n.cancel),
      icon: const Icon(Icons.close, size: 16),
    );
  }
}
