import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/single_child_widget.dart';
import 'package:zenon_syrius_wallet_flutter/main.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/features.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/utils.dart';
import 'package:zenon_syrius_wallet_flutter/utils/utils.dart';
import 'package:zenon_syrius_wallet_flutter/utils/wallet_action_context.dart';
import 'package:zenon_syrius_wallet_flutter/utils/wallet_context_revision.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/reusable_widgets/reusable_widgets.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

/// The live action hold shared by every Nodes delegation entry point.
bool nodesDelegationBusy(BuildContext context) =>
    context.read<DelegationBloc>().state is DelegationLoading ||
    context.read<UndelegateBloc>().state is UndelegateLoading;

/// The same hold, subscribed for buttons that show its disabled state.
bool watchNodesDelegationBusy(BuildContext context) {
  final DelegationState delegation = context.watch<DelegationBloc>().state;
  final UndelegateState undelegation = context.watch<UndelegateBloc>().state;
  return delegation is DelegationLoading || undelegation is UndelegateLoading;
}

AccountBlockUtils _capturedPublisher() {
  final String? address = kSelectedAddress;
  final WalletActionContext? original = address == null
      ? null
      : WalletActionContext.capture(address);
  return AccountBlockUtils(canPublish: () => original?.isCurrent ?? false);
}

/// Keeps the two existing action blocs alive above the page and its dialogs.
///
/// The page owns result handling once. A list in a chooser can disappear
/// during a send without losing the pending hold, refresh or error result.
class NodesDelegationScope extends StatelessWidget {
  /// Creates the scope; supplied blocs remain owned by their caller.
  const NodesDelegationScope({
    required this.child,
    this.delegationBloc,
    this.undelegateBloc,
    super.key,
  });

  /// The page and the entry points that use the shared hold.
  final Widget child;

  /// An existing action bloc, chiefly for an isolated widget test.
  final DelegationBloc? delegationBloc;

  /// An existing action bloc, chiefly for an isolated widget test.
  final UndelegateBloc? undelegateBloc;

  @override
  Widget build(BuildContext context) => MultiBlocProvider(
    providers: <SingleChildWidget>[
      if (delegationBloc case final DelegationBloc bloc)
        BlocProvider<DelegationBloc>.value(value: bloc)
      else
        BlocProvider<DelegationBloc>(
          create: (_) => DelegationBloc(
            accountBlockUtils: _capturedPublisher(),
            zenon: zenon!,
          ),
        ),
      if (undelegateBloc case final UndelegateBloc bloc)
        BlocProvider<UndelegateBloc>.value(value: bloc)
      else
        BlocProvider<UndelegateBloc>(
          create: (_) => UndelegateBloc(
            accountBlockUtils: _capturedPublisher(),
            zenon: zenon!,
          ),
        ),
    ],
    child: _Results(child: child),
  );
}

class _Results extends StatelessWidget {
  const _Results({required this.child});

  final Widget child;

  void _refresh(BuildContext context) {
    context.read<DelegationStatsBloc>().add(
      FetchRequestData(address: Address.parse(kSelectedAddress!)),
    );
  }

  @override
  Widget build(BuildContext context) => MultiBlocListener(
    listeners: <SingleChildWidget>[
      BlocListener<DelegationBloc, DelegationState>(
        listener: (BuildContext context, DelegationState state) {
          if (state is DelegationDone) {
            _refresh(context);
          } else if (state is DelegationFailure) {
            unawaited(
              NotificationUtils.sendNotificationError(
                state.exception,
                context.l10n.pillarDelegationError,
              ),
            );
          }
        },
      ),
      BlocListener<UndelegateBloc, UndelegateState>(
        listener: (BuildContext context, UndelegateState state) {
          if (state is UndelegateDone) {
            _refresh(context);
          } else if (state is UndelegateFailure) {
            unawaited(
              NotificationUtils.sendNotificationError(
                state.exception,
                context.l10n.errorUndelegating,
              ),
            );
          }
        },
      ),
    ],
    child: child,
  );
}

/// The existing list with the Nodes action scope rather than a local sender.
class NodesDelegationList extends StatelessWidget {
  /// Creates the list under a [NodesDelegationScope] and [PillarsBloc].
  const NodesDelegationList({this.heading, super.key});

  /// Common Nodes tabs occupy the list card's heading.
  final Widget? heading;

  @override
  Widget build(BuildContext context) => PillarsCard(
    heading: heading,
    delegationBloc: context.read<DelegationBloc>(),
    delegationBlocked: watchNodesDelegationBusy(context),
  );
}

/// Confirms the current delegation, then uses the existing undelegate event.
Future<void> requestNodesUndelegation(
  BuildContext context, {
  required String pillarName,
}) async {
  if (nodesDelegationBusy(context)) return;
  final String address = kSelectedAddress!;
  final int revision = WalletContextRevision.value;
  final Zenon? client = zenon;
  final String? node = kCurrentNode;
  final int chain = getChainIdentifier();
  final bool? confirmed = await showDialogWithNoAndYesOptions(
    context: context,
    title: context.l10n.nodesUndelegate,
    description: context.l10n.nodesUndelegateConfirm(pillarName),
    isBarrierDismissible: true,
  );
  if (!context.mounted ||
      confirmed != true ||
      kSelectedAddress != address ||
      WalletContextRevision.value != revision ||
      !identical(client, zenon) ||
      kCurrentNode != node ||
      getChainIdentifier() != chain ||
      nodesDelegationBusy(context)) {
    return;
  }
  final FetchState<DelegationInfo> current = context
      .read<DelegationStatsBloc>()
      .state;
  // The question names one pillar. A refreshed or changed delegation is
  // another decision, so it cannot inherit this answer.
  if (current is! FetchPopulated<DelegationInfo> ||
      current.data.name != pillarName) {
    return;
  }
  context.read<UndelegateBloc>().add(
    UndelegateRequested(address: Address.parse(address)),
  );
}
