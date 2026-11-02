import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/home/home.dart'
    show AmountText;
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/extensions/buildcontext_extension.dart';
import 'package:zenon_syrius_wallet_flutter/utils/app_theme.dart';
import 'package:zenon_syrius_wallet_flutter/utils/format_utils.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

/// Read-only compatibility facts. Ownership actions require a captured source.
class ProjectsStats extends StatelessWidget {
  /// Displays the supplied original project without acquiring action resources.
  const ProjectsStats(this.project, {super.key});

  /// Original metadata, owner, creation time and exact native funding amounts.
  final Project project;
  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = AppTokens.of(context);
    final String owner = project.owner.toString();
    final String short = owner.length > 14
        ? '${owner.substring(0, 7)}…${owner.substring(owner.length - 6)}'
        : owner;
    Widget fact(String label, Widget child) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(label.toUpperCase(), style: tokens.ledgerText),
        SizedBox(height: tokens.inlineGap),
        child,
      ],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Wrap(
          spacing: tokens.acceleratorDetailFactsGap,
          runSpacing: tokens.cardGap,
          children: <Widget>[
            fact(
              context.l10n.acceleratorBudget,
              Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  AmountText(
                    project.znnFundsNeeded,
                    decimals: coinDecimals,
                    symbol: 'ZNN',
                    style: tokens.dataText,
                  ),
                  Text(
                    ' · ',
                    style: tokens.dataText.copyWith(color: tokens.dim),
                  ),
                  AmountText(
                    project.qsrFundsNeeded,
                    decimals: coinDecimals,
                    symbol: 'QSR',
                    style: tokens.dataText,
                  ),
                ],
              ),
            ),
            fact(
              context.l10n.acceleratorOwner,
              Tooltip(
                message: owner,
                child: Text(short, style: tokens.dataText),
              ),
            ),
            fact(
              context.l10n.acceleratorCreated,
              Text(
                FormatUtils.formatDate(project.creationTimestamp * 1000),
                style: tokens.bodyText,
              ),
            ),
          ],
        ),
        SizedBox(height: tokens.panelGap),
        Text(
          project.description,
          style: tokens.bodyText.copyWith(color: tokens.dim),
        ),
      ],
    );
  }
}
