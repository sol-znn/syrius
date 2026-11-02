import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/extensions/buildcontext_extension.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/motion/rise_switcher.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/page/page_widgets.dart';
import 'package:zenon_syrius_wallet_flutter/utils/app_theme.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/shell/rail.dart'
    show buildShellSymbol;

/// Settings destinations, in the mockup's section-menu order.
enum SettingsSectionId {
  /// Wallet addresses and contacts.
  addresses,

  /// Connections and the embedded node.
  node,

  /// Locking, backup and authentication.
  security,

  /// Appearance and value visibility.
  display,

  /// Wallet maintenance and operator modes.
  wallet,

  /// Connected sites and pairings.
  apps,

  /// The application and its licences.
  about;

  /// The short localized section name.
  String label(BuildContext context) => switch (this) {
    addresses => context.l10n.settingsSectionAddresses,
    node => context.l10n.settingsSectionNode,
    security => context.l10n.settingsSectionSecurity,
    display => context.l10n.settingsSectionDisplay,
    wallet => context.l10n.settingsSectionWallet,
    apps => context.l10n.settingsSectionApps,
    about => context.l10n.settingsSectionAbout,
  };

  /// The section's navigation mark.
  String get symbol => switch (this) {
    addresses => 'book',
    node => 'globe',
    security => 'shield',
    display => 'eye',
    wallet => 'gear',
    apps => 'link',
    about => 'info',
  };
}

/// One section menu and the current Settings page.
///
/// Settled, only the selected page stays mounted. Leaving a section releases
/// its readers, and the shared switcher blocks an outgoing form as soon as
/// another section is chosen.
class SettingsFrame extends StatelessWidget {
  /// Draws [child] beside the menu with [selected] highlighted.
  const SettingsFrame({
    required this.selected,
    required this.onSelected,
    required this.child,
    super.key,
  });

  /// The page shown beside the menu.
  final SettingsSectionId selected;

  /// Chooses another section.
  final ValueChanged<SettingsSectionId> onSelected;

  /// The selected section's page.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = AppTokens.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SizedBox(
          key: const Key('settings_section_menu'),
          width: tokens.settingsMenuWidth,
          child: Panel(
            padding: EdgeInsets.all(tokens.inlineGap),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  for (final SettingsSectionId section
                      in SettingsSectionId.values)
                    _SectionItem(
                      section: section,
                      selected: section == selected,
                      onTap: () => onSelected(section),
                    ),
                ],
              ),
            ),
          ),
        ),
        SizedBox(width: tokens.pageGap),
        Expanded(
          child: RiseSwitcher(
            child: KeyedSubtree(
              key: ValueKey<SettingsSectionId>(selected),
              child: child,
            ),
          ),
        ),
      ],
    );
  }
}

class _SectionItem extends StatefulWidget {
  const _SectionItem({
    required this.section,
    required this.selected,
    required this.onTap,
  });

  final SettingsSectionId section;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_SectionItem> createState() => _SectionItemState();
}

class _SectionItemState extends State<_SectionItem>
    with SingleTickerProviderStateMixin {
  late final AnimationController _selection = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 150),
    value: widget.selected ? 1 : 0,
    // Selection feedback keeps its clock whatever the OS reports.
    animationBehavior: AnimationBehavior.preserve,
  );
  bool _focused = false;

  @override
  void didUpdateWidget(_SectionItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selected != oldWidget.selected) {
      _selection.animateTo(widget.selected ? 1 : 0);
    }
  }

  @override
  void dispose() {
    _selection.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = AppTokens.of(context);
    final BorderRadius radius = BorderRadius.circular(tokens.cardRadius);
    return Semantics(
      selected: widget.selected,
      child: AnimatedBuilder(
        animation: _selection,
        builder: (BuildContext context, Widget? child) {
          final double t = tokens.ease.transform(_selection.value);
          return Material(
            // The preserving controller owns this colour transition.
            animationDuration: Duration.zero,
            color: Color.lerp(
              tokens.card2.withValues(alpha: 0),
              tokens.card2,
              t,
            ),
            borderRadius: radius,
            child: DecoratedBox(
              position: DecorationPosition.foreground,
              decoration: BoxDecoration(
                borderRadius: radius,
                border: Border.all(
                  color: _focused ? tokens.focusRing : Colors.transparent,
                  width: tokens.focusWidth,
                ),
              ),
              child: InkWell(
                key: ValueKey<String>('settings_${widget.section.name}'),
                borderRadius: radius,
                onFocusChange: (bool focused) {
                  if (mounted) setState(() => _focused = focused);
                },
                onTap: widget.onTap,
                child: SizedBox(
                  height: tokens.settingsItemHeight,
                  child: Padding(
                    padding: EdgeInsetsDirectional.symmetric(
                      horizontal: tokens.cardGap,
                    ),
                    child: Row(
                      children: <Widget>[
                        buildShellSymbol(
                          context,
                          widget.section.symbol,
                          size: tokens.settingsIconSize,
                          color: Color.lerp(tokens.dim, tokens.znnInk, t),
                        ),
                        SizedBox(width: tokens.pageGap),
                        Expanded(
                          child: Text(
                            widget.section.label(context),
                            overflow: TextOverflow.ellipsis,
                            style: tokens.bodyText.copyWith(
                              color: Color.lerp(
                                tokens.dim,
                                tokens.foreground,
                                t,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
