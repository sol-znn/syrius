import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/l10n/app_localizations.dart';
import 'package:zenon_syrius_wallet_flutter/utils/app_theme.dart';
import 'package:zenon_syrius_wallet_flutter/utils/window_chrome.dart';

class _WindowCaptionRepaint extends ChangeNotifier {
  void markPaint() => notifyListeners();
}

/// The actual original body route's eligibility to paint its own backdrop.
enum AppWindowEntryBackdropPhase {
  /// The original entry body is no longer painted or its owner is gone.
  hidden,

  /// The original entry body remains visible under a non-opaque overlay.
  covered,

  /// The original entry body owns the current route.
  current,
}

/// Paints only the original entry field inside this frame's caption bounds.
typedef AppWindowEntryBackdropPaint = void Function(Canvas, Size);

/// One original entry State's paint delegate; it creates no animation clock.
/// The opaque owner, route checks and builder never leave this process.
final class AppWindowEntryBackdrop {
  AppWindowEntryBackdrop._(
    this._frame, this._owner, this._phase, this._paint, this._repaint,
  ) {
    _repaint.addListener(_frame._entryBackdropChanged);
  }

  final AppWindowFrameState _frame;
  final Object _owner;
  final AppWindowEntryBackdropPhase Function() _phase;
  final AppWindowEntryBackdropPaint _paint;
  final Listenable _repaint;
  bool _retired = false;

  AppWindowEntryBackdropPhase get _originalPhase {
    if (_retired || !_frame.mounted || _frame._entryBackdropDisposed) {
      return AppWindowEntryBackdropPhase.hidden;
    }
    try {
      return _phase();
    } on Object {
      return AppWindowEntryBackdropPhase.hidden;
    }
  }

  /// Only the unique eligible original delegate is visible in this frame.
  bool get isVisible => !_retired &&
      identical(_frame._selectedEntryBackdrop(), this);

  /// Retires only this original delegate; pending frame requests cannot revive.
  void dispose() {
    if (_retired) return;
    _retired = true;
    _repaint.removeListener(_frame._entryBackdropChanged);
    _frame._entryBackdrops.remove(this);
    _frame._entryBackdropChanged();
  }
}

/// The production Windows client frame. Its body is the supplied Navigator,
/// including that Navigator's routes, modal barriers and overlay ownership.
/// Other platforms retain their native caption and the original child layout.
class AppWindowFrame extends StatefulWidget {
  /// Keep the supplied Navigator subtree as the unchanged body child.
  const AppWindowFrame({required this.child, super.key});

  /// The original application Navigator and its route/modal subtree.
  final Widget child;

  @override
  State<AppWindowFrame> createState() => AppWindowFrameState();
}

/// Owns one production caption controller for this frame's entire lifetime.
class AppWindowFrameState extends State<AppWindowFrame> {
  late final AppWindowController? _window;
  final Set<AppWindowEntryBackdrop> _entryBackdrops =
      <AppWindowEntryBackdrop>{};
  final _WindowCaptionRepaint _entryBackdropChanges = _WindowCaptionRepaint();
  bool _entryBackdropDisposed = false;

  /// Whether this original frame owns a client caption to be painted.
  bool get hasClientCaption => !_entryBackdropDisposed && _window != null;

  /// Captures only an actual descendant entry body's original paint owner.
  /// Only paint listeners are notified; registration rebuilds no ancestor.
  AppWindowEntryBackdrop? attachEntryBackdrop({
    required Object owner,
    required AppWindowEntryBackdropPhase Function() phase,
    required AppWindowEntryBackdropPaint paint,
    required Listenable repaint,
  }) {
    if (!mounted || !hasClientCaption || _entryBackdrops.any(
      (AppWindowEntryBackdrop value) => identical(value._owner, owner),
    )) {
      return null;
    }
    final AppWindowEntryBackdrop original = AppWindowEntryBackdrop._(
      this, owner, phase, paint, repaint,
    );
    _entryBackdrops.add(original);
    _entryBackdropChanged();
    return original;
  }

  AppWindowEntryBackdrop? _selectedEntryBackdrop() {
    if (!mounted || !hasClientCaption) return null;
    final List<AppWindowEntryBackdrop> current = <AppWindowEntryBackdrop>[];
    final List<AppWindowEntryBackdrop> covered = <AppWindowEntryBackdrop>[];
    for (final AppWindowEntryBackdrop original in _entryBackdrops.toList()) {
      switch (original._originalPhase) {
        case AppWindowEntryBackdropPhase.current: current.add(original);
        case AppWindowEntryBackdropPhase.covered: covered.add(original);
        case AppWindowEntryBackdropPhase.hidden: break;
      }
    }
    final List<AppWindowEntryBackdrop> eligible =
        current.isNotEmpty ? current : covered;
    return eligible.length == 1 ? eligible.single : null;
  }

