import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/main.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/extensions/buildcontext_extension.dart';
import 'package:zenon_syrius_wallet_flutter/utils/app_theme.dart';
import 'package:zenon_syrius_wallet_flutter/utils/constants.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/shell/tabs.dart';

// Canonical symbol contents from 00-head.html. Their original paths keep
// the silhouette and stroke consistent between the rail and Settings.
const Map<String, String> _symbols = <String, String>{
  'home':
      '<path d="M3 11 12 3l9 8v9a1 1 0 0 1-1 1h-5v-6H9v6H4a1 1 0 0 1-1-1z"/>',
  'send': '<path d="M22 2 11 13M22 2l-7 20-4-9-9-4z"/>',
  'up': '<path d="M12 19V5M5 12l7-7 7 7"/>',
  'down': '<path d="M12 5v14M19 12l-7 7-7-7"/>',
  'copy':
      '<rect x="9" y="9" width="12" height="12" rx="2"/><path d="M5 15V5a2 2 0 0 1 2-2h10"/>',
  'dl': '<path d="M12 3v12M7 10l5 5 5-5M4 21h16"/>',
  'refresh':
      '<path d="M3 12a9 9 0 0 1 15-6.7L21 8M21 3v5h-5M21 '
      '12a9 9 0 0 1-15 6.7L3 16M3 21v-5h5"/>',
  'trash': '<path d="M4 7h16M9 7V4h6v3M6 7l1 13h10l1-13M10 11v6M14 11v6"/>',
  'coins': '<circle cx="9" cy="9" r="6"/><path d="M15.5 9.5a6 6 0 1 1-6 6"/>',
  'stack': '<path d="m12 3 9 5-9 5-9-5zM3 13l9 5 9-5M3 18l9 5 9-5"/>',
  'zap': '<path d="M13 2 4 14h7l-1 8 9-12h-7z"/>',
  'token': '<circle cx="12" cy="12" r="9"/><circle cx="12" cy="12" r="3.5"/>',
  'swap': '<path d="M7 4 3 8l4 4M3 8h14M17 12l4 4-4 4M21 16H7"/>',
  'rocket':
      '<path d="M12 2c4 3 5 8 4 13H8C7 10 8 5 12 2zM8 15l-3 3 '
      '3 1M16 15l3 3-3 1M12 19v3"/>',
  'bell':
      '<path d="M6 8a6 6 0 0 1 12 0c0 7 3 8 3 8H3s3-1 3-8M10 '
      '20a2 2 0 0 0 4 0"/>',
  'gear':
      '<circle cx="12" cy="12" r="3"/><path d="M12 2v3M12 19v3M2 12h3M19 12h3M4.9 4.9l2.1 2.1M17 17l2.1 2.1M4.9 19.1 7 17M17 7l2.1-2.1"/>',
  'lock':
      '<rect x="4" y="11" width="16" height="10" rx="2"/><path d="M8 11V7a4 4 0 0 1 8 0v4"/>',
  'link':
      '<path d="M10 14a5 5 0 0 0 7 0l3-3a5 5 0 0 0-7-7l-1 1M14 '
      '10a5 5 0 0 0-7 0l-3 3a5 5 0 0 0 7 7l1-1"/>',
  'chevr': '<path d="m9 6 6 6-6 6"/>',
  'shield': '<path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z"/>',
  'eye':
      '<path d="M2 12s4-7 10-7 10 7 10 7-4 7-10 7S2 12 2 12z"/><circle cx="12" cy="12" r="3"/>',
  'book':
      '<path d="M4 4h12a3 3 0 0 1 3 3v13H7a3 3 0 0 0-3 3zM4 '
      '4v16M19 16H7a3 3 0 0 0-3 3"/>',
  'info': '<circle cx="12" cy="12" r="9"/><path d="M12 11v5M12 8h.01"/>',
  'globe':
      '<circle cx="12" cy="12" r="9"/><path d="M3 12h18M12 3a14 14 0 0 1 0 18M12 3a14 14 0 0 0 0 18"/>',
};

