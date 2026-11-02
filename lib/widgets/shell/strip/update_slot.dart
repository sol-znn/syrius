import 'package:flutter_svg/flutter_svg.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/extensions/buildcontext_extension.dart';
import 'package:zenon_syrius_wallet_flutter/seams/seam.dart';
import 'package:zenon_syrius_wallet_flutter/utils/app_theme.dart';

/// The drawn update line, held behind the unbuilt wallet-release service.
/// With no verified display data it names the feature, not an available
/// release. It neither checks GitHub nor starts a download or installation.
class WalletUpdateSlot extends StatelessWidget {
  /// Creates the slot. A supplied version must come from verified display
  /// data or an explicit harness fixture; there is no example-version default.
  const WalletUpdateSlot({this.version, super.key});

  /// The known release version, absent until the caller has real data.
  final String? version;

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = AppTokens.of(context);
    final String? version = this.version;
    final TextStyle text = Theme.of(context).textTheme.titleMedium!.copyWith(
      fontSize: 13,
      color: tokens.warn,
    );
    return SeamGate(
      seam: Seam.walletUpdateNotice,
      child: Row(
        key: const Key('strip_update'),
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          SvgPicture.string(
            '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" '
            'fill="none" stroke="currentColor" stroke-width="1.8" '
            'stroke-linecap="round" stroke-linejoin="round"> '
            '<path d="M12 3v12M7 10l5 5 5-5M4 21h16"/></svg>',
            // The strip and Settings both use the mockup's .i.s symbol size.
            width: tokens.settingsIconSize,
            height: tokens.settingsIconSize,
            colorFilter: ColorFilter.mode(tokens.warn, BlendMode.srcIn),
            excludeFromSemantics: true,
          ),
          SizedBox(width: tokens.statusDotSize),
          Text(
            version == null || version.isEmpty
                ? context.l10n.stripWalletUpdates
                : context.l10n.stripUpdateAvailable(version),
            key: const Key('strip_update_label'),
            style: text,
            maxLines: 1,
            softWrap: false,
          ),
          SizedBox(width: tokens.statusDotSize),
          OutlinedButton(
            key: const Key('strip_update_button'),
            onPressed: () => throw const SeamNotBuilt(Seam.walletUpdateNotice),
            style: OutlinedButton.styleFrom(
              foregroundColor: tokens.foreground,
              backgroundColor: tokens.card2,
              side: BorderSide(color: tokens.line),
              padding: EdgeInsets.symmetric(horizontal: tokens.cardGap),
              minimumSize: Size.zero,
              fixedSize: Size.fromHeight(
                tokens.statusStripHeight - tokens.statusStripPadding.vertical,
              ),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              shape: const StadiumBorder(),
              textStyle: text.copyWith(
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
            child: Text(context.l10n.update),
          ),
        ],
      ),
    );
  }
}
