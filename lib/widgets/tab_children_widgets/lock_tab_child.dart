import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as path;
import 'package:zenon_syrius_wallet_flutter/l10n/l10n.dart';
import 'package:zenon_syrius_wallet_flutter/main.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/features.dart';
import 'package:zenon_syrius_wallet_flutter/utils/constants.dart';
import 'package:zenon_syrius_wallet_flutter/utils/extensions.dart';
import 'package:zenon_syrius_wallet_flutter/utils/global.dart';
import 'package:zenon_syrius_wallet_flutter/utils/init_utils.dart';
import 'package:zenon_syrius_wallet_flutter/utils/wallet_file.dart';
import 'package:zenon_syrius_wallet_flutter/utils/wallet_initialization.dart';
import 'package:zenon_syrius_wallet_flutter/utils/wallet_maintenance.dart';
import 'package:zenon_syrius_wallet_flutter/utils/wallet_maintenance_binding.dart';
import 'package:zenon_syrius_wallet_flutter/utils/wallet_maintenance_lock.dart';
import 'package:zenon_syrius_wallet_flutter/utils/wallet_utils.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/reusable_widgets/startup_stage.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/tab_children_widgets/lock_card.dart';
import 'package:znn_ledger_dart/znn_ledger_dart.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

/// Completes the optional notice before recording a refused password.
///
/// A display failure cannot skip the count or change the original password
/// classification. Persistence failures escape without a retry or success.
@visibleForTesting
Future<void> recordLockFailure({
  required bool incorrectPassword,
  required Future<void> Function() notify,
  required Future<void> Function() recordFailedAttempt,
}) async {
  await Future<void>.sync(notify).onError<Object>((Object _, StackTrace _) {});
  if (incorrectPassword) await recordFailedAttempt();
}

/// Keeps the unlocked session hidden until its successful reset is saved.
@visibleForTesting
Future<void> unlockAfterLockReset({
  required Future<void> Function() persistReset,
  required Future<void> Function() exposeSession,
}) async {
  await persistReset();
  await exposeSession();
}

/// A passive view of the genuine lock owner for bounded qualification.
///
/// The observation contains fixed booleans, a bounded visible failure count
/// lifecycle and fixed request progress. It never reads input, wallet data
/// or error text.
abstract interface class LockViewSource {
  /// Reads stored view state without callbacks, input or wallet access.
  Map<String, Object?> get lockViewSnapshot;
}

/// Owns single-wallet unlock and the existing global failed-password policy.
///
/// The card receives display data and callbacks only. It cannot read a wallet
/// file, decrypt it, initialise the app or change the attempt counter.
class LockTabChild extends StatefulWidget {
  /// Keeps the existing unlock callbacks and accepts a shell replay signal.
  const LockTabChild(
    this.afterUnlockCallback,
    this.afterInitCallback, {
    this.replay,
    this.startup,
    super.key,
  });

  /// Resumes an already initialised wallet session after decryption.
  final Future<void> Function(String) afterUnlockCallback;

  /// Opens the first wallet session after its existing initialisation flow.
  final Function() afterInitCallback;

  /// A shell-owned replay counter. Zero holds the last frame on cold entry;
  /// a positive initial value is a manual lock, and later changes replay it.
  final ValueListenable<int>? replay;

  /// Keeps cold-start authentication refused until its original film settles.
  final StartupStageSession? startup;

  @override
  State<LockTabChild> createState() => _LockTabChildState();
}