/// Draws an original shell symbol for the rail or Settings section menu.
Widget buildShellSymbol(
  BuildContext context,
  String symbol, {
  Color? color,
  double? size,
  bool directional = false,
}) {
  final AppTokens tokens = AppTokens.of(context);
  final String? contents = _symbols[symbol];
  if (contents == null) {
    throw ArgumentError.value(symbol, 'symbol', 'Unknown shell symbol');
  }
  return SvgPicture.string(
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" '
    'fill="none" stroke="currentColor" stroke-width="1.8" '
    'stroke-linecap="round" stroke-linejoin="round">$contents</svg>',
    width: size ?? tokens.railIconSize,
    height: size ?? tokens.railIconSize,
    colorFilter: ColorFilter.mode(color ?? tokens.dim, BlendMode.srcIn),
    matchTextDirection: directional,
    excludeFromSemantics: true,
  );
}

String get _chordName =>
    defaultTargetPlatform == TargetPlatform.macOS ? 'Cmd' : 'Ctrl';

/// A tooltip beside its item, towards the page, avoids covering the next row.
TooltipPositionDelegate _railTooltipBeside(
  TextDirection direction,
  double gap,
) => (TooltipPositionContext context) {
  final double reach = context.targetSize.width / 2 + gap;
  final double top = context.target.dy - context.tooltipSize.height / 2;
  final double lowest = math.max(
    0,
    context.overlaySize.height - context.tooltipSize.height,
  );
  return Offset(
    direction == TextDirection.ltr
        ? context.target.dx + reach
        : context.target.dx - reach - context.tooltipSize.width,
    top.clamp(0.0, lowest),
  );
};

/// One destination, with stable metadata for the shell's shortcut palette.
class RailEntry {
  /// Creates an entry for [tab].
  const RailEntry(this.tab, this.label, this.icon);

  /// The existing identifier, also used in harness selectors.
  final Tabs tab;

  /// The English source label. Render [localizedLabel] in the interface.
  final String label;

  /// Material metadata for existing consumers. [buildIcon] draws the source
  /// mockup's glyph in the rail and in new consumers.
  final IconData icon;

  /// The destination's name in the current locale.
  String localizedLabel(BuildContext context) => switch (tab) {
    Tabs.dashboard => context.l10n.railHome,
    Tabs.transfer => context.l10n.transfer,
    Tabs.staking => context.l10n.railStaking,
    Tabs.pillars || Tabs.sentinels => context.l10n.railNodes,
    Tabs.plasma => context.l10n.plasma,
    Tabs.tokens => context.l10n.tokens,
    Tabs.p2pSwap => context.l10n.railSwap,
    Tabs.accelerator => context.l10n.railAccelerator,
    Tabs.notifications => context.l10n.railNotifications,
    Tabs.settings => context.l10n.railSettings,
    Tabs.lock =>
      label == 'Locked' ? context.l10n.railLocked : context.l10n.railLock,
    _ => label,
  };

  /// Draws the original glyph without a second accessible name.
  Widget buildIcon(BuildContext context, {Color? color}) {
    final AppTokens tokens = AppTokens.of(context);
    final String? symbol = switch (tab) {
      Tabs.dashboard => 'home',
      Tabs.transfer => 'send',
      Tabs.staking => 'coins',
      Tabs.pillars || Tabs.sentinels => 'stack',
      Tabs.plasma => 'zap',
      Tabs.tokens => 'token',
      Tabs.p2pSwap => 'swap',
      Tabs.accelerator => 'rocket',
      Tabs.notifications => 'bell',
      Tabs.settings => 'gear',
      Tabs.lock => 'lock',
      Tabs.walletConnect => 'link',
      _ => null,
    };
    return symbol == null
        ? Icon(icon, size: tokens.railIconSize, color: color ?? tokens.dim)
        : buildShellSymbol(context, symbol, color: color);
  }
}

/// The eight pages, in the order of their number shortcuts.
const List<RailEntry> kRailPages = <RailEntry>[
  RailEntry(Tabs.dashboard, 'Home', Icons.home_outlined),
  RailEntry(Tabs.transfer, 'Transfer', Icons.send_outlined),
  RailEntry(Tabs.staking, 'Staking', Icons.savings_outlined),
  RailEntry(Tabs.pillars, 'Nodes', Icons.layers_outlined),
  RailEntry(Tabs.plasma, 'Plasma', Icons.bolt_outlined),
  RailEntry(Tabs.tokens, 'Tokens', Icons.toll_outlined),
  RailEntry(Tabs.p2pSwap, 'Swap', Icons.swap_horiz),
  RailEntry(Tabs.accelerator, 'Accelerator', Icons.rocket_launch_outlined),
];

