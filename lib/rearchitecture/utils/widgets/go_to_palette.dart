import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/extensions/buildcontext_extension.dart';
import 'package:zenon_syrius_wallet_flutter/seams/seam.dart';
import 'package:zenon_syrius_wallet_flutter/utils/app_theme.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/reusable_widgets/modals/frosted_route.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/reusable_widgets/modals/modal_chrome.dart';

/// The three groups in the palette. Contacts share the addresses group.
enum GoToCategory {
  /// A page or a named destination inside one.
  pages,

  /// An action whose existing flow is opened by the shell.
  actions,

  /// An owned address or a contact, identified by its complete address.
  addresses,
}

/// Draws an entry's original mark in the supplied foreground colour.
typedef GoToIconBuilder = Widget Function(BuildContext context, Color color);

/// One destination a [GoToPalette] offers.
///
/// The shell supplies values and validates them again when it dispatches the
/// answer. The palette never resolves a name or a shortened identifier into an
/// operation, and never invokes a callback stored as [value].
class GoToEntry<T> {
  /// Creates an entry that answers [value] when chosen.
  const GoToEntry({
    required this.value,
    required this.label,
    this.icon,
    this.shortcut,
    this.id,
    this.category = GoToCategory.pages,
    this.detail,
    this.identifier,
    this.searchTerms = const <String>[],
    this.seam,
    this.iconBuilder,
  });

  /// What the palette returns for this entry, without interpreting it.
  final T value;

  /// The localized name shown and searched.
  final String label;

  /// The legacy icon, used when [iconBuilder] is absent.
  final IconData? icon;

  /// A key chord shown at the end of the row. The shell owns its binding.
  final String? shortcut;

  /// A stable, unique catalog identity, independent of the translated name.
  ///
  /// When omitted, [value] supplies the identity for existing callers. Supply
  /// an id when separate destinations can have equal values or labels.
  final Object? id;

  /// Which heading the entry appears beneath.
  final GoToCategory category;

  /// A short context or action label, such as Nodes or Send to.
  final String? detail;

  /// The exact complete identifier. Only its visual presentation is shortened.
  final String? identifier;

  /// Additional localized names and aliases searched without fuzzy matching.
  final List<String> searchTerms;

  /// A drawn action whose backing implementation is missing.
  final Seam? seam;

  /// The original glyph, preferred over the legacy material icon.
  final GoToIconBuilder? iconBuilder;
}

/// Opens the palette and returns one selected value, or null on dismissal.
///
/// The owner supplies [chordName] to match its actual platform bindings. Focus
/// returns to its previous field only if that field still belongs to the tree.
Future<T?> showGoToPalette<T>({
  required BuildContext context,
  required List<GoToEntry<T>> entries,
  String? hintText,
  String chordName = 'Ctrl',
}) async {
  final FocusNode? previousFocus = FocusManager.instance.primaryFocus;
  try {
    return await showFrostedDialog<T>(
      context: context,
      builder: (BuildContext context) => GoToPalette<T>(
        entries: entries,
        hintText: hintText,
        chordName: chordName,
      ),
    );
  } finally {
    if (previousFocus != null &&
        (previousFocus.context?.mounted ?? false) &&
        previousFocus.canRequestFocus) {
      previousFocus.requestFocus();
    }
  }
}

/// Pages, actions and addresses under one focused search field.
///
/// Each group keeps prefix matches ahead of substring matches. Arrows move
/// between available entries, Enter answers once, and Escape dismisses. Headers
/// and missing implementations never become keyboard targets.
class GoToPalette<T> extends StatefulWidget {
  /// Creates a palette over the supplied catalog, including live replacements.
  const GoToPalette({
    required this.entries,
    this.hintText,
    this.chordName = 'Ctrl',
    super.key,
  });

  /// Every destination in its stable order within a group.
  final List<GoToEntry<T>> entries;

