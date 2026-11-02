import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/home/home.dart'
    show AmountText;
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/extensions/buildcontext_extension.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/page/page_strip.dart';
import 'package:zenon_syrius_wallet_flutter/utils/app_theme.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/accelerator_widgets/accelerator_list_presenter.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/reusable_widgets/buttons/primary_pill.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/reusable_widgets/modals/modal_chrome.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

/// The actual fund and exact selected Pillar's outstanding project count.
/// The owning page guards navigation; this strip performs no RPC.
class AcceleratorStats extends StatelessWidget {
  /// Displays current original fund and vote facts without requesting RPC work.
  const AcceleratorStats({
    required this.snapshot,
    required this.nowTimestamp,
    this.onDonate,
    this.onCreateProject,
    super.key,
  });

  /// Exact source-bound display facts, including explicit unknown amounts.
  final AcceleratorListSnapshot snapshot;

  /// Original display clock in Unix seconds for voting-window counts.
  final int nowTimestamp;

  /// Guarded explicit donation action supplied by the owning page.
  final VoidCallback? onDonate;

  /// Guarded explicit project-creation action supplied by the owning page.
  final VoidCallback? onCreateProject;

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = AppTokens.of(context);
    final bool current = snapshot.isCurrent;
    final AcceleratorListFund fund = current
        ? snapshot.fund
        : const AcceleratorListFund();
    final int? needsVote = snapshot.needsYourVote(nowTimestamp);
    Widget amount(BigInt? value, {required bool qsr}) => value == null
        ? Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                context.l10n.acceleratorUnknown,
                style: tokens.dataText.copyWith(color: tokens.dim),
              ),
              SizedBox(width: tokens.inlineGap),
              Text(
                qsr ? 'QSR' : 'ZNN',
                style: tokens.dataText.copyWith(
                  fontSize: 13,
                  color: qsr ? tokens.qsrInk : tokens.znnInk,
                ),
              ),
            ],
          )
        : AmountText(
            value,
            decimals: coinDecimals,
            symbol: qsr ? 'QSR' : 'ZNN',
            symbolColor: qsr ? tokens.qsrInk : tokens.znnInk,
            style: tokens.stripAmountText,
          );
    return PageStrip(
      key: const Key('accelerator_strip'),
      figures: <StripFigure>[
        StripFigure(
          label: context.l10n.acceleratorFund,
          value: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              KeyedSubtree(
                key: const Key('accelerator_fund_znn'),
                child: amount(fund.znn, qsr: false),
              ),
              Text('  ·  ', style: tokens.dataText.copyWith(color: tokens.dim)),
              KeyedSubtree(
                key: const Key('accelerator_fund_qsr'),
                child: amount(fund.qsr, qsr: true),
              ),
            ],
          ),
        ),
        StripFigure(
          label: context.l10n.acceleratorVoting,
          value: Text(
            needsVote?.toString() ?? context.l10n.acceleratorUnknown,
            key: const Key('accelerator_need_vote_count'),
            style: tokens.stripAmountText,
          ),
          trailing: Text(context.l10n.acceleratorNeedYourPillar),
        ),
      ],
      actions: <Widget>[
        OutlinedButton.icon(
          key: const Key('acc_donate'),
          style: secondaryButtonStyle(context),
          onPressed: current ? onDonate : null,
          icon: const Icon(Icons.volunteer_activism_outlined, size: 18),
          label: Text(context.l10n.acceleratorDonate),
        ),
        PrimaryPill(
          key: const Key('acc_create_project'),
          onPressed: current ? onCreateProject : null,
          icon: const Icon(Icons.add, size: 18),
          child: Text(context.l10n.acceleratorCreateProject),
        ),
      ],
    );
  }
}
