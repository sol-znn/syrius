import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/extensions/buildcontext_extension.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/hero_field.dart';
import 'package:zenon_syrius_wallet_flutter/seams/seam.dart';
import 'package:zenon_syrius_wallet_flutter/utils/app_theme.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/reusable_widgets/buttons/primary_pill.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/reusable_widgets/launch_film.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/reusable_widgets/modals/frosted_route.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/reusable_widgets/startup_stage.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/tab_children_widgets/lock_wallet_picker.dart';

/// A lock view with no wallet, filesystem or SDK dependency.
///
/// The owner supplies the selected wallet's display data, controls attempts,
/// and clears the password. Repeated failures have a serial so the same
/// message still shakes and replays on every refused password.
class LockCard extends StatefulWidget {
  /// Shows owner-supplied state without changing the wallet's auth policy.
  const LockCard({
    required this.walletName,
    required this.passwordController,
    required this.onUnlock,
    this.address,
    this.busy = false,
    this.canUnlock = true,
    this.opening = false,
    this.errorMessage,
    this.incorrectPassword = false,
    this.failedAttempts = 0,
    this.attemptsRemaining,
    this.passwordFailures = 0,
    this.replay,
    this.startup,
    super.key,
  });

  /// A display name only, never a wallet path or an invented example name.
  final String walletName;

  /// An address already available to the owner; absent on a cold session.
  final String? address;

  /// Remains owned and cleared by the authentication owner.
  final TextEditingController passwordController;

  /// Requests the existing unlock flow without receiving or retaining it.
  final VoidCallback onUnlock;

  /// Covers decryption, initialisation and awaited attempt bookkeeping.
  final bool busy;

  /// False after the owner cannot persist its attempt state; no retry runs.
  final bool canUnlock;

  /// Names the existing wallet-initialisation wait after decryption.
  final bool opening;

  /// A mapped non-password failure, rather than raw library diagnostics.
  final String? errorMessage;

  /// Selects the password error paint and the refused-state capture marker.
  final bool incorrectPassword;

  /// The existing global count; this view never increments it.
  final int failedAttempts;

  /// Null means that there is no finite enabled limit to count down.
  final int? attemptsRemaining;

  /// Changes once per refused password, including identical error messages.
  final int passwordFailures;

  /// Zero or null holds the last frame. A positive initial value plays the
  /// manual-lock segment; every later change requests the same segment.
  final ValueListenable<int>? replay;

  /// The cold-start owner moves its original film into this real well.
  final StartupStageSession? startup;

  @override
  State<LockCard> createState() => _LockCardState();
}