  /// The field's hint. Null takes the localized Go to label.
  final String? hintText;

  /// The key used by the shell's displayed shortcuts, for example Cmd.
  final String chordName;

  @override
  State<GoToPalette<T>> createState() => _GoToPaletteState<T>();
}

class _GoToPaletteState<T> extends State<GoToPalette<T>> {
  static const int _rowsShown = 8;

  final TextEditingController _query = TextEditingController();
  final ScrollController _scroll = ScrollController();

  List<GoToEntry<T>> _matches = <GoToEntry<T>>[];
  List<_ListItem<T>> _items = <_ListItem<T>>[];
  int _highlighted = -1;
  int _scrollRevision = 0;
  String _lastText = '';
  bool _answered = false;

  bool get _composing =>
      _query.value.composing.isValid && !_query.value.composing.isCollapsed;

  String get _needle => _query.text.trim().toLowerCase();

  @override
  void initState() {
    super.initState();
    _replaceMatches(reset: true);
    _query.addListener(_editingChanged);
  }

  @override
  void didUpdateWidget(GoToPalette<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    _replaceMatches(reset: false);
    _scheduleScroll();
  }

  @override
  void dispose() {
    _query
      ..removeListener(_editingChanged)
      ..dispose();
    _scroll.dispose();
    super.dispose();
  }

  Object? _identity(GoToEntry<T> entry) => entry.id ?? entry.value;

  void _editingChanged() {
    final bool changed = _lastText != _query.text;
    setState(() {
      _lastText = _query.text;
      _replaceMatches(reset: changed);
    });
    _scheduleScroll(reset: changed);
  }

  void _replaceMatches({required bool reset}) {
    final Object? previous = _highlighted >= 0 && _highlighted < _matches.length
        ? _identity(_matches[_highlighted])
        : null;
    final bool hadPrevious = _highlighted >= 0;
    final String needle = _needle;
    final List<GoToEntry<T>> matches = <GoToEntry<T>>[];
    for (final GoToCategory category in GoToCategory.values) {
      final List<GoToEntry<T>> starts = <GoToEntry<T>>[];
      final List<GoToEntry<T>> contains = <GoToEntry<T>>[];
      for (final GoToEntry<T> entry in widget.entries) {
        if (entry.category != category) continue;
        final List<String> terms = <String>[
          entry.label,
          if (entry.detail != null) entry.detail!,
          if (entry.identifier != null) entry.identifier!,
          ...entry.searchTerms,
        ].map((String term) => term.toLowerCase()).toList();
        if (terms.any((String term) => term.startsWith(needle))) {
          starts.add(entry);
        } else if (terms.any((String term) => term.contains(needle))) {
          contains.add(entry);
        }
      }
      matches.addAll(<GoToEntry<T>>[...starts, ...contains]);
    }
    _matches = matches;
    _highlighted = !reset && hadPrevious
        ? matches.indexWhere(
            (GoToEntry<T> entry) =>
                _identity(entry) == previous && entry.seam == null,
          )
        : -1;
    if (_highlighted < 0) {
      _highlighted = matches.indexWhere(
        (GoToEntry<T> entry) => entry.seam == null,
      );
    }
    _items = <_ListItem<T>>[];
    GoToCategory? lastCategory;
    for (int i = 0; i < matches.length; i++) {
      final GoToEntry<T> entry = matches[i];
      if (lastCategory != entry.category) {
        _items.add(_ListItem<T>.heading(entry.category));
        lastCategory = entry.category;
      }
      _items.add(_ListItem<T>.entry(entry, i));
    }
  }

  void _move(int direction) {
    if (!mounted || _matches.isEmpty) return;
    int next = _highlighted;
    for (int i = 0; i < _matches.length; i++) {
      next = next < 0
          ? (direction < 0 ? _matches.length - 1 : 0)
          : (next + direction) % _matches.length;
      if (_matches[next].seam == null) {
        setState(() => _highlighted = next);
        _scheduleScroll();
        return;
      }
    }
  }