/// The footer. Connected sites is reached through Settings > Apps.
List<RailEntry> railWalletEntries({required bool onLock}) => <RailEntry>[
  const RailEntry(
    Tabs.notifications,
    'Notifications',
    Icons.notifications_outlined,
  ),
  const RailEntry(Tabs.settings, 'Settings', Icons.settings_outlined),
  RailEntry(Tabs.lock, onLock ? 'Locked' : 'Lock', Icons.lock_outline),
];

/// The profile's choice, shared by the toggle, shortcut and Display setting.
/// Without an open preferences service the choice lasts in memory.
class RailCollapse extends ValueNotifier<bool> {
  /// Starts collapsed when no valid choice has been stored.
  RailCollapse() : super(_stored());

  static bool _stored() {
    try {
      final Object? stored = sharedPrefsService?.get(kRailCollapsedKey);
      return stored is! bool || stored;
    } on Object {
      // A service can exist before its box is open.
      return true;
    }
  }

  /// Opens a collapsed rail and closes an open one.
  void toggle() => setCollapsed(collapsed: !value);

  /// Stores an explicit choice made by the toggle or Display setting.
  void setCollapsed({required bool collapsed}) {
    if (value == collapsed) return;
    value = collapsed;
    unawaited(_store(collapsed));
  }

  static Future<void> _store(bool collapsed) async {
    try {
      await sharedPrefsService?.put(kRailCollapsedKey, collapsed);
    } on Object {
      // A closed box must not break navigation. This choice remains in
      // memory until the profile next opens its stored preferences.
    }
  }
}

/// Opening finishes the width movement before the labels fade in, so a
/// moving edge never cuts through visible text.
class ShellRail extends StatefulWidget {
  /// Creates the rail around the shell-owned choice and navigation.
  const ShellRail({
    required this.collapse,
    required this.selected,
    required this.locked,
    required this.onSelected,
    this.onNotifications,
    this.hasUnseen = false,
    super.key,
  });

  /// Whether the rail is collapsed.
  final RailCollapse collapse;

  /// The selected page. Legacy Sentinels navigation also selects Nodes.
  final Tabs selected;

  /// Removes pointer, keyboard and accessibility access to navigation.
  final bool locked;

  /// Opens an existing destination.
  final ValueChanged<Tabs> onSelected;

  /// Opens the bell panel when supplied; otherwise opens Notifications.
  final VoidCallback? onNotifications;

  /// Whether the bell carries the unseen marker.
  final bool hasUnseen;

  @override
  State<ShellRail> createState() => _ShellRailState();
}

class _ShellRailState extends State<ShellRail> with TickerProviderStateMixin {
  // Preserve keeps the complete motion on systems whose accessibility
  // preference otherwise shortens controllers to a twentieth.
  late final AnimationController _width = AnimationController(
    vsync: this,
    value: 1,
    animationBehavior: AnimationBehavior.preserve,
  );
  late double _widthStart = widget.collapse.value ? 0 : 1;
  late double _widthEnd = _widthStart;
  late final AnimationController _labels = AnimationController(
    vsync: this,
    value: widget.collapse.value ? 0 : 1,
    animationBehavior: AnimationBehavior.preserve,
  );
  late final Listenable _motion = Listenable.merge(<Listenable>[
    _width,
    _labels,
  ]);

  @override
  void initState() {
    super.initState();
    _width.addStatusListener(_followWidth);
    widget.collapse.addListener(_followChoice);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final AppTokens tokens = AppTokens.of(context);
    _width.duration = tokens.railWidthDuration;
    _labels.duration = tokens.railLabelDuration;
  }