class _LockCardState extends State<LockCard>
    with SingleTickerProviderStateMixin {
  final LaunchFilmController _film = LaunchFilmController();
  final FocusNode _passwordFocus = FocusNode(debugLabel: 'Unlock password');
  late final AnimationController _shake = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 200),
    // A failed password must still be visible when Windows animation
    // effects are disabled, just like the wallet's other motion.
    animationBehavior: AnimationBehavior.preserve,
  );
  bool _obscure = true;

  LaunchFilmController get _activeFilm => widget.startup?.film ?? _film;

  @override
  void initState() {
    super.initState();
    widget.replay?.addListener(_replay);
    if (widget.startup != null) {
      // The startup film is already playing in its single overlay host.
      // Skipping here would cut that original movie before it finishes.
      return;
    }
    if ((widget.replay?.value ?? 0) > 0) {
      _replay();
    } else {
      _film.skipToEnd();
    }
  }

  @override
  void didUpdateWidget(LockCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.busy && widget.busy) _obscure = true;
    if ((oldWidget.busy && !widget.busy) ||
        (!oldWidget.canUnlock && widget.canUnlock)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !widget.busy && widget.canUnlock) {
          _passwordFocus.requestFocus();
        }
      });
    }
    if (!identical(oldWidget.replay, widget.replay)) {
      oldWidget.replay?.removeListener(_replay);
      widget.replay?.addListener(_replay);
      if ((widget.replay?.value ?? 0) > 0) _replay();
    }
    if (oldWidget.passwordFailures != widget.passwordFailures) {
      _obscure = true;
      _shake.forward(from: 0);
      _replay();
    }
  }

  void _replay() {
    if (mounted && (widget.startup?.interactive ?? true)) {
      _activeFilm.play(from: 14);
    }
  }

  void _submit() {
    if (!widget.busy &&
        widget.canUnlock &&
        widget.passwordController.text.isNotEmpty) {
      widget.onUnlock();
    }
  }

  @override
  void dispose() {
    widget.replay?.removeListener(_replay);
    _shake.dispose();
    _film.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = AppTokens.of(context);
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        if (widget.startup case final StartupStageSession startup)
          ValueListenableBuilder<double>(
            valueListenable: startup.motion,
            child: const HeroField(),
            builder: (_, double progress, Widget? child) =>
                Opacity(opacity: progress, child: child),
          )
        else
          const HeroField(),
        LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) =>
              SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: Padding(
                    padding: tokens.lockPagePadding,
                    child: Center(
                      child: SizedBox(
                        width: tokens.lockCardWidth,
                        child: _buildMovingCard(context, tokens),
                      ),
                    ),
                  ),
                ),
              ),
        ),
      ],
    );
  }

  Widget _buildMovingCard(BuildContext context, AppTokens tokens) {
    final Widget card = _buildCard(context, tokens);
    final StartupStageSession? startup = widget.startup;
    if (startup == null) return card;
    return ValueListenableBuilder<double>(
      valueListenable: startup.motion,
      child: card,
      builder: (_, double progress, Widget? child) => Opacity(
        opacity: progress,
        child: Transform.translate(
          offset: Offset(0, tokens.launchLockRise * (1 - progress)),
          child: child,
        ),
      ),
    );
  }

  Widget _buildCard(BuildContext context, AppTokens tokens) {
    final BorderRadius radius = BorderRadius.circular(tokens.dialogRadius);
    return KeyedSubtree(
      key: const ValueKey<String>('lock_card_surface'),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: radius,
          boxShadow: tokens.lockCardShadow,
        ),
        child: FrostedSurface(
          sigma: tokens.panelBlur,
          borderRadius: radius,
          child: DecoratedBox(
            position: DecorationPosition.foreground,
            decoration: BoxDecoration(
              borderRadius: radius,
              border: Border.all(color: tokens.line),
            ),
            child: Padding(
              padding: EdgeInsets.all(tokens.glassTopEdge.width),
              // The shared glass composition clips a separate top edge.
              // A rounded border cannot paint different side colours.
              child: DecoratedBox(
                position: DecorationPosition.foreground,
                decoration: BoxDecoration(
                  border: Border(top: tokens.glassTopEdge),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    _buildWell(tokens),
                    Padding(
                      padding: tokens.lockContentPadding,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          LockWalletPicker(
                            current: LockWalletDisplayEntry(
                              name: widget.walletName,
                              address: widget.address,
                            ),
                          ),
                          SizedBox(height: tokens.panelGap),
                          _buildPassword(context, tokens),
                          if (_hasNote) ...<Widget>[
                            SizedBox(height: tokens.fieldLabelGap),
                            _buildNote(context, tokens),
                          ],
                          SizedBox(height: tokens.panelGap),
                          SizedBox(
                            // Changing the action marker preserves the film
                            // and password field.
                            key: ValueKey<String>(
                              widget.incorrectPassword
                                  ? 'lock_wrong_marker'
                                  : 'lock_screen_marker',
                            ),
                            height: tokens.lockActionHeight,
                            child: PrimaryPill(
                              key: const ValueKey<String>(
                                'wallet_unlock_button',
                              ),
                              onPressed: widget.busy || !widget.canUnlock
                                  ? null
                                  : _submit,
                              style: ButtonStyle(
                                minimumSize: WidgetStatePropertyAll<Size>(
                                  Size(0, tokens.lockActionHeight),
                                ),
                                textStyle: WidgetStatePropertyAll<TextStyle>(
                                  tokens.lockActionText,
                                ),
                              ),
                              icon: widget.busy
                                  ? SizedBox.square(
                                      dimension: tokens.lockGlyphSize,
                                      child: CircularProgressIndicator(
                                        strokeWidth: tokens.focusWidth,
                                        color: tokens.primaryButtonForeground,
                                      ),
                                    )
                                  : Icon(
                                      Icons.lock_outline,
                                      size: tokens.railIconSize,
                                    ),
                              child: Text(context.l10n.lockUnlock),
                            ),
                          ),
                          SizedBox(height: tokens.panelGap),
                          _buildLinks(context, tokens),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildWell(AppTokens tokens) {
    final StartupStageSession? startup = widget.startup;
    return MouseRegion(
      onEnter: (_) => _replay(),
      child: SizedBox(
        key: const ValueKey<String>('lock_film_well'),
        height: tokens.lockWellHeight,
        child: ClipRect(
          key: startup?.wellKey,
          child: ColoredBox(
            color: tokens.launchStageBackground,
            child: OverflowBox(
              minWidth: tokens.lockFilmWidth,
              maxWidth: tokens.lockFilmWidth,
              minHeight: tokens.lockFilmHeight,
              maxHeight: tokens.lockFilmHeight,
              child: startup == null
                  ? LaunchFilm(
                      asset: 'assets/images/launch_well.webp',
                      autoplay: false,
                      controller: _film,
                    )
                  : startup.filmInWell
                  ? startup.buildFilm()
                  : const SizedBox.expand(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPassword(BuildContext context, AppTokens tokens) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: <Widget>[
      Text(context.l10n.password.toUpperCase(), style: tokens.ledgerText),
      SizedBox(height: tokens.fieldLabelGap),
      AnimatedBuilder(
        animation: _shake,
        child: TextField(
          key: const ValueKey<String>('wallet_password_field'),
          controller: widget.passwordController,
          focusNode: _passwordFocus,
          autofocus: widget.startup?.interactive ?? true,
          enabled: !widget.busy && widget.canUnlock,
          obscureText: _obscure,
          enableSuggestions: false,
          autocorrect: false,
          style: tokens.dataText,
          onSubmitted: (_) => _submit(),
          decoration: InputDecoration(
            isDense: true,
            filled: true,
            fillColor: tokens.card2,
            contentPadding: tokens.lockFieldPadding,
            constraints: BoxConstraints(minHeight: tokens.fieldHeight),
            hintText: context.l10n.password,
            hintStyle: tokens.bodyText.copyWith(color: tokens.faint),
            enabledBorder: _passwordBorder(tokens),
            focusedBorder: _passwordBorder(tokens),
            disabledBorder: _passwordBorder(tokens),
            suffixIconConstraints: BoxConstraints.tightFor(
              width: tokens.fieldHeight,
              height: tokens.fieldHeight,
            ),
            suffixIcon: IconButton(
              tooltip: _obscure
                  ? context.l10n.lockShowPassword
                  : context.l10n.lockHidePassword,
              padding: EdgeInsets.zero,
              constraints: BoxConstraints.tightFor(
                width: tokens.fieldHeight,
                height: tokens.fieldHeight,
              ),
              onPressed: widget.busy || !widget.canUnlock
                  ? null
                  : () => setState(() => _obscure = !_obscure),
              icon: Icon(
                _obscure
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
                size: tokens.lockGlyphSize,
                color: tokens.faint,
              ),
            ),
          ),
        ),
        builder: (BuildContext context, Widget? child) => Transform.translate(
          key: const ValueKey<String>('lock_password_shake'),
          offset: Offset(
            // Two complete 4 px cycles, returning exactly to rest at 200 ms.
            _shake.isAnimating ? math.sin(_shake.value * math.pi * 4) * 4 : 0,
            0,
          ),
          child: child,
        ),
      ),
    ],
  );

  OutlineInputBorder _passwordBorder(AppTokens tokens) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(tokens.cardRadius),
    borderSide: BorderSide(
      color: widget.incorrectPassword ? tokens.error : tokens.faint,
    ),
  );

  bool get _hasNote =>
      widget.opening ||
      widget.incorrectPassword ||
      (widget.errorMessage?.isNotEmpty ?? false) ||
      (widget.failedAttempts > 0 && widget.attemptsRemaining != null);

  Widget _buildNote(BuildContext context, AppTokens tokens) {
    if (widget.opening) {
      return Text(context.l10n.lockOpening, style: tokens.compactText);
    }
    final String? error =
        widget.errorMessage ??
        (widget.incorrectPassword
            ? context.l10n.walletPasswordIncorrectError
            : null);
    final int? attempts = widget.failedAttempts > 0
        ? widget.attemptsRemaining
        : null;
    return Row(
      key: const ValueKey<String>('lock_attempt_note'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Icon(
          Icons.warning_amber_outlined,
          size: tokens.lockGlyphSize,
          color: tokens.error,
        ),
        SizedBox(width: tokens.inlineGap),
        Expanded(
          child: Text.rich(
            TextSpan(
              children: <InlineSpan>[
                if (error != null && error.isNotEmpty)
                  TextSpan(
                    text: attempts == null ? error : '$error. ',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                if (attempts != null)
                  TextSpan(text: context.l10n.lockTriesLeft(attempts)),
              ],
            ),
            style: tokens.compactText.copyWith(color: tokens.error),
          ),
        ),
      ],
    );
  }

  Widget _buildLinks(BuildContext context, AppTokens tokens) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: <Widget>[
      Flexible(
        child: SeamGate(
          seam: Seam.walletPicker,
          child: TextButton(
            onPressed: () => throw const SeamNotBuilt(Seam.walletPicker),
            style: _linkStyle(tokens),
            child: Text(context.l10n.lockAddWallet),
          ),
        ),
      ),
      SizedBox(width: tokens.inlineGap),
      Flexible(
        child: SeamGate(
          seam: Seam.passwordRecovery,
          child: TextButton(
            onPressed: () => throw const SeamNotBuilt(Seam.passwordRecovery),
            style: _linkStyle(tokens),
            child: Text(context.l10n.lockForgotPassword),
          ),
        ),
      ),
    ],
  );

  ButtonStyle _linkStyle(AppTokens tokens) => ButtonStyle(
    foregroundColor: WidgetStatePropertyAll<Color>(tokens.dim),
    textStyle: WidgetStatePropertyAll<TextStyle>(tokens.lockLinkText),
    padding: const WidgetStatePropertyAll<EdgeInsetsGeometry>(EdgeInsets.zero),
    minimumSize: const WidgetStatePropertyAll<Size>(Size.zero),
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
  );
}
