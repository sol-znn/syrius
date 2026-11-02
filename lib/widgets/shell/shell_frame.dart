import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/utils/app_theme.dart';

/// Keeps the page owner mounted while entry and working geometry change.
class ShellFrame extends StatelessWidget {
  /// Creates a shell with independently owned rail, page and status surfaces.
  const ShellFrame({
    required this.locked,
    required this.rail,
    required this.page,
    required this.status,
    super.key,
  });

  /// Entry mode removes rail interaction and gives the page the whole field.
  final ValueListenable<bool> locked;

  /// The rail retains its collapse choice while it is hidden at entry.
  final Widget rail;

  /// The current page retains its state across a lock-status change.
  final Widget page;

  /// Connection status remains available at entry without wallet flight data.
  final Widget status;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
    valueListenable: locked,
    builder: (BuildContext context, bool locked, _) {
      final AppTokens tokens = AppTokens.of(context);
      return Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Offstage(
            offstage: locked,
            child: TickerMode(
              enabled: !locked,
              child: ExcludeFocus(
                excluding: locked,
                child: ExcludeSemantics(
                  excluding: locked,
                  child: IgnorePointer(
                    ignoring: locked,
                    child: RepaintBoundary(child: rail),
                  ),
                ),
              ),
            ),
          ),
          SizedBox(width: locked ? 0 : tokens.shellRailGap),
          Expanded(
            child: Padding(
              padding: locked ? EdgeInsets.zero : tokens.shellPadding,
              child: Column(
                children: <Widget>[
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(tokens.cardRadius),
                      clipBehavior: locked ? Clip.none : Clip.antiAlias,
                      child: RepaintBoundary(child: page),
                    ),
                  ),
                  SizedBox(height: locked ? 0 : tokens.shellStatusGap),
                  Padding(
                    padding: locked
                        ? tokens.lockedStatusPadding
                        : EdgeInsets.zero,
                    child: RepaintBoundary(child: status),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    },
  );
}
