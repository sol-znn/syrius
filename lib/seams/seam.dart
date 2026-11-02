import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/extensions/buildcontext_extension.dart';

/// Drawn features whose backing implementation is absent from this tree.
///
/// Every value has a row in `SEAMS.md`. Remove its gate only when that
/// implementation exists; an existing wallet feature never becomes a seam.
enum Seam {
  /// Enforcing both sides of a negotiated swap offer and its quote.
  swapTerms,

  /// Finding a recipient and sending a Zap.
  zapSend,

  /// Recognising a Zap, reading its message and celebrating its receipt.
  zapReceive,

  /// Listing and switching wallets with isolated per-wallet state.
  walletPicker,

  /// Recovering access without treating the global reset flow as recovery.
  passwordRecovery,

  /// Changing a wallet password together with its encrypted recovery stores.
  passwordChangeMigration,

  /// Detecting infrastructure ownership and applying mode overrides.
  operatorModes,

  /// Comparing wallet releases and showing a newer-release notice.
  walletUpdateNotice,

  /// Unlocking through Windows Hello or Touch ID.
  biometricUnlock,

  /// Replacing the existing positive inactivity timer with locking on close.
  autoLockOnClose,

  /// Disabling the existing positive wrong-password exhaustion limit.
  wrongPasswordLimitOff,

  /// Reading and managing Sporks from the wallet.
  sporks,

  /// Estimating and sorting pillar annual returns from qualified inputs.
  pillarAprEstimate,
}

/// A missing service refuses explicitly instead of returning invented data.
class SeamNotBuilt implements Exception {
  /// Identifies the implementation that has not been built.
  const SeamNotBuilt(this.seam);

  /// The missing implementation.
  final Seam seam;

  @override
  String toString() => 'SeamNotBuilt(${seam.name})';
}

/// Runs an indirect action only when it has no missing implementation.
///
/// Palette entries and shortcuts must use this guard as well as gating their
/// control: their callbacks can run without a pointer entering [SeamGate].
/// False means refused; the callback is never invoked in that case.
bool runUnlessSeamed({required Seam? seam, required VoidCallback action}) {
  if (seam != null) {
    return false;
  }
  action();
  return true;
}

/// Keeps a drawn control's paint and layout while denying its activation.
///
/// Descendant semantics are excluded because a screen reader can invoke an
/// action without a pointer or keyboard. The outer node remains discoverable
/// as disabled. Missing services also throw [SeamNotBuilt] for direct callers.
class SeamGate extends StatefulWidget {
  /// Holds [child] behind the missing implementation identified by [seam].
  const SeamGate({required this.seam, required this.child, super.key});

  /// The missing implementation documented in `SEAMS.md`.
  final Seam seam;

  /// The control as drawn, with its normal appearance.
  final Widget child;

  @override
  State<SeamGate> createState() => _SeamGateState();
}

class _SeamGateState extends State<SeamGate> {
  final FocusNode _barrier = FocusNode(debugLabel: 'Seam gate');
  bool _focusClearScheduled = false;

  @override
  void initState() {
    super.initState();
    _scheduleFocusClear();
  }

  @override
  void didUpdateWidget(SeamGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    _scheduleFocusClear();
  }

  @override
  void activate() {
    super.activate();
    _scheduleFocusClear();
  }

  void _scheduleFocusClear() {
    if (_focusClearScheduled) {
      return;
    }
    _focusClearScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusClearScheduled = false;
      _clearFocusedDescendant();
    });
  }

  void _clearFocusedDescendant() {
    // A reparented node can remain primary even though new focus requests
    // are blocked. Unfocus the barrier's branch, leaving other controls alone.
    if (mounted && _barrier.hasFocus) {
      _barrier.unfocus();
    }
  }

  void _onFocusChange(bool focused) {
    if (focused) {
      _clearFocusedDescendant();
    }
  }

  @override
  void dispose() {
    _barrier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final String message = context.l10n.notYet;
    return Semantics(
      container: true,
      enabled: false,
      label: message,
      child: Tooltip(
        message: message,
        excludeFromSemantics: true,
        child: MouseRegion(
          cursor: SystemMouseCursors.basic,
          child: ExcludeSemantics(
            child: Focus(
              focusNode: _barrier,
              canRequestFocus: false,
              skipTraversal: true,
              descendantsAreFocusable: false,
              descendantsAreTraversable: false,
              includeSemantics: false,
              onFocusChange: _onFocusChange,
              child: AbsorbPointer(child: widget.child),
            ),
          ),
        ),
      ),
    );
  }
}
