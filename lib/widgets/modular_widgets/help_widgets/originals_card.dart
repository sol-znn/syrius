import 'dart:async';

import 'package:flutter/services.dart';
import 'package:lottie/lottie.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/extensions/buildcontext_extension.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/list_entrance.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/ltr.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/page/page_widgets.dart';
import 'package:zenon_syrius_wallet_flutter/utils/app_theme.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/settings_widgets/settings_parts.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/reusable_widgets/app_lottie.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/reusable_widgets/launch_film.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/shell/rail.dart';

part 'originals_tiles.dart';

/// Discovery belongs to one Settings visit and never reaches preferences.
class OriginalsController extends ChangeNotifier {
  bool _revealed = false;
  bool _closed = false;

  /// Whether the exact discovery input was entered during this visit.
  bool get revealed => !_closed && _revealed;

  /// Reveals once; disposed controllers cannot be revived by saved callbacks.
  void reveal() {
    if (_closed || _revealed) return;
    _revealed = true;
    notifyListeners();
  }

  @override
  void dispose() {
    _closed = true;
    super.dispose();
  }
}

/// The unlabelled field after the final genuine licence entry.
class OriginalsDiscovery extends StatefulWidget {
  /// The owning Settings page supplies both lifetime and source authority.
  const OriginalsDiscovery({
    required this.controller,
    required this.isCurrent,
    super.key,
  });

  /// The controller survives section changes but ends when Settings is left.
  final OriginalsController controller;

  /// A saved callback cannot reveal a replacement Settings visit.
  final bool Function() isCurrent;

  @override
  State<OriginalsDiscovery> createState() => _OriginalsDiscoveryState();
}