  void _entryBackdropChanged() {
    if (mounted && !_entryBackdropDisposed) {
      // The only listener is the caption's RenderCustomPaint. The body can
      // update its original field during layout without rebuilding a parent.
      _entryBackdropChanges.markPaint();
    }
  }

  /// Read-only original-owner observation, independent of painted frame timing.
  AppWindowStatus? get windowStatus => _window?.status;

  @override
  void initState() {
    super.initState();
    _window = usesAppWindowFrame ? AppWindowController.native() : null;
    _window?.addListener(_changed);
  }

  void _changed() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppWindowController? window = _window;
    if (window == null) {
      return widget.child;
    }
    final AppTokens tokens = AppTokens.of(context);
    final AppLocalizations text = AppLocalizations.of(context)!;
    final Widget caption = Directionality(
      textDirection: TextDirection.ltr,
      child: Material(
        key: const ValueKey<String>('window-caption'),
        color: tokens.windowCaptionBackground,
        child: Stack(
          children: <Widget>[
            Positioned.fill(
              child: IgnorePointer(child: ExcludeSemantics(
                child: CustomPaint(
                  key: const ValueKey<String>('window-caption-backdrop'),
                  painter: _AppWindowCaptionPainter(
                    frame: this, background: tokens.windowCaptionBackground,
                  ),
                ),
              )),
            ),
            SizedBox(
              height: tokens.windowCaptionHeight,
              child: Padding(
                padding: tokens.windowCaptionPadding,
                child: FocusTraversalGroup(
                  policy: WidgetOrderTraversalPolicy(),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: GestureDetector(
                          key: const ValueKey<String>('window-drag-region'),
                          behavior: HitTestBehavior.opaque,
                          onPanStart: window.canMinimize
                              ? (_) => unawaited(window.startDragging())
                              : null,
                          onSecondaryTapDown: window.canMinimize
                              ? (_) => unawaited(window.showMenu())
                              : null,
                          onDoubleTap: window.canToggleMaximize
                              ? () => unawaited(window.toggleMaximize())
                              : null,
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Transform.translate(
                              offset: tokens.windowWordmarkPaintOffset,
                              transformHitTests: false,
                              child: Text(
                                'SYRIUS',
                                style: tokens.windowTitleText,
                              ),
                            ),
                          ),
                        ),
                      ),
                      _CaptionButton(
                        key: const ValueKey<String>('window-minimize'),
                        label: text.windowMinimize,
                        icon: Icons.remove,
                        glyph: _CaptionGlyph.minimize,
                        onPressed: window.canMinimize
                            ? () => unawaited(window.minimize())
                            : null,
                      ),
                      _CaptionButton(
                        key: const ValueKey<String>('window-maximize'),
                        label: window.maximized == true
                            ? text.windowRestore
                            : text.windowMaximize,
                        icon: window.maximized == true
                            ? Icons.filter_none
                            : Icons.crop_square,
                        glyph: window.maximized == true
                            ? null
                            : _CaptionGlyph.maximize,
                        onPressed: window.canToggleMaximize
                            ? () => unawaited(window.toggleMaximize())
                            : null,
                      ),
                      _CaptionButton(
                        key: const ValueKey<String>('window-close'),
                        label: text.commonClose,
                        icon: Icons.close,
                        glyph: _CaptionGlyph.close,
                        isClose: true,
                        onPressed: window.canClose
                            ? () => unawaited(window.close())
                            : null,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
    // Keep body lookups in the original Navigator and View ancestry.
    // Only the caption uses the full-client tooltip Overlay.
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        Column(
          children: <Widget>[
            SizedBox(height: tokens.windowCaptionHeight),
            Expanded(
              child: LayoutBuilder(
                builder: (BuildContext context, BoxConstraints constraints) =>
                    MediaQuery(
                      key: const ValueKey<String>('window-body'),
                      data: MediaQuery.of(
                        context,
                      ).copyWith(size: constraints.biggest),
                      child: widget.child,
                    ),
              ),
            ),
          ],
        ),
        Positioned.fill(
          child: Overlay.wrap(
            child: Align(alignment: Alignment.topCenter, child: caption),
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _entryBackdropDisposed = true;
    for (final AppWindowEntryBackdrop original in _entryBackdrops.toList()) {
      original.dispose();
    }
    _entryBackdrops.clear();
    _entryBackdropChanges.dispose();
    _window
      ?..removeListener(_changed)
      ..dispose();
    super.dispose();
  }
}

class _AppWindowCaptionPainter extends CustomPainter {
  _AppWindowCaptionPainter({required this._frame, required this._background})
      : super(repaint: _frame._entryBackdropChanges);

  final AppWindowFrameState _frame;
  final Color _background;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final Rect viewport = Offset.zero & size;
    canvas.drawRect(viewport, Paint()..color = _background);
    final AppWindowEntryBackdrop? original = _frame._selectedEntryBackdrop();
    if (original == null) return;
    canvas
      ..save()
      ..clipRect(viewport);
    original._paint(canvas, size);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_AppWindowCaptionPainter old) =>
      !identical(_frame, old._frame) || _background != old._background;
}

enum _CaptionGlyph { minimize, maximize, close }

class _CaptionButton extends StatelessWidget {
  const _CaptionButton({
    required this.label,
    required this.icon,
    required this.onPressed,
    super.key,
    this.isClose = false,
    this.glyph,
  });

  final String label;
  final IconData icon;
  final _CaptionGlyph? glyph;
  final VoidCallback? onPressed;
  final bool isClose;

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = AppTokens.of(context);
    final Size size = Size(
      tokens.windowControlWidth,
      tokens.windowCaptionHeight,
    );
    return IconButton(
      tooltip: label,
      onPressed: onPressed,
      icon: glyph == null
          ? Icon(icon, size: tokens.windowControlIconSize)
          : ExcludeSemantics(
              child: Builder(
                builder: (BuildContext context) => Center(
                  widthFactor: 1,
                  heightFactor: 1,
                  child: CustomPaint(
                    key: const ValueKey<String>('window-caption-mark'),
                    size: Size.square(tokens.windowControlIconSize),
                    painter: _CaptionGlyphPainter(
                      glyph!,
                      IconTheme.of(context).color ?? tokens.faint,
                    ),
                  ),
                ),
              ),
            ),
      style: ButtonStyle(
        fixedSize: WidgetStatePropertyAll<Size>(size),
        minimumSize: WidgetStatePropertyAll<Size>(size),
        maximumSize: WidgetStatePropertyAll<Size>(size),
        padding: const WidgetStatePropertyAll<EdgeInsets>(EdgeInsets.zero),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.standard,
        shape: const WidgetStatePropertyAll<OutlinedBorder>(
          RoundedRectangleBorder(),
        ),
        foregroundColor: WidgetStateProperty.resolveWith<Color>(
          (Set<WidgetState> states) {
            if (states.contains(WidgetState.disabled)) {
              return tokens.dim;
            }
            return isClose && states.contains(WidgetState.hovered)
                ? tokens.error
                : tokens.faint;
          },
        ),
        overlayColor: WidgetStateProperty.resolveWith<Color>(
          (Set<WidgetState> states) =>
              isClose ? tokens.windowCloseHover : tokens.hover,
        ),
        side: WidgetStateProperty.resolveWith<BorderSide>(
          (Set<WidgetState> states) => states.contains(WidgetState.focused)
              ? BorderSide(color: tokens.focusRing, width: tokens.focusWidth)
              : BorderSide.none,
        ),
      ),
    );
  }
}

/// The three reference caption marks on the original twelve-pixel canvas.
/// Their geometry remains independent of platform symbol-font fallback.
class _CaptionGlyphPainter extends CustomPainter {
  const _CaptionGlyphPainter(this._glyph, this._color);

  final _CaptionGlyph _glyph;
  final Color _color;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    canvas.save();
    try {
      canvas.scale(size.width / 12, size.height / 12);
      final Paint ink = Paint()
        ..color = _color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1;
      switch (_glyph) {
        case _CaptionGlyph.minimize:
          canvas.drawLine(const Offset(1, 6), const Offset(11, 6), ink);
          return;
        case _CaptionGlyph.maximize:
          canvas.drawRect(const Rect.fromLTWH(3.5, 3.5, 5, 5), ink);
          return;
        case _CaptionGlyph.close:
          canvas
            ..drawLine(const Offset(1.5, 0.5), const Offset(10.5, 8.5), ink)
            ..drawLine(const Offset(10.5, 0.5), const Offset(1.5, 8.5), ink);
          return;
      }
    } finally {
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_CaptionGlyphPainter oldDelegate) =>
      _glyph != oldDelegate._glyph || _color != oldDelegate._color;
}
