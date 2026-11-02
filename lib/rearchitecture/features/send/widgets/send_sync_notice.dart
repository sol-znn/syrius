import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/node_sync_status/node_sync_status.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/utils.dart';
import 'package:zenon_syrius_wallet_flutter/utils/app_theme.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

/// The reported lag, using the same three-momentum slack as the status strip.
///
/// The pair's first value remembers a previous connection's sync status.
/// Only the current SyncInfo can establish a lag; absent heights cannot.
int? sendMomentumsBehind(NodeSyncStatusState? state) {
  final SyncInfo? info = state?.data?.second;
  if (state?.status != TimerStatus.success ||
      info == null ||
      info.state == SyncState.syncDone ||
      info.currentHeight <= 0 ||
      info.targetHeight <= 0) {
    return null;
  }
  final int behind = info.targetHeight - info.currentHeight;
  return behind < 3 ? null : behind;
}

/// The known-lag note, shared by standalone Send and Transfer's header.
class SendSyncNotice extends StatelessWidget {
  /// Observes the existing session cubit without starting a timer or read.
  const SendSyncNotice({this.syncCubit, super.key});

  /// The provided session owner when omitted.
  final NodeSyncStatusCubit? syncCubit;

  @override
  Widget build(BuildContext context) {
    final NodeSyncStatusCubit? cubit =
        syncCubit ?? context.read<NodeSyncStatusCubit?>();
    if (cubit == null) return const SizedBox.shrink();
    return BlocBuilder<NodeSyncStatusCubit, NodeSyncStatusState>(
      bloc: cubit,
      builder: (BuildContext context, NodeSyncStatusState state) {
        final int? lag = sendMomentumsBehind(state);
        if (lag == null) return const SizedBox.shrink();
        final AppTokens tokens = AppTokens.of(context);
        return Container(
          key: const Key('send_node_behind'),
          padding: tokens.transferSyncPadding,
          color: tokens.transferWarningTint,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Icon(
                Icons.warning_amber_rounded,
                color: tokens.warn,
                size: tokens.heroIconSize,
              ),
              SizedBox(width: tokens.transferFieldGap),
              Expanded(
                child: Text(
                  '${context.l10n.sendNodeBehind(lag)} '
                  '${context.l10n.sendWaitForSync}',
                  style: tokens.transferCaptionText,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
