import 'dart:math' as math;

import 'package:flutter_svg/flutter_svg.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/extensions/buildcontext_extension.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/entry_field.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/list_entrance.dart';
import 'package:zenon_syrius_wallet_flutter/utils/app_theme.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/reusable_widgets/app_lottie.dart';

/// The three existing onboarding routes, requested without constructing them.
enum WelcomeDestination {
  /// Starts the existing seed-generation flow.
  createWallet,

  /// Opens the existing seed and wallet-file importer.
  importWallet,

  /// Opens the existing hardware-device choice flow.
  hardwareWallet,
}

const double _rowBorderWidth = 1;

const List<LocalKey> _rowKeys = <LocalKey>[
  ValueKey<String>('welcome_create_entrance'),
  ValueKey<String>('welcome_import_entrance'),
  ValueKey<String>('welcome_hardware_entrance'),
];

// Original symbol contents from 00-head.html preserve the entry silhouettes.
const Map<String, String> _symbols = <String, String>{
  'plus': '<path d="M12 5v14M5 12h14"/>',
  'file': '<path d="M6 2h8l6 6v14H6zM14 2v6h6"/>',
  'usb':
      '<rect x="7" y="3" width="10" height="8" rx="1"/> '
      '<path d="M9 11v10h6V11M10 6h1M13 6h1"/>',
  'chevr': '<path d="m9 6 6 6-6 6"/>',
};

/// A welcome view with no wallet, persistence or device owner.
///
/// The caller receives a destination only after this route and the source
/// that drew the row are still current. Artwork can be supplied by finite
/// offline fixtures without mounting the original animation or field.
class WelcomeSurface extends StatefulWidget {
  /// Draws the original globe and the three owned entry actions.
  const WelcomeSurface({
    required this.source,
    required this.onSelected,
    required this.wrapImportDrop,
    this.globe,
    this.background,
    super.key,
  });

  /// Identity of the owner whose actions this view displays.
  final Object source;

  /// The owner constructs a genuine destination only after admission.
  final ValueChanged<WelcomeDestination> onSelected;

  /// The current entry owner supplies the genuine guarded file-drop adapter.
  final Widget Function(Widget) wrapImportDrop;

  /// Replaces the animation inside its measured original composition box.
  final Widget? globe;

  /// Replaces the full-window field without changing the entry layout.
  final Widget? background;

  @override
  State<WelcomeSurface> createState() => _WelcomeSurfaceState();
}