class _OriginalsDiscoveryState extends State<OriginalsDiscovery>
    with WidgetsBindingObserver {
  final TextEditingController _text = TextEditingController();
  int _epoch = 0;
  bool _active = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _epoch++;
    _active = state == AppLifecycleState.resumed;
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(OriginalsDiscovery oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      _epoch++;
      _text.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = AppTokens.of(context);
    final OriginalsController original = widget.controller;
    final int epoch = _epoch;
    final bool Function() source = widget.isCurrent;
    return Padding(
      padding: tokens.originalsDiscoveryPadding,
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: SizedBox(
          width: tokens.originalsDiscoveryWidth,
          height: tokens.originalsDiscoveryHeight,
          child: Ltr(
            child: TextField(
              key: const Key('originals_discovery_field'),
              controller: _text,
              style: tokens.dataText,
              decoration: InputDecoration(
                isDense: true,
                contentPadding: EdgeInsetsDirectional.symmetric(
                  horizontal: tokens.originalsFieldInset,
                  vertical: tokens.originalsFieldVerticalInset,
                ),
              ),
              onChanged: (String value) {
                if (!mounted ||
                    !_active ||
                    epoch != _epoch ||
                    !identical(original, widget.controller) ||
                    !source() ||
                    !TickerMode.valuesOf(context).enabled ||
                    !(ModalRoute.of(context)?.isCurrent ?? true)) {
                  return;
                }
                if (value == '321') {
                  _text.clear();
                  original.reveal();
                }
              },
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _epoch++;
    WidgetsBinding.instance.removeObserver(this);
    _text.dispose();
    super.dispose();
  }
}

/// The six original large artworks, without constructing wallet services.
enum OriginalsArt {
  /// The original launch movie.
  launch,

  /// The turning welcome globe.
  globe,

  /// The ready screen's node map.
  map,

  /// The assembling pillar.
  pillar,

  /// The assembling sentinel.
  sentinel,

  /// The assembling token coin.
  zts,
}

/// Presentation fixtures can replace artwork without parsing large assets.
typedef OriginalsArtBuilder = Widget Function(BuildContext, OriginalsArt);

/// Finite fixtures may supply the same film interface with a tiny movie.
typedef OriginalsReplayBuilder =
    Widget Function(
      BuildContext,
      LaunchFilmController,
      VoidCallback,
    );

/// The original nine animations and a replay of the movie alone.
class OriginalsCard extends StatefulWidget {
  /// This card has no startup, authentication, storage or network callbacks.
  const OriginalsCard({
    required this.isCurrent,
    this.artBuilder,
    this.replayBuilder,
    super.key,
  });

  /// Authority belongs to the exact Settings visit that revealed the card.
  final bool Function() isCurrent;

  /// Supplies inert artwork in presentation fixtures only.
  final OriginalsArtBuilder? artBuilder;

  /// Supplies a tiny original film in finite replay fixtures.
  final OriginalsReplayBuilder? replayBuilder;

  @override
  State<OriginalsCard> createState() => _OriginalsCardState();
}

class _OriginalsCardState extends State<OriginalsCard>
    with WidgetsBindingObserver {
  final LaunchFilmController _film = LaunchFilmController();
  final FocusNode _movieFocus = FocusNode(debugLabel: 'Original movie replay');
  OverlayEntry? _entry;
  Object? _run;
  FocusNode? _returnFocus;
  bool _active = true;
  int _epoch = 0;

  bool _current() =>
      mounted &&
      _active &&
      widget.isCurrent() &&
      TickerMode.valuesOf(context).enabled &&
      (ModalRoute.of(context)?.isCurrent ?? true);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _epoch++;
    _active = state == AppLifecycleState.resumed;
    if (!_active) _closeReplay(restoreFocus: false);
  }

  void _replay(bool Function() current) {
    if (_entry != null || !current()) return;
    final OverlayState overlay = Overlay.of(context, rootOverlay: true);
    final Object run = Object();
    _run = run;
    _returnFocus = FocusManager.instance.primaryFocus;
    final AppTokens tokens = AppTokens.of(context);
    final String hint = context.l10n.launchSkipHint;
    final OriginalsReplayBuilder? builder = widget.replayBuilder;
    void done() {
      if (identical(run, _run)) _closeReplay(restoreFocus: current());
    }

    final OverlayEntry entry = OverlayEntry(
      builder: (BuildContext context) => Positioned.fill(
        child: Material(
          key: const Key('originals_movie_replay'),
          color: tokens.launchStageBackground,
          child: Focus(
            focusNode: _movieFocus,
            autofocus: true,
            onKeyEvent: (_, KeyEvent event) {
              if (event is KeyDownEvent && identical(run, _run)) {
                _film.skipToEnd();
                return KeyEventResult.handled;
              }
              return KeyEventResult.ignored;
            },
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                if (identical(run, _run)) _film.skipToEnd();
              },
              child: Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  builder?.call(context, _film, done) ??
                      LaunchFilm(
                        controller: _film,
                        fit: BoxFit.cover,
                        onDone: done,
                      ),
                  PositionedDirectional(
                    start: 0,
                    end: 0,
                    bottom: tokens.launchHintBottomInset,
                    child: Text(
                      hint,
                      textAlign: TextAlign.center,
                      style: tokens.launchHintText,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    _entry = entry;
    overlay.insert(entry);
  }

  void _closeReplay({required bool restoreFocus}) {
    final OverlayEntry? entry = _entry;
    if (entry == null) return;
    _entry = null;
    _run = null;
    entry
      ..remove()
      ..dispose();
    final FocusNode? previous = _returnFocus;
    _returnFocus = null;
    if (restoreFocus &&
        _current() &&
        previous?.context != null &&
        previous!.canRequestFocus) {
      previous.requestFocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = AppTokens.of(context);
    final int epoch = _epoch;
    bool current() => epoch == _epoch && _current();
    const ValueKey<String> key = ValueKey<String>('originals_card');
    return ListEntrance(
      itemKeys: const <LocalKey>[key],
      child: ListEntranceItem(
        key: key,
        child: Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: tokens.panelHeaderHeight,
                ),
                child: Padding(
                  padding: tokens.panelHeaderPadding,
                  child: Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: tokens.settingsActionGap,
                    runSpacing: tokens.settingsActionGap,
                    children: <Widget>[
                      Text(
                        context.l10n.originalsTitle,
                        style: panelTitleStyle(context),
                      ),
                      Wrap(
                        spacing: tokens.settingsActionGap,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: <Widget>[
                          Text(
                            context.l10n.originalsSince,
                            style: tokens.settingsHintText,
                          ),
                          SecondaryAction(
                            child: OutlinedButton.icon(
                              key: const Key('originals_play_launch'),
                              style: OutlinedButton.styleFrom(
                                minimumSize: Size(0, tokens.smallButtonHeight),
                                padding: EdgeInsetsDirectional.symmetric(
                                  horizontal: tokens.receiveMicroGap,
                                ),
                                textStyle: tokens.captionText,
                              ),
                              onPressed: () => _replay(current),
                              icon: buildShellSymbol(
                                context,
                                'refresh',
                                size: tokens.settingsIconSize,
                                color: tokens.dim,
                              ),
                              label: Text(context.l10n.originalsPlayLaunch),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const Divider(height: 1),
              Padding(
                padding: tokens.originalsBodyPadding,
                child: _OriginalsTiles(
                  isCurrent: current,
                  artBuilder: widget.artBuilder,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _epoch++;
    WidgetsBinding.instance.removeObserver(this);
    _closeReplay(restoreFocus: false);
    _movieFocus.dispose();
    _film.dispose();
    super.dispose();
  }
}
