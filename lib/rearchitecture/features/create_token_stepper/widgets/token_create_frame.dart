import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/utils.dart';
import 'package:zenon_syrius_wallet_flutter/utils/app_theme.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/reusable_widgets/buttons/primary_pill.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/reusable_widgets/modals/modal_chrome.dart';

/// A finite field viewport and fixed actions for the four token steps.
class TokenCreateFrame extends StatefulWidget {
  /// The retained shared-axis input gate owns activation and focus timing.
  const TokenCreateFrame({
    required this.active,
    required this.body,
    required this.label,
    this.onSubmit,
    this.onBack,
    this.busy = false,
    super.key,
  });

  /// Only the selected, fully entered step can act.
  final bool active;

  /// Scrolls independently of the action row in a short window.
  final Widget body;

  /// The primary action's concise current meaning.
  final String label;

  /// Null until this step has enough valid facts.
  final VoidCallback? onSubmit;

  /// The first step retains a disabled Back button.
  final VoidCallback? onBack;

  /// A pending preflight or publication closes editing and Back.
  final bool busy;

  @override
  State<TokenCreateFrame> createState() => _TokenCreateFrameState();
}

class _TokenCreateFrameState extends State<TokenCreateFrame> {
  final FocusNode _scope = FocusNode(debugLabel: 'Token creation step');
  final FocusNode _fields = FocusNode(debugLabel: 'Token creation fields');
  final FocusNode _primary = FocusNode(debugLabel: 'Token creation action');
  bool _interactive = false;
  int _generation = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(TokenCreateFrame oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  void _sync() {
    final bool interactive = widget.active && StepInteraction.of(context);
    if (interactive == _interactive) return;
    _interactive = interactive;
    final int generation = ++_generation;
    if (!interactive) {
      if (_scope.hasFocus) _scope.unfocus();
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_interactive || generation != _generation) return;
      if (!_scope.hasFocus) {
        (_fields.traversalDescendants.firstOrNull ??
                _primary.traversalDescendants.firstOrNull)
            ?.requestFocus();
      }
    });
  }

  void _submit() {
    if (_interactive && !widget.busy) widget.onSubmit?.call();
  }

  KeyEventResult _fieldKey(FocusNode node, KeyEvent event) {
    if (event.logicalKey != LogicalKeyboardKey.enter &&
        event.logicalKey != LogicalKeyboardKey.numpadEnter) {
      return KeyEventResult.ignored;
    }
    if (event is KeyDownEvent) _submit();
    return KeyEventResult.handled;
  }

  KeyEventResult _frameKey(FocusNode node, KeyEvent event) {
    final LogicalKeyboardKey key = event.logicalKey;
    if (event is KeyRepeatEvent &&
        (key == LogicalKeyboardKey.enter ||
            key == LogicalKeyboardKey.numpadEnter ||
            key == LogicalKeyboardKey.space)) {
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = AppTokens.of(context);
    return FocusTraversalGroup(
      policy: ReadingOrderTraversalPolicy(),
      child: Focus(
        focusNode: _scope,
        canRequestFocus: false,
        skipTraversal: true,
        descendantsAreFocusable: _interactive,
        onKeyEvent: _frameKey,
        child: IgnorePointer(
          ignoring: !_interactive,
          child: ExcludeSemantics(
            excluding: !_interactive,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Flexible(
                  child: Focus(
                    focusNode: _fields,
                    canRequestFocus: false,
                    skipTraversal: true,
                    descendantsAreFocusable: !widget.busy,
                    onKeyEvent: _fieldKey,
                    child: IgnorePointer(
                      ignoring: widget.busy,
                      child: SingleChildScrollView(child: widget.body),
                    ),
                  ),
                ),
                SizedBox(height: tokens.registrationActionGap),
                Wrap(
                  spacing: tokens.inlineGap,
                  runSpacing: tokens.inlineGap,
                  children: <Widget>[
                    TextButton(
                      key: const Key('token_create_back'),
                      style: quietButtonStyle(context),
                      onPressed: widget.busy || widget.onBack == null
                          ? null
                          : () {
                              if (_interactive) widget.onBack!();
                            },
                      child: Text(context.l10n.tokenCreateBack),
                    ),
                    Focus(
                      focusNode: _primary,
                      canRequestFocus: false,
                      skipTraversal: true,
                      child: PrimaryPill(
                        key: const Key('token_create_continue'),
                        onPressed: widget.busy || widget.onSubmit == null
                            ? null
                            : _submit,
                        child: Text(widget.label),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _generation++;
    _scope.dispose();
    _fields.dispose();
    _primary.dispose();
    super.dispose();
  }
}
