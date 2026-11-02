import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/extensions/buildcontext_extension.dart';
import 'package:zenon_syrius_wallet_flutter/utils/app_theme.dart';
import 'package:zenon_syrius_wallet_flutter/utils/wallet_ready_binding.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/reusable_widgets/app_lottie.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/reusable_widgets/buttons/primary_pill.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/reusable_widgets/modals/frosted_route.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/reusable_widgets/modals/modal_chrome.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/shell/rail.dart';

/// The final entry view. It owns no wallet, file, service or initializer.
class WalletReadySurface extends StatefulWidget {
  /// Draws the original map behind the one successful wallet's glass card.
  const WalletReadySurface({
    required this.binding,
    required this.onOpen,
    required this.onCopy,
    this.map,
    this.hardware = false,
    this.imported = false,
    super.key,
  });

  /// Absent when original initialization has not positively completed.
  final WalletReadyBinding? binding;

  /// Receives a once-reserved opening of that original wallet.
  final VoidCallback onOpen;

  /// Copies only the immutable first address displayed by this card.
  final ValueChanged<String> onCopy;

  /// Finite offline fixtures can replace the genuine artwork here.
  final Widget? map;

  /// Hardware setup has no seed confirmation step to claim completed.
  final bool hardware;

  /// An import completed password setup without a seed confirmation quiz.
  final bool imported;

  @override
  State<WalletReadySurface> createState() => _WalletReadySurfaceState();
}