class _WelcomeSurfaceState extends State<WelcomeSurface>
    with WidgetsBindingObserver {
  final FocusNode _barrier = FocusNode(debugLabel: 'Welcome actions');
  Object _generation = Object();
  ModalRoute<dynamic>? _route;
  FocusNode? _parentFocus;
  bool _tickerEnabled = true;
  bool _foreground = true;
  bool _available = false;

  bool get _current =>
      mounted &&
      _foreground &&
      _tickerEnabled &&
      (_route?.isCurrent ?? true) &&
      (_parentFocus?.descendantsAreFocusable ?? true) &&
      (_parentFocus?.ancestors.every(
            (FocusNode node) => node.descendantsAreFocusable,
          ) ??
          true);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final AppLifecycleState? lifecycle = WidgetsBinding.instance.lifecycleState;
    _foreground = lifecycle == null || lifecycle == AppLifecycleState.resumed;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final ModalRoute<dynamic>? route = ModalRoute.of(context);
    if (!identical(_route, route)) _generation = Object();
    _route = route;
    _parentFocus = Focus.maybeOf(context, scopeOk: true);
    _tickerEnabled = TickerMode.valuesOf(context).enabled;
    _refreshAvailability();
  }

  @override
  void didUpdateWidget(WelcomeSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.source, widget.source) ||
        oldWidget.onSelected != widget.onSelected) {
      _generation = Object();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted) return;
    setState(() {
      _foreground = state == AppLifecycleState.resumed;
      _refreshAvailability();
    });
  }

  void _refreshAvailability() {
    final bool next = _current;
    if (next != _available) _generation = Object();
    _available = next;
    if (!next) {
      final Object generation = _generation;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        // Only the hidden branch loses focus. A different route's current
        // control must keep the focus it has just acquired.
        if (mounted &&
            identical(_generation, generation) &&
            !_current &&
            _barrier.hasFocus) {
          _barrier.unfocus();
        }
      });
    }
  }

  VoidCallback _capture(WelcomeDestination destination) {
    final Object generation = _generation;
    final Object source = widget.source;
    final ModalRoute<dynamic>? route = _route;
    final ValueChanged<WelcomeDestination> selected = widget.onSelected;
    return () {
      // A callback saved before a cover, replacement or disposal never
      // constructs a seed, importer or device owner in a later context.
      if (!_current) {
        _generation = Object();
        _available = false;
        return;
      }
      if (!_available ||
          !identical(generation, _generation) ||
          !identical(source, widget.source) ||
          !identical(route, _route) ||
          selected != widget.onSelected) {
        return;
      }
      selected(destination);
    };
  }

  @override
  void deactivate() {
    _generation = Object();
    _available = false;
    super.deactivate();
  }

  @override
  void activate() {
    super.activate();
    _refreshAvailability();
  }

  @override
  void dispose() {
    _generation = Object();
    _available = false;
    WidgetsBinding.instance.removeObserver(this);
    _barrier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = AppTokens.of(context);
    final bool active = _current;
    return Scaffold(
      backgroundColor: tokens.background,
      body: Focus(
        focusNode: _barrier,
        canRequestFocus: false,
        skipTraversal: true,
        descendantsAreFocusable: active,
        descendantsAreTraversable: active,
        child: IgnorePointer(
          ignoring: !active,
          child: ExcludeSemantics(
            excluding: !active,
            child: TickerMode(
              enabled: active,
              child: Stack(
                key: const Key('welcome_screen_marker'),
                fit: StackFit.expand,
                children: <Widget>[
                  widget.background ?? const EntryField(),
                  SafeArea(
                    child: ListEntrance(
                      itemKeys: _rowKeys,
                      child: _buildLayout(context, tokens),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLayout(BuildContext context, AppTokens tokens) => LayoutBuilder(
    builder: (BuildContext context, BoxConstraints constraints) {
      final EdgeInsets inset = tokens.welcomePagePadding.resolve(
        Directionality.of(context),
      );
      final double width = math.max(
        0,
        constraints.maxWidth - inset.horizontal,
      );
      final bool wide =
          width >=
          tokens.welcomeGlobeSize +
              tokens.welcomeColumnGap +
              tokens.welcomeColumnWidth;
      final Widget globe = _buildGlobe(
        tokens,
        wide
            ? tokens.welcomeGlobeSize
            : math.min(width, tokens.welcomeGlobeSize),
      );
      final Widget actions = SizedBox(
        key: const Key('welcome_action_column'),
        width: math.min(width, tokens.welcomeColumnWidth),
        child: _buildActions(context, tokens),
      );
      return SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Padding(
            padding: tokens.welcomePagePadding,
            child: Center(
              child: wide
                  ? Row(
                      key: const Key('welcome_wide_layout'),
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        globe,
                        SizedBox(width: tokens.welcomeColumnGap),
                        actions,
                      ],
                    )
                  : Column(
                      key: const Key('welcome_stacked_layout'),
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        globe,
                        SizedBox(height: tokens.welcomeColumnGap),
                        actions,
                      ],
                    ),
            ),
          ),
        ),
      );
    },
  );

  Widget _buildGlobe(AppTokens tokens, double size) {
    final double scale = size / tokens.welcomeGlobeSize;
    return ExcludeSemantics(
      child: IgnorePointer(
        child: ClipRect(
          child: SizedBox.square(
            key: const Key('welcome_globe_viewport'),
            dimension: size,
            child: OverflowBox(
              minWidth: tokens.welcomeFilmWidth * scale,
              maxWidth: tokens.welcomeFilmWidth * scale,
              minHeight: tokens.welcomeFilmHeight * scale,
              maxHeight: tokens.welcomeFilmHeight * scale,
              child: SizedBox(
                key: const Key('welcome_globe_composition'),
                width: tokens.welcomeFilmWidth * scale,
                height: tokens.welcomeFilmHeight * scale,
                child:
                    widget.globe ??
                    const AppLottie(AppLottieAsset.globe, fit: BoxFit.contain),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildActions(BuildContext context, AppTokens tokens) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: MainAxisSize.min,
    children: <Widget>[
      Text(context.l10n.welcomeTitle, style: tokens.welcomeHeadingText),
      SizedBox(height: tokens.welcomeTextGap),
      Text(context.l10n.welcomeSubtitle, style: tokens.welcomeSubtitleText),
      SizedBox(height: tokens.welcomeTextGap + tokens.welcomeIntroBottomGap),
      Column(
        spacing: tokens.welcomeRowGap,
        children: <Widget>[
          ListEntranceItem(
            key: _rowKeys[0],
            child: _WelcomeAction(
              actionKey: const Key('welcome_create'),
              label: context.l10n.welcomeCreate,
              hint: context.l10n.welcomeCreateHint,
              icon: 'plus',
              primary: true,
              onTap: _capture(WelcomeDestination.createWallet),
            ),
          ),
          ListEntranceItem(
            key: _rowKeys[1],
            child: widget.wrapImportDrop(
              _WelcomeAction(
                actionKey: const Key('welcome_import'),
                label: context.l10n.welcomeImport,
                hint: context.l10n.welcomeImportHint,
                icon: 'file',
                onTap: _capture(WelcomeDestination.importWallet),
              ),
            ),
          ),
          ListEntranceItem(
            key: _rowKeys[2],
            child: _WelcomeAction(
              actionKey: const Key('welcome_hardware'),
              label: context.l10n.welcomeHardware,
              hint: context.l10n.welcomeHardwareHint,
              icon: 'usb',
              onTap: _capture(WelcomeDestination.hardwareWallet),
            ),
          ),
        ],
      ),
      SizedBox(height: tokens.welcomeTextGap + tokens.welcomeFooterTopGap),
      Text(context.l10n.welcomeSettingsHint, style: tokens.welcomeFooterText),
    ],
  );
}

class _WelcomeAction extends StatefulWidget {
  const _WelcomeAction({
    required this.actionKey,
    required this.label,
    required this.hint,
    required this.icon,
    required this.onTap,
    this.primary = false,
  });

  final Key actionKey;
  final String label;
  final String hint;
  final String icon;
  final VoidCallback onTap;
  final bool primary;

  @override
  State<_WelcomeAction> createState() => _WelcomeActionState();
}

class _WelcomeActionState extends State<_WelcomeAction> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = AppTokens.of(context);
    final BorderRadius radius = BorderRadius.circular(tokens.cardRadius);
    return Semantics(
      button: true,
      child: Material(
        color: tokens.card,
        borderRadius: radius,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: widget.actionKey,
          onTap: widget.onTap,
          mouseCursor: SystemMouseCursors.click,
          borderRadius: radius,
          hoverColor: tokens.hover,
          focusColor: Colors.transparent,
          onFocusChange: (bool focused) => setState(() => _focused = focused),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: tokens.welcomeRowHeight),
            child: AnimatedContainer(
              duration: tokens.welcomeStateDuration,
              curve: tokens.ease,
              // The reference border occupies layout space as well as paint.
              // Keep its inset fixed when the focus ring changes its width.
              padding: tokens.welcomeRowPadding.add(
                const EdgeInsets.all(_rowBorderWidth),
              ),
              foregroundDecoration: BoxDecoration(
                borderRadius: radius,
                border: Border.all(
                  color: _focused ? tokens.focusRing : tokens.line,
                  width: _focused ? tokens.focusWidth : _rowBorderWidth,
                ),
              ),
              child: Row(
                children: <Widget>[
                  Container(
                    width: tokens.welcomeIconSize,
                    height: tokens.welcomeIconSize,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: widget.primary ? null : tokens.card2,
                      gradient: widget.primary ? tokens.plasma : null,
                    ),
                    child: Center(
                      child: _WelcomeSymbol(
                        symbol: widget.icon,
                        size: tokens.welcomeGlyphSize,
                        color: widget.primary ? tokens.onZnn : tokens.dim,
                      ),
                    ),
                  ),
                  SizedBox(width: tokens.welcomeIconGap),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(widget.label, style: tokens.welcomeActionText),
                        Text(widget.hint, style: tokens.welcomeHintText),
                      ],
                    ),
                  ),
                  SizedBox(width: tokens.welcomeIconGap),
                  _WelcomeSymbol(
                    symbol: 'chevr',
                    color: tokens.faint,
                    size: tokens.welcomeChevronSize,
                    directional: true,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _WelcomeSymbol extends StatelessWidget {
  const _WelcomeSymbol({
    required this.symbol,
    required this.size,
    required this.color,
    this.directional = false,
  });

  final String symbol;
  final double size;
  final Color color;
  final bool directional;

  @override
  Widget build(BuildContext context) => SvgPicture.string(
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" '
    'fill="none" stroke="currentColor" stroke-width="1.8" '
    'stroke-linecap="round" stroke-linejoin="round">${_symbols[symbol]}</svg>',
    width: size,
    height: size,
    colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
    matchTextDirection: directional,
    excludeFromSemantics: true,
  );
}
