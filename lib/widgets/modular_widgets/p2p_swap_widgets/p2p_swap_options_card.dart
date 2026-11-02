import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/blocs/pow_generating_status_bloc.dart';
import 'package:zenon_syrius_wallet_flutter/main.dart' as app;
import 'package:zenon_syrius_wallet_flutter/model/p2p_swap/p2p_swap.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/extensions/buildcontext_extension.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/ltr.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/page/page_strip.dart';
import 'package:zenon_syrius_wallet_flutter/utils/app_theme.dart';
import 'package:zenon_syrius_wallet_flutter/utils/toast_utils.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/p2p_swap_widgets/swap_list_presenter.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/reusable_widgets/buttons/primary_pill.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/reusable_widgets/modals/modal_chrome.dart';

/// The counts and actions share the table's one complete captured snapshot.
class P2pSwapOptionsCard extends StatelessWidget {
  /// Displays counts and routes actions through the same captured binding.
  const P2pSwapOptionsCard({
    this.snapshot,
    this.binding,
    this.onStart,
    this.onJoin,
    this.swaps,
    super.key,
  });

  /// Complete source snapshot, or null when no count is established.
  final SwapListSnapshot? snapshot;

  /// Original resources that must remain owned for either action.
  final SwapListBinding? binding;

  /// Opens the explicit Start flow without publishing a deposit itself.
  final VoidCallback? onStart;

  /// Opens the explicit Join lookup and confirmation flow.
  final VoidCallback? onJoin;

  /// Retained for old callers. A stream alone cannot authorize an action.
  final Stream<List<P2pSwap>>? swaps;

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = AppTokens.of(context);
    Widget count(int? value) =>
        Ltr(child: Text(value?.toString() ?? context.l10n.swapListUnknown));
    final Widget strip = PageStrip(
      key: const Key('p2p_swaps_strip'),
      figures: <StripFigure>[
        StripFigure(
          label: context.l10n.swapListActive,
          value: count(snapshot?.active),
        ),
        StripFigure(
          label: context.l10n.swapListCompleted,
          value: count(snapshot?.completed),
        ),
        StripFigure(
          label: context.l10n.swapListToReclaim,
          value: count(snapshot?.reclaimable),
        ),
      ],
      actions: <Widget>[
        OutlinedButton.icon(
          key: const Key('p2p_join_swap'),
          onPressed: onJoin == null || binding?.ownsResources() != true
              ? null
              : () => _invoke(context, onJoin!),
          style: secondaryButtonStyle(context),
          icon: Icon(Icons.link, size: tokens.railIconSize),
          label: Text(context.l10n.swapListJoin),
        ),
        PrimaryPill(
          key: const Key('p2p_start_swap'),
          onPressed: onStart == null || binding?.ownsResources() != true
              ? null
              : () => _invoke(context, onStart!),
          icon: Icon(Icons.add, size: tokens.railIconSize),
          child: Text(context.l10n.swapListStart),
        ),
      ],
    );
    return strip;
  }

  void _invoke(BuildContext context, VoidCallback action) {
    final PowGeneratingStatusBloc? status =
        app.sl.isRegistered<PowGeneratingStatusBloc>()
        ? app.sl<PowGeneratingStatusBloc>()
        : null;
    if (status?.value.isGenerating ?? false) {
      ToastUtils.showToast(context, context.l10n.swapListPlasmaWait);
      return;
    }
    if (binding?.ownsResources() == true) action();
  }
}
