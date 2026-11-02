import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/extensions/buildcontext_extension.dart';
import 'package:zenon_syrius_wallet_flutter/utils/app_theme.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/shell/page_refresh.dart';

/// A read refresh shared by the page's button and its shell shortcut.
class RefreshButton extends StatelessWidget {
  /// Constructs a new instance.
  const RefreshButton({
    required this._onPressed,
    super.key,
  });

  final VoidCallback _onPressed;

  @override
  Widget build(BuildContext context) {
    return PageRefreshAction(
      onRefresh: _onPressed,
      child: IconButton(
        mouseCursor: SystemMouseCursors.click,
        tooltip: context.l10n.commonRefresh,
        iconSize: 18,
        color: AppTokens.of(context).dim,
        icon: const Icon(Icons.refresh),
        onPressed: _onPressed,
      ),
    );
  }
}