class _LockTabChildState extends State<LockTabChild>
    with WidgetsBindingObserver
    implements LockViewSource {
  final TextEditingController _passwordController = TextEditingController();
  bool _busy = false;
  bool _opening = false;
  bool _incorrectPassword = false;
  bool _attemptStorageFailed = false;
  String? _errorToUser;
  int _passwordFailures = 0;
  int _epoch = 0;
  String _unlockViewPhase = 'idle';
  int _unlockViewRequests = 0;
  bool _visible = true;
  bool _windowActive = true;
  ModalRoute<dynamic>? _route;
  FocusNode? _parentFocus;

  bool get _current =>
      mounted &&
      _windowActive &&
      _visible &&
      (_route?.isCurrent ?? true) &&
      (_parentFocus?.descendantsAreFocusable ?? true) &&
      (_parentFocus?.ancestors.every(
            (FocusNode node) => node.descendantsAreFocusable,
          ) ??
          true);

  @override
  Map<String, Object?> get lockViewSnapshot =>
      Map<String, Object?>.unmodifiable(<String, Object?>{
        'mounted': mounted,
        'current': _current,
        'window_active': _windowActive,
        'visible': _visible,
        'route_current': _route?.isCurrent ?? true,
        'focus_allows_input':
            (_parentFocus?.descendantsAreFocusable ?? true) &&
            (_parentFocus?.ancestors.every(
                  (FocusNode node) => node.descendantsAreFocusable,
                ) ?? true),
        'startup_interactive': widget.startup?.interactive ?? true,
        'busy': _busy,
        'opening': _opening,
        'incorrect_password': _incorrectPassword,
        'attempt_storage_failed': _attemptStorageFailed,
        'has_error_message': _errorToUser != null,
        'password_failures': _passwordFailures.clamp(0, 255),
        'unlock_phase': _unlockViewPhase,
        'unlock_requests': _unlockViewRequests,
        'lifecycle': WidgetsBinding.instance.lifecycleState?.name ?? 'unknown',
      });

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _route = ModalRoute.of(context);
    _parentFocus = Focus.maybeOf(context, scopeOk: true);
    _setVisible(
      TickerMode.valuesOf(context).enabled && (_route?.isCurrent ?? true),
    );
  }

  void _setVisible(bool visible) {
    if (_visible && !visible) {
      _epoch++;
    }
    _visible = visible;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_windowActive && state != AppLifecycleState.resumed) {
      _epoch++;
    }
    _windowActive = state == AppLifecycleState.resumed;
  }

  @override
  Widget build(BuildContext context) {
    final double? limit = kAutoEraseWalletLimit;
    final int failedAttempts = kNumFailedUnlockAttempts ?? 0;
    final int? remaining =
        !_attemptStorageFailed && limit != null && limit.isFinite && limit > 0
        ? (limit.toInt() - failedAttempts).clamp(0, limit.toInt())
        : null;
    final String? walletPath = kWalletPath;
    return LockCard(
      // Only the filename is display data. The presentation never receives
      // the path, and no file is opened just to show its name.
      walletName: walletPath == null ? '' : path.basename(walletPath),
      address: kDefaultAddressList.whereType<String>().firstOrNull,
      passwordController: _passwordController,
      onUnlock: _onActionButtonPressed,
      busy: _busy,
      canUnlock:
          !_attemptStorageFailed && (widget.startup?.interactive ?? true),
      opening: _opening,
      errorMessage: _errorToUser,
      incorrectPassword: _incorrectPassword,
      failedAttempts: failedAttempts,
      attemptsRemaining: remaining,
      passwordFailures: _passwordFailures,
      replay: widget.replay,
      startup: widget.startup,
    );
  }

  Future<void> _onError(
    String errorMessage,
    Object error,
    WalletLockAttempt attempt,
  ) async {
    final bool incorrectPassword = error is IncorrectPasswordException;
    final WalletLockAttemptOutcome outcome = await attempt.fail(
      error,
      errorMessage,
      incorrectPassword: incorrectPassword,
    );
    if (!mounted || !attempt.isCurrent) {
      return;
    }
    if (outcome.error != null) {
      _showAttemptStorageFailure(incorrectPassword: incorrectPassword);
      return;
    }
    setState(() {
      _opening = false;
      _incorrectPassword = incorrectPassword;
      _errorToUser = _incorrectPassword ? null : errorMessage;
      if (_incorrectPassword) _passwordFailures += 1;
    });
    if (outcome.exhausted) {
      final WalletMaintenanceRequest? request = attempt.resetRequest;
      if (request == null || !request.canApprove) {
        request?.cancel();
        _showAttemptStorageFailure(incorrectPassword: true);
        return;
      }
      handoffWalletMaintenance(request);
    }
  }

  void _showAttemptStorageFailure({required bool incorrectPassword}) {
    _attemptStorageFailed = true;
    if (!mounted) return;
    setState(() {
      _opening = false;
      _incorrectPassword = incorrectPassword;
      _errorToUser = currentL10n.lockAttemptSaveFailed;
      if (incorrectPassword) _passwordFailures += 1;
    });
  }

  Future<void> _onActionButtonPressed() async {
    if (_unlockViewRequests < 255) {
      _unlockViewRequests++;
    }
    _unlockViewPhase = 'entered';
    if (!_current ||
        !(widget.startup?.interactive ?? true) ||
        _busy ||
        _attemptStorageFailed ||
        _passwordController.text.isEmpty) {
      _unlockViewPhase = 'preflight_refused';
      return;
    }
    final int epoch = _epoch;
    bool sourceIsCurrent() => epoch == _epoch && _current;
    _unlockViewPhase = 'capture_requested';
    final WalletLockAttempt? attempt = captureWalletLockAttempt(
      context: context,
      sourceIsCurrent: sourceIsCurrent,
      observePhase: (WalletLockCapturePhase value) {
        _unlockViewPhase = value.label;
      },
    );
    _unlockViewPhase = 'capture_returned';
    if (attempt == null) {
      _unlockViewPhase = 'attempt_unavailable';
      _showAttemptStorageFailure(incorrectPassword: false);
      return;
    }
    _unlockViewPhase = 'attempt_bound';
    final String password = _passwordController.text;
    final WalletFile? lockedFile = kWalletFile;
    final WalletInitializationBinding? initialization = attempt.initialization;
    final bool needsInit = initialization != null;
    final MultipleBalanceBloc? balances =
        needsInit && sl.isRegistered<MultipleBalanceBloc>()
        ? sl<MultipleBalanceBloc>()
        : null;
    _unlockViewPhase = 'busy_mark_requested';
    bool authenticated = false;
    WalletFile? decryptedFile;
    setState(() {
      // The synchronous guard also covers Enter before the next build and
      // the awaited notification and preferences work after a failed try.
      _busy = true;
      _opening = false;
      _incorrectPassword = false;
      _errorToUser = null;
    });
    _unlockViewPhase = 'input_clear_requested';
    _passwordController.clear();
    try {
      _unlockViewPhase = 'decrypt_requested';
      final WalletFile decrypted = await attempt.decrypt<WalletFile>(
        (String originalPath) => WalletUtils.decryptWalletFile(
          originalPath,
          password,
        ),
      );
      _unlockViewPhase = 'decrypt_returned';
      decryptedFile = decrypted;
      if (!attempt.isCurrent) {
        _unlockViewPhase = 'view_revoked';
        await attempt.fail(
          const WalletMaintenanceRefused('lock-view'),
          currentL10n.walletSettingsUnavailable,
          incorrectPassword: false,
        );
        return;
      }
      _unlockViewPhase = 'reset_requested';
      final WalletLockAttemptOutcome reset = await attempt.resetAfterDecrypt();
      _unlockViewPhase = 'reset_returned';
      if (!reset.committed || reset.error != null) {
        _unlockViewPhase = 'reset_refused';
        if (attempt.isCurrent) {
          _showAttemptStorageFailure(incorrectPassword: false);
        }
        return;
      }
      if (!attempt.isCurrent || decrypted.walletPath != attempt.path) {
        _unlockViewPhase = 'result_guard_refused';
        return;
      }
      authenticated = true;
      bool openedIsCurrent() =>
          sourceIsCurrent() &&
          identical(kWalletFile, decrypted) &&
          kWalletPath == attempt.path;
      if (initialization != null) {
        setState(() => _opening = true);
        _unlockViewPhase = 'init_requested';
        await InitUtils.initWalletAfterDecryption(
          Crypto.digest(utf8.encode(password)),
          originalFile: decrypted,
          binding: initialization,
        );
        _unlockViewPhase = 'init_returned';
        if (!openedIsCurrent()) return;
        if (balances != null &&
            sl.isRegistered<MultipleBalanceBloc>() &&
            identical(sl<MultipleBalanceBloc>(), balances)) {
          balances.add(
            MultipleBalanceFetch(
              addresses: kDefaultAddressList.map((String? e) => e!).toList(),
            ),
          );
        }
      } else {
        kWalletFile = decrypted;
        _unlockViewPhase = 'session_assigned';
      }
      if (!openedIsCurrent()) return;
      _unlockViewPhase = 'callback_requested';
      if (needsInit) {
        widget.afterInitCallback();
      } else {
        await widget.afterUnlockCallback(password);
      }
      _unlockViewPhase = 'callback_returned';
      if (openedIsCurrent()) {
        setState(() {
          _incorrectPassword = false;
          _errorToUser = null;
        });
      }
    } on IncorrectPasswordException catch (error) {
      _unlockViewPhase = 'password_exception';
      if (!authenticated) {
        await _onError(kIncorrectPasswordNotificationTitle, error, attempt);
      }
    } on LedgerError catch (error) {
      _unlockViewPhase = 'ledger_exception';
      if (!authenticated) {
        await _onError('Ledger: ${error.toFriendlyString()}', error, attempt);
      }
    } on Object catch (error) {
      _unlockViewPhase = authenticated
          ? 'authenticated_exception'
          : 'other_exception';
      if (!authenticated) {
        await _onError(kUnlockFailedNotificationTitle, error, attempt);
      } else if (sourceIsCurrent() &&
          kWalletPath == attempt.path &&
          (identical(kWalletFile, decryptedFile) ||
              identical(kWalletFile, lockedFile))) {
        setState(() => _errorToUser = currentL10n.walletSettingsUnavailable);
      }
    } finally {
      if (mounted) {
        _passwordController.clear();
        setState(() {
          _busy = false;
          _opening = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _epoch++;
    WidgetsBinding.instance.removeObserver(this);
    _passwordController.dispose();
    super.dispose();
  }
}