  @override
  void didUpdateWidget(ShellRail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.collapse != widget.collapse) {
      oldWidget.collapse.removeListener(_followChoice);
      widget.collapse.addListener(_followChoice);
      _followChoice();
    }
  }

  void _followWidth(AnimationStatus status) {
    if (status == AnimationStatus.completed &&
        _widthEnd == 1 &&
        !widget.collapse.value) {
      _labels.forward();
    }
  }

  double _expansion(AppTokens tokens) =>
      _widthStart +
      (_widthEnd - _widthStart) * tokens.spring.transform(_width.value);

  void _followChoice() {
    // Text leaves before a closing edge moves. Reversing an interrupted
    // opening never exposes a fragment of a label.
    _labels
      ..stop()
      ..value = 0;
    _widthStart = _expansion(AppTokens.of(context));
    _widthEnd = widget.collapse.value ? 0 : 1;
    setState(() {});
    if (_widthStart == _widthEnd) {
      _width.value = 1;
      if (_widthEnd == 1) _labels.forward();
    } else {
      // Each direction uses the spring from its own starting width.
      _width.forward(from: 0);
    }
  }

  @override
  void dispose() {
    widget.collapse.removeListener(_followChoice);
    _width.removeStatusListener(_followWidth);
    _width.dispose();
    _labels.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = AppTokens.of(context);
    return AnimatedBuilder(
      animation: _motion,
      builder: (BuildContext context, Widget? child) {
        final double expansion = _expansion(tokens);
        return SizedBox(
          width:
              tokens.railCollapsedWidth +
              (tokens.railExpandedWidth - tokens.railCollapsedWidth) *
                  expansion,
          child: _Rail(
            selected: widget.selected == Tabs.sentinels
                ? Tabs.pillars
                : widget.selected,
            locked: widget.locked,
            onSelected: widget.onSelected,
            onNotifications: widget.onNotifications,
            hasUnseen: widget.hasUnseen,
            collapsed: widget.collapse.value,
            expansion: expansion,
            labelsVisible: _width.isCompleted && !widget.collapse.value,
            labelOpacity: tokens.ease.transform(_labels.value),
            onToggle: widget.collapse.toggle,
          ),
        );
      },
    );
  }
}

class _Rail extends StatelessWidget {
  const _Rail({
    required this.selected,
    required this.locked,
    required this.onSelected,
    required this.onNotifications,
    required this.hasUnseen,
    required this.collapsed,
    required this.expansion,
    required this.labelsVisible,
    required this.labelOpacity,
    required this.onToggle,
  });

