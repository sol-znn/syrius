import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/single_child_widget.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/delegation/view/delegation_actions.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/features.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/utils.dart';
import 'package:zenon_syrius_wallet_flutter/utils/app_theme.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/reusable_widgets/modals/frosted_route.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/reusable_widgets/modals/modal_chrome.dart';

/// A list-sized glass panel for a Nodes action that is not always open.
Future<void> showNodesPanel({
  required BuildContext context,
  required String title,
  required Widget body,
}) async {
  final Size size = MediaQuery.sizeOf(context);
  await showFrostedDialog<void>(
    context: context,
    builder: (BuildContext dialogContext) => DialogCard(
      title: title,
      width: size.width * 0.85,
      body: SizedBox(height: size.height * 0.6, child: body),
      actions: <Widget>[
        TextButton(
          key: const Key('nodes_panel_close'),
          style: quietButtonStyle(dialogContext),
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: Text(dialogContext.l10n.commonClose),
        ),
      ],
    ),
  );
}

/// Opens the live list as the delegation chooser.
///
/// Keeping the existing list also keeps its balance gate, pagination,
/// transaction listener and keyboard traversal. A second delegate form
/// would have to keep those rules in sync with every row in the page.
Future<void> showDelegationChooser(BuildContext context) async {
  if (nodesDelegationBusy(context)) return;
  await showNodesPanel(
    context: context,
    title: context.l10n.nodesDelegate,
    body: MultiBlocProvider(
      providers: <SingleChildWidget>[
        BlocProvider<PillarsBloc>.value(value: context.read<PillarsBloc>()),
        BlocProvider<DelegationBloc>.value(
          value: context.read<DelegationBloc>(),
        ),
        BlocProvider<UndelegateBloc>.value(
          value: context.read<UndelegateBloc>(),
        ),
        BlocProvider<DelegationStatsBloc>.value(
          value: context.read<DelegationStatsBloc>(),
        ),
        BlocProvider<MultipleBalanceBloc>.value(
          value: context.read<MultipleBalanceBloc>(),
        ),
      ],
      child: const NodesDelegationList(),
    ),
  );
}

/// The compact, quiet action beside a headline figure.
ButtonStyle nodesQuietButtonStyle(BuildContext context) {
  final AppTokens tokens = AppTokens.of(context);
  return quietButtonStyle(context).copyWith(
    minimumSize: const WidgetStatePropertyAll<Size>(Size(0, 30)),
    padding: WidgetStatePropertyAll<EdgeInsetsGeometry>(
      EdgeInsetsDirectional.symmetric(horizontal: tokens.cardGap),
    ),
    textStyle: WidgetStatePropertyAll<TextStyle>(tokens.compactText),
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
  );
}