class _WalletReadySurfaceState extends State<WalletReadySurface>
    with WidgetsBindingObserver {
  ModalRoute<dynamic>? _route;
  Object _generation = Object();
  bool _foreground = true;
  bool _visible = false;
  bool _ticker = true;
  bool _currentRoute = true;

  bool get _available =>
      mounted &&
      _foreground &&
      _ticker &&
      _currentRoute &&
      (_route?.isCurrent ?? true) &&
      (widget.binding?.isCurrent ?? false);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final AppLifecycleState? state = WidgetsBinding.instance.lifecycleState;
    _foreground = state == null || state == AppLifecycleState.resumed;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final ModalRoute<dynamic>? route = ModalRoute.of(context);
    if (!identical(_route, route)) _generation = Object();
    _route = route;
    _currentRoute = ModalRoute.isCurrentOf(context) ?? true;
    _ticker = TickerMode.valuesOf(context).enabled;
    _syncVisibility();
  }

  void _syncVisibility() {
    final bool next = _available;
    if (_visible != next) _generation = Object();
    _visible = next;
  }

  @override
  void didUpdateWidget(WalletReadySurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.binding, widget.binding) ||
        oldWidget.onOpen != widget.onOpen ||
        oldWidget.onCopy != widget.onCopy) {
      _generation = Object();
    }
    _syncVisibility();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted) return;
    setState(() {
      _foreground = state == AppLifecycleState.resumed;
      _syncVisibility();
    });
  }

  VoidCallback _capture({required bool opening}) {
    final Object generation = _generation;
    final WalletReadyBinding? binding = widget.binding;
    final ModalRoute<dynamic>? route = _route;
    final VoidCallback open = widget.onOpen;
    final ValueChanged<String> copy = widget.onCopy;
    return () {
      if (!_available) {
        _generation = Object();
        _visible = false;
        return;
      }
      if (!_visible ||
          !identical(generation, _generation) ||
          !identical(binding, widget.binding) ||
          !identical(route, _route) ||
          open != widget.onOpen ||
          copy != widget.onCopy ||
          binding == null) {
        return;
      }
      if (opening) {
        if (!binding.takeOpening()) return;
        setState(_syncVisibility);
        open();
      } else {
        copy(binding.firstAddress);
      }
    };
  }

  @override
  void deactivate() {
    _generation = Object();
    _visible = false;
    super.deactivate();
  }

  @override
  void activate() {
    super.activate();
    _syncVisibility();
  }

  @override
  void dispose() {
    _generation = Object();
    _visible = false;
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = AppTokens.of(context);
    final bool available = _available;
    final String? address = widget.binding?.firstAddress;
    return Scaffold(
      backgroundColor: tokens.background,
      body: Stack(
        key: const Key('wallet_ready_screen_marker'),
        fit: StackFit.expand,
        children: <Widget>[
          ExcludeSemantics(
            child: IgnorePointer(
              child: RepaintBoundary(
                key: const Key('wallet_ready_map'),
                child:
                    widget.map ??
                    const AppLottie(AppLottieAsset.map, fit: BoxFit.cover),
              ),
            ),
          ),
          SafeArea(
            child: LayoutBuilder(
              builder: (BuildContext context, BoxConstraints bounds) {
                return SingleChildScrollView(
                  padding: tokens.lockPagePadding,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: math.max(
                        0,
                        bounds.maxHeight - tokens.lockPagePadding.vertical,
                      ),
                    ),
                    child: Center(
                      child: SizedBox(
                        width: tokens.readyCardWidth,
                        child: RiseIn(
                          duration: const Duration(milliseconds: 320),
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(
                                tokens.dialogRadius,
                              ),
                              boxShadow: tokens.lockCardShadow,
                            ),
                            child: FrostedSurface(
                              sigma: tokens.dialogBlur,
                              child: DecoratedBox(
                                key: const Key('wallet_ready_card'),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(
                                    tokens.dialogRadius,
                                  ),
                                  border: Border.all(color: tokens.line),
                                ),
                                child: Padding(
                                  padding: tokens.readyCardPadding,
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: <Widget>[
                                      _buildSteps(context, tokens),
                                      SizedBox(
                                        height:
                                            tokens.readyGap +
                                            tokens.readyTitleGap,
                                      ),
                                      Text(
                                        context.l10n.walletReadyTitle,
                                        textAlign: TextAlign.center,
                                        style: tokens.readyTitleText,
                                      ),
                                      SizedBox(height: tokens.readyGap),
                                      Text(
                                        context.l10n.walletReadyFirstAddress,
                                        style: tokens.ledgerText,
                                        textAlign: TextAlign.center,
                                      ),
                                      SizedBox(height: tokens.readyAddressGap),
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: <Widget>[
                                          Flexible(
                                            child: _ReadyAddress(
                                              address:
                                                  address ??
                                                  context
                                                      .l10n
                                                      .walletReadyUnknown,
                                              style: tokens.readyAddressText,
                                            ),
                                          ),
                                          if (address != null)
                                            IconButton(
                                              key: const Key(
                                                'wallet_ready_copy',
                                              ),
                                              tooltip:
                                                  context.l10n.walletReadyCopy,
                                              onPressed: available
                                                  ? _capture(opening: false)
                                                  : null,
                                              constraints: const BoxConstraints(
                                                minWidth: 32,
                                                minHeight: 32,
                                              ),
                                              icon: buildShellSymbol(
                                                context,
                                                'copy',
                                                size: tokens.lockGlyphSize,
                                              ),
                                            ),
                                        ],
                                      ),
                                      SizedBox(
                                        height:
                                            tokens.readyGap +
                                            tokens.readyAddressGap,
                                      ),
                                      PrimaryPill(
                                        key: const Key('wallet_ready_open'),
                                        onPressed: available
                                            ? _capture(opening: true)
                                            : null,
                                        style: OutlinedButton.styleFrom(
                                          minimumSize: Size(
                                            0,
                                            tokens.lockActionHeight,
                                          ),
                                          textStyle: tokens.lockActionText,
                                        ),
                                        child: Text(
                                          context.l10n.walletReadyOpen,
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
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSteps(BuildContext context, AppTokens tokens) {
    final List<String> labels = widget.hardware
        ? <String>[
            context.l10n.walletReadyDevice,
            context.l10n.walletReadyPassword,
            context.l10n.walletReadyReady,
          ]
        : widget.imported
        ? <String>[
            context.l10n.importSeedOrFile,
            context.l10n.walletReadyPassword,
            context.l10n.walletReadyReady,
          ]
        : <String>[
            context.l10n.walletReadySeed,
            context.l10n.walletReadyConfirm,
            context.l10n.walletReadyPassword,
            context.l10n.walletReadyReady,
          ];
    return Wrap(
      key: const Key('wallet_ready_steps'),
      alignment: WrapAlignment.center,
      spacing: tokens.readyStepGap,
      runSpacing: tokens.readyAddressGap,
      children: <Widget>[
        for (final String label in labels)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                Icons.check_circle_outline,
                size: tokens.lockGlyphSize,
                color: tokens.znn,
              ),
              SizedBox(width: tokens.readyAddressGap),
              Text(
                label,
                style: tokens.bodyText.copyWith(
                  fontSize: 12,
                  color: tokens.dim,
                ),
              ),
            ],
          ),
      ],
    );
  }
}

class _ReadyAddress extends StatelessWidget {
  const _ReadyAddress({required this.address, required this.style});
  final String address;
  final TextStyle style;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: address,
    child: LayoutBuilder(
      builder: (BuildContext context, BoxConstraints bounds) {
        final TextPainter measure = TextPainter(
          text: TextSpan(text: address, style: style),
          textDirection: TextDirection.ltr,
          textScaler: MediaQuery.textScalerOf(context),
        )..layout();
        final String shown =
            measure.width <= bounds.maxWidth || address.length < 26
            ? address
            : address.replaceRange(12, address.length - 8, '…');
        measure.dispose();
        return Text(
          shown,
          key: const Key('wallet_ready_address'),
          style: style,
          textDirection: TextDirection.ltr,
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.clip,
        );
      },
    ),
  );
}