  final Tabs selected;
  final bool locked;
  final ValueChanged<Tabs> onSelected;
  final VoidCallback? onNotifications;
  final bool hasUnseen;
  final bool collapsed;
  final double expansion;
  final bool labelsVisible;
  final double labelOpacity;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = AppTokens.of(context);
    final List<RailEntry> wallet = railWalletEntries(
      onLock: selected == Tabs.lock,
    );
    return ExcludeFocus(
      excluding: locked,
      child: ExcludeSemantics(
        excluding: locked,
        child: IgnorePointer(
          ignoring: locked,
          child: Opacity(
            opacity: locked ? tokens.disabledOpacity : 1,
            child: Padding(
              padding: tokens.railPadding,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  _RailButton(
                    hitKey: const ValueKey<String>('rail_toggle'),
                    iconKey: const ValueKey<String>('rail_icon_toggle'),
                    buildIcon: (BuildContext context, Color color) =>
                        Transform.rotate(
                          angle: math.pi * expansion,
                          child: buildShellSymbol(
                            context,
                            'chevr',
                            color: color,
                            directional: true,
                          ),
                        ),
                    name: collapsed
                        ? context.l10n.railExpand
                        : context.l10n.railCollapse,
                    shortcut: '$_chordName B',
                    height: tokens.railToggleHeight,
                    labelled: false,
                    labelOpacity: 0,
                    quiet: true,
                    onTap: () {
                      if (!locked) onToggle();
                    },
                  ),
                  SizedBox(height: tokens.railItemGap),
                  for (int i = 0; i < kRailPages.length; i++) ...<Widget>[
                    _buildItem(context, kRailPages[i], '$_chordName ${i + 1}'),
                    SizedBox(height: tokens.railItemGap),
                  ],
                  const Spacer(),
                  for (int i = 0; i < wallet.length; i++) ...<Widget>[
                    _buildItem(
                      context,
                      wallet[i],
                      switch (wallet[i].tab) {
                        Tabs.settings => '$_chordName ,',
                        Tabs.lock => '$_chordName L',
                        _ => null,
                      },
                    ),
                    if (i < wallet.length - 1)
                      SizedBox(height: tokens.railItemGap),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildItem(BuildContext context, RailEntry entry, String? shortcut) {
    return _RailButton(
      hitKey: ValueKey<String>('nav_${entry.tab.name}'),
      iconKey: ValueKey<String>('rail_icon_${entry.tab.name}'),
      labelKey: ValueKey<String>('rail_label_${entry.tab.name}'),
      buildIcon: (BuildContext context, Color color) =>
          entry.buildIcon(context, color: color),
      name: entry.localizedLabel(context),
      shortcut: shortcut,
      height: AppTokens.of(context).railItemHeight,
      labelled: labelsVisible,
      labelOpacity: labelOpacity,
      selected: entry.tab == selected,
      hasUnseen: entry.tab == Tabs.notifications && hasUnseen,
      onTap: () {
        if (locked) return;
        if (entry.tab == Tabs.notifications && onNotifications != null) {
          onNotifications!();
        } else {
          onSelected(entry.tab);
        }
      },
    );
  }
}

class _RailButton extends StatefulWidget {
  const _RailButton({
    required this.hitKey,
    required this.iconKey,
    required this.buildIcon,
    required this.name,
    required this.shortcut,
    required this.height,
    required this.labelled,
    required this.labelOpacity,
    required this.onTap,
    this.labelKey,
    this.selected = false,
    this.hasUnseen = false,
    this.quiet = false,
  });

  final Key hitKey;
  final Key iconKey;
  final Key? labelKey;
  final Widget Function(BuildContext, Color) buildIcon;
  final String name;
  final String? shortcut;
  final double height;
  final bool labelled;
  final double labelOpacity;
  final bool selected;
  final bool hasUnseen;
  final bool quiet;
  final VoidCallback onTap;

  @override
  State<_RailButton> createState() => _RailButtonState();
}

class _RailButtonState extends State<_RailButton>
    with SingleTickerProviderStateMixin {
  bool _hovered = false;
  bool _focused = false;
  bool _hasAppearance = false;
  final ColorTween _icon = ColorTween();
  final ColorTween _text = ColorTween();
  final ColorTween _fill = ColorTween();

  late final AnimationController _appearance = AnimationController(
    vsync: this,
    value: 1,
    animationBehavior: AnimationBehavior.preserve,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _appearance.duration = AppTokens.of(context).railLabelDuration;
    _retarget();
  }

  @override
  void didUpdateWidget(_RailButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selected != widget.selected ||
        oldWidget.quiet != widget.quiet) {
      _retarget();
    }
  }

  Color _color(ColorTween tween) {
    final double t = AppTokens.of(context).ease.transform(_appearance.value);
    return Color.lerp(tween.begin, tween.end, t)!;
  }

  void _retarget() {
    final AppTokens tokens = AppTokens.of(context);
    final Color ink = widget.quiet ? tokens.faint : tokens.dim;
    final Color icon = widget.selected
        ? tokens.znnInk
        : _hovered
        ? tokens.foreground
        : ink;
    final Color text = widget.selected || _hovered ? tokens.foreground : ink;
    final Color fill = widget.selected ? tokens.card : Colors.transparent;
    _icon
      ..begin = _hasAppearance ? _color(_icon) : icon
      ..end = icon;
    _text
      ..begin = _hasAppearance ? _color(_text) : text
      ..end = text;
    _fill
      ..begin = _hasAppearance ? _color(_fill) : fill
      ..end = fill;
    if (_hasAppearance) {
      _appearance.forward(from: 0);
    }
    _hasAppearance = true;
  }

  @override
  void dispose() {
    _appearance.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = AppTokens.of(context);
    final String tooltip = widget.shortcut == null
        ? widget.name
        : '${widget.name}  ${widget.shortcut}';
    return AnimatedBuilder(
      animation: _appearance,
      builder: (BuildContext context, Widget? child) => Semantics(
        container: true,
        button: true,
        enabled: true,
        selected: widget.selected,
        focused: _focused,
        label: widget.name,
        hint: widget.shortcut,
        value: widget.hasUnseen ? context.l10n.railUnseen : null,
        onTap: widget.onTap,
        child: ExcludeSemantics(
          child: TooltipVisibility(
            visible: !widget.labelled || widget.labelOpacity == 0,
            child: Tooltip(
              richMessage: TextSpan(
                text: '',
                semanticsLabel: tooltip,
                style: tokens.railTooltipText,
                children: <InlineSpan>[
                  TextSpan(text: widget.name),
                  if (widget.shortcut != null)
                    WidgetSpan(
                      alignment: PlaceholderAlignment.middle,
                      child: Padding(
                        padding: EdgeInsetsDirectional.only(
                          start: tokens.inlineGap,
                        ),
                        child: Directionality(
                          textDirection: TextDirection.ltr,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              border: Border.all(color: tokens.line),
                              borderRadius: BorderRadius.circular(
                                tokens.keyboardHintRadius,
                              ),
                            ),
                            child: Padding(
                              padding: tokens.keyboardHintPadding,
                              child: Text(
                                widget.shortcut!,
                                style: tokens.keyboardHintText,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              padding: tokens.railTooltipPadding,
              textStyle: tokens.railTooltipText,
              decoration: BoxDecoration(
                color: tokens.card3,
                border: Border.all(color: tokens.line),
                borderRadius: BorderRadius.circular(tokens.compactRadius),
                boxShadow: <BoxShadow>[tokens.tooltipShadow],
              ),
              excludeFromSemantics: true,
              positionDelegate: _railTooltipBeside(
                Directionality.of(context),
                tokens.cardGap,
              ),
              child: Material(
                type: MaterialType.transparency,
                child: InkWell(
                  key: widget.hitKey,
                  borderRadius: BorderRadius.circular(tokens.cardRadius),
                  hoverColor: Colors.transparent,
                  focusColor: Colors.transparent,
                  splashFactory: NoSplash.splashFactory,
                  onHover: (bool hovered) {
                    _hovered = hovered;
                    _retarget();
                  },
                  onFocusChange: (bool focused) {
                    if (mounted) setState(() => _focused = focused);
                  },
                  onTap: widget.onTap,
                  child: DecoratedBox(
                    // A decoration makes the whole row hittable, including
                    // the empty middle of a row that shows only an icon.
                    position: DecorationPosition.foreground,
                    decoration: BoxDecoration(
                      border: _focused
                          ? Border.all(
                              color: tokens.focusRing,
                              width: tokens.focusWidth,
                            )
                          : null,
                      borderRadius: BorderRadius.circular(tokens.cardRadius),
                    ),
                    child: SizedBox(
                      height: widget.height,
                      child: DecoratedBox(
                        key: widget.selected ? const Key('rail_pill') : null,
                        decoration: BoxDecoration(
                          color: _color(_fill),
                          borderRadius: BorderRadius.circular(
                            tokens.cardRadius,
                          ),
                        ),
                        child: Stack(
                          children: <Widget>[
                            Positioned.fill(
                              child: Padding(
                                padding: EdgeInsetsDirectional.symmetric(
                                  horizontal: tokens.railItemInset,
                                ),
                                child: Row(
                                  children: <Widget>[
                                    SizedBox(
                                      key: widget.iconKey,
                                      width: tokens.railIconSize,
                                      height: tokens.railIconSize,
                                      child: widget.buildIcon(
                                        context,
                                        _color(_icon),
                                      ),
                                    ),
                                    if (widget.labelled) ...<Widget>[
                                      SizedBox(width: tokens.railLabelGap),
                                      Expanded(
                                        child: Opacity(
                                          opacity: widget.labelOpacity,
                                          child: Text(
                                            widget.name,
                                            key: widget.labelKey,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: tokens.bodyText.copyWith(
                                              color: _color(_text),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                            if (widget.hasUnseen)
                              PositionedDirectional(
                                start:
                                    tokens.railDotStart -
                                    tokens.railDotRingWidth,
                                top:
                                    tokens.railDotTop - tokens.railDotRingWidth,
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: tokens.background,
                                  ),
                                  child: Padding(
                                    padding: EdgeInsets.all(
                                      tokens.railDotRingWidth,
                                    ),
                                    child: SizedBox(
                                      key: const ValueKey<String>(
                                        'rail_unseen_dot',
                                      ),
                                      width: tokens.railDotSize,
                                      height: tokens.railDotSize,
                                      child: DecoratedBox(
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: tokens.pink,
                                        ),
                                      ),
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
              ),
            ),
          ),
        ),
      ),
    );
  }
}