  void _scheduleScroll({bool reset = false}) {
    final int revision = ++_scrollRevision;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || revision != _scrollRevision || !_scroll.hasClients) {
        return;
      }
      final ScrollPosition position = _scroll.position;
      double target = reset ? position.minScrollExtent : position.pixels;
      if (_highlighted >= 0) {
        final AppTokens tokens = AppTokens.of(context);
        double top = tokens.goToListInset;
        for (final _ListItem<T> item in _items) {
          if (item.entryIndex == _highlighted) break;
          top += item.entry == null
              ? tokens.goToHeadingHeight
              : tokens.goToRowHeight;
        }
        final double bottom = top + tokens.goToRowHeight;
        if (top < target) {
          target = top;
        } else if (bottom > target + position.viewportDimension) {
          target = bottom - position.viewportDimension;
        }
      }
      _scroll.jumpTo(
        target.clamp(position.minScrollExtent, position.maxScrollExtent),
      );
    });
  }

  void _take([int? index]) {
    final int at = index ?? _highlighted;
    if (!mounted ||
        _answered ||
        _composing ||
        at < 0 ||
        at >= _matches.length) {
      return;
    }
    final GoToEntry<T> entry = _matches[at];
    runUnlessSeamed(
      seam: entry.seam,
      action: () {
        if (ModalRoute.of(context)?.isCurrent == false) return;
        _answered = true;
        Navigator.of(context).pop<T>(entry.value);
      },
    );
  }

  void _takeEntry(GoToEntry<T> entry) {
    // A row callback can outlive a catalog replacement. Its former index may
    // now name another destination, so resolve only its unchanged identity.
    final int index = _matches.indexWhere(
      (GoToEntry<T> current) => _identity(current) == _identity(entry),
    );
    if (index >= 0) _take(index);
  }

  void _hoverEntry(GoToEntry<T> entry) {
    if (!mounted || _answered) return;
    final int index = _matches.indexWhere(
      (GoToEntry<T> current) =>
          _identity(current) == _identity(entry) && current.seam == null,
    );
    if (index >= 0 && index != _highlighted) {
      setState(() => _highlighted = index);
      _scheduleScroll();
    }
  }

  void _dismiss() {
    if (!mounted || _answered || ModalRoute.of(context)?.isCurrent == false) {
      return;
    }
    _answered = true;
    Navigator.of(context).pop<T>();
  }

  String _categoryLabel(GoToCategory category) => switch (category) {
    GoToCategory.pages => context.l10n.goToPalettePages,
    GoToCategory.actions => context.l10n.goToPaletteActions,
    GoToCategory.addresses => context.l10n.goToPaletteAddresses,
  };

  Widget _buildHeader(AppTokens tokens) => Padding(
    padding: tokens.goToHeaderPadding,
    child: Row(
      children: <Widget>[
        Icon(Icons.search, size: tokens.railIconSize, color: tokens.faint),
        SizedBox(width: tokens.inlineGap),
        Expanded(
          child: TextField(
            key: const Key('go_to_field'),
            controller: _query,
            autofocus: true,
            textInputAction: TextInputAction.go,
            style: tokens.goToQueryText,
            decoration: InputDecoration(
              filled: false,
              isDense: true,
              hintText: widget.hintText ?? context.l10n.goToPaletteHint,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              contentPadding: EdgeInsets.zero,
            ),
            onSubmitted: (_) => _take(),
          ),
        ),
        SizedBox(width: tokens.inlineGap),
        const _KeyHint('Esc'),
      ],
    ),
  );

  Widget _buildList(AppTokens tokens) {
    if (_matches.isEmpty) {
      return SizedBox(
        height: tokens.goToRowHeight + tokens.goToListInset * 2,
        child: Padding(
          padding: EdgeInsetsDirectional.symmetric(
            horizontal: tokens.goToRowInset + tokens.goToListInset,
          ),
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: Text(
              context.l10n.goToPaletteEmpty,
              style: tokens.compactText,
            ),
          ),
        ),
      );
    }
    final int headings = _items.length - _matches.length;
    final double height =
        tokens.goToListInset * 2 +
        headings * tokens.goToHeadingHeight +
        math.min(_matches.length, _rowsShown) * tokens.goToRowHeight;
    return SizedBox(
      height: height,
      child: ListView.builder(
        key: const Key('go_to_results'),
        controller: _scroll,
        padding: EdgeInsets.all(tokens.goToListInset),
        itemCount: _items.length,
        itemBuilder: (BuildContext context, int index) {
          final _ListItem<T> item = _items[index];
          final GoToEntry<T>? entry = item.entry;
          if (entry == null) {
            return SizedBox(
              height: tokens.goToHeadingHeight,
              child: Padding(
                padding: tokens.goToHeadingPadding,
                child: Text(
                  _categoryLabel(item.heading!).toUpperCase(),
                  style: tokens.ledgerText,
                ),
              ),
            );
          }
          Widget row = _PaletteRow<T>(
            key: ValueKey<Object?>(_identity(entry)),
            entry: entry,
            highlighted: item.entryIndex == _highlighted,
            needle: _needle,
            onHover: () => _hoverEntry(entry),
            onTap: () => _takeEntry(entry),
          );
          if (entry.seam != null) row = SeamGate(seam: entry.seam!, child: row);
          return SizedBox(height: tokens.goToRowHeight, child: row);
        },
      ),
    );
  }

  Widget _buildFooter(AppTokens tokens) => Padding(
    padding: tokens.goToFooterPadding,
    child: Row(
      children: <Widget>[
        const _KeyHint('↑↓'),
        SizedBox(width: tokens.inlineGap),
        Text(context.l10n.goToPaletteMove, style: tokens.captionText),
        SizedBox(width: tokens.goToFooterGap),
        const _KeyHint('↵'),
        SizedBox(width: tokens.inlineGap),
        Text(context.l10n.goToPaletteOpen, style: tokens.captionText),
        SizedBox(width: tokens.goToFooterGap),
        Expanded(child: _ShortcutSummary(chordName: widget.chordName)),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = AppTokens.of(context);
    final BorderRadius radius = BorderRadius.circular(tokens.dialogRadius);
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.escape): _dismiss,
        // IME composition keeps its own arrows and Enter until it is committed.
        if (!_composing) ...<ShortcutActivator, VoidCallback>{
          const SingleActivator(LogicalKeyboardKey.arrowDown): () => _move(1),
          const SingleActivator(LogicalKeyboardKey.arrowUp): () => _move(-1),
          const SingleActivator(LogicalKeyboardKey.enter): _take,
          const SingleActivator(LogicalKeyboardKey.numpadEnter): _take,
        },
      },
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) => Padding(
          padding: EdgeInsetsDirectional.fromSTEB(
            tokens.goToEdgeInset,
            math.min(tokens.goToTopInset, constraints.maxHeight / 4),
            tokens.goToEdgeInset,
            tokens.goToEdgeInset,
          ),
          child: Align(
            alignment: Alignment.topCenter,
            child: SizedBox(
              key: const Key('go_to_palette'),
              width: tokens.goToWidth,
              child: RiseIn(
                duration: const Duration(milliseconds: 240),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: radius,
                    boxShadow: <BoxShadow>[tokens.dialogShadow],
                  ),
                  child: FrostedSurface(
                    borderRadius: radius,
                    child: DecoratedBox(
                      position: DecorationPosition.foreground,
                      decoration: BoxDecoration(
                        borderRadius: radius,
                        border: Border.all(color: tokens.line),
                      ),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          border: Border(top: tokens.glassTopEdge),
                        ),
                        child: Material(
                          type: MaterialType.transparency,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: <Widget>[
                              _buildHeader(tokens),
                              Divider(
                                height: 1,
                                thickness: 1,
                                color: tokens.line,
                              ),
                              Flexible(child: _buildList(tokens)),
                              _buildFooter(tokens),
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
      ),
    );
  }
}

class _ListItem<T> {
  const _ListItem.heading(this.heading) : entry = null, entryIndex = null;

  const _ListItem.entry(this.entry, this.entryIndex) : heading = null;

  final GoToCategory? heading;
  final GoToEntry<T>? entry;
  final int? entryIndex;
}

class _PaletteRow<T> extends StatefulWidget {
  const _PaletteRow({
    required this.entry,
    required this.highlighted,
    required this.needle,
    required this.onHover,
    required this.onTap,
    super.key,
  });

  final GoToEntry<T> entry;
  final bool highlighted;
  final String needle;
  final VoidCallback onHover;
  final VoidCallback onTap;

  @override
  State<_PaletteRow<T>> createState() => _PaletteRowState<T>();
}

class _PaletteRowState<T> extends State<_PaletteRow<T>>
    with SingleTickerProviderStateMixin {
  late final AnimationController _highlight = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 150),
    value: widget.highlighted ? 1 : 0,
    // Selection feedback keeps its clock regardless of OS animation effects.
    animationBehavior: AnimationBehavior.preserve,
  );

  @override
  void didUpdateWidget(_PaletteRow<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.highlighted != oldWidget.highlighted) {
      _highlight.animateTo(
        widget.highlighted ? 1 : 0,
        curve: AppTokens.of(context).ease,
      );
    }
  }

  @override
  void dispose() {
    _highlight.dispose();
    super.dispose();
  }

  Widget _buildContents(AppTokens tokens) {
    final GoToEntry<T> entry = widget.entry;
    final Color ink = widget.highlighted ? tokens.foreground : tokens.dim;
    final GoToIconBuilder? iconBuilder = entry.iconBuilder;
    final String? identifier = entry.identifier;
    final bool address = entry.category == GoToCategory.addresses;
    Widget detail() => _MatchedText(
      text: entry.detail!,
      needle: widget.needle,
      style: tokens.compactText.copyWith(color: tokens.dim),
    );
    return Padding(
      padding: EdgeInsetsDirectional.symmetric(horizontal: tokens.goToRowInset),
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) => Row(
          children: <Widget>[
            if (iconBuilder != null || entry.icon != null) ...<Widget>[
              iconBuilder?.call(context, ink) ??
                  Icon(entry.icon, size: tokens.railIconSize, color: ink),
              SizedBox(width: tokens.railLabelGap),
            ],
            // Fill the content slot before laying out the trailing hint.
            // Loose text widths must not leave space after that hint.
            Expanded(
              child: Row(
                children: <Widget>[
                  Flexible(
                    child: _MatchedText(
                      text: entry.label,
                      needle: widget.needle,
                      style: tokens.bodyText.copyWith(color: ink),
                    ),
                  ),
                  if (identifier != null) ...<Widget>[
                    SizedBox(width: tokens.inlineGap),
                    Flexible(
                      child: Tooltip(
                        message: identifier,
                        child: _MatchedText(
                          text: _shortIdentifier(identifier),
                          needle: widget.needle,
                          style: tokens.goToIdentifierText,
                          textDirection: TextDirection.ltr,
                        ),
                      ),
                    ),
                  ],
                  if (!address && entry.detail != null) ...<Widget>[
                    SizedBox(width: tokens.inlineGap),
                    Flexible(child: detail()),
                  ],
                ],
              ),
            ),
            if (address && entry.detail != null) ...<Widget>[
              SizedBox(width: tokens.inlineGap),
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: constraints.maxWidth * 0.4,
                ),
                child: detail(),
              ),
            ],
            if (entry.shortcut != null) ...<Widget>[
              SizedBox(width: tokens.inlineGap),
              _KeyHint(entry.shortcut!),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = AppTokens.of(context);
    final GoToEntry<T> entry = widget.entry;
    return Semantics(
      button: true,
      selected: widget.highlighted,
      label: <String>[
        entry.label,
        if (entry.identifier != null) entry.identifier!,
        if (entry.detail != null) entry.detail!,
      ].join(', '),
      onTap: widget.onTap,
      child: ExcludeSemantics(
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onHover: (_) => widget.onHover(),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            excludeFromSemantics: true,
            onTap: widget.onTap,
            child: AnimatedBuilder(
              animation: _highlight,
              child: _buildContents(tokens),
              builder: (BuildContext context, Widget? child) => DecoratedBox(
                decoration: BoxDecoration(
                  color: tokens.card3.withValues(alpha: _highlight.value),
                  borderRadius: BorderRadius.circular(tokens.compactRadius),
                ),
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

String _shortIdentifier(String identifier) => identifier.length <= 13
    ? identifier
    : '${identifier.substring(0, 6)}…'
          '${identifier.substring(identifier.length - 4)}';

class _MatchedText extends StatelessWidget {
  const _MatchedText({
    required this.text,
    required this.needle,
    required this.style,
    this.textDirection,
  });

  final String text;
  final String needle;
  final TextStyle style;
  final TextDirection? textDirection;

  @override
  Widget build(BuildContext context) {
    final List<InlineSpan> spans = <InlineSpan>[];
    int cursor = 0;
    if (needle.isNotEmpty) {
      // Match offsets belong to the original string, including translated text
      // whose lowercase form can have a different number of code units.
      final RegExp pattern = RegExp(
        RegExp.escape(needle),
        caseSensitive: false,
      );
      for (final RegExpMatch match in pattern.allMatches(text)) {
        if (match.start > cursor) {
          spans.add(TextSpan(text: text.substring(cursor, match.start)));
        }
        spans.add(
          TextSpan(
            text: text.substring(match.start, match.end),
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        );
        cursor = match.end;
      }
    }
    if (cursor < text.length) spans.add(TextSpan(text: text.substring(cursor)));
    return Text.rich(
      TextSpan(children: spans),
      style: style,
      textDirection: textDirection,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}

class _KeyHint extends StatelessWidget {
  const _KeyHint(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = AppTokens.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: tokens.line),
        borderRadius: BorderRadius.circular(tokens.keyboardHintRadius),
      ),
      child: Padding(
        padding: tokens.keyboardHintPadding,
        child: Text(
          label,
          style: tokens.keyboardHintText,
          textDirection: TextDirection.ltr,
        ),
      ),
    );
  }
}

class _ShortcutSummary extends StatelessWidget {
  const _ShortcutSummary({required this.chordName});

  final String chordName;

  @override
  Widget build(BuildContext context) {
    final List<String> chords = <String>[
      '$chordName 1',
      '$chordName 8',
      '$chordName L',
      '$chordName R',
    ];
    final String text = context.l10n.goToPaletteShortcuts(
      chords[0],
      chords[1],
      chords[2],
      chords[3],
    );
    final RegExp pattern = RegExp(chords.map(RegExp.escape).join('|'));
    final List<InlineSpan> spans = <InlineSpan>[];
    int cursor = 0;
    for (final RegExpMatch match in pattern.allMatches(text)) {
      if (match.start > cursor) {
        spans.add(TextSpan(text: text.substring(cursor, match.start)));
      }
      spans.add(
        WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: _KeyHint(match.group(0)!),
        ),
      );
      cursor = match.end;
    }
    if (cursor < text.length) spans.add(TextSpan(text: text.substring(cursor)));
    return Text.rich(
      TextSpan(children: spans),
      style: AppTokens.of(context).captionText,
      textAlign: TextAlign.end,
    );
  }
}
