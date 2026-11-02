import 'dart:async';

import 'package:hive_ce/hive_ce.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/blocs/blocs.dart';
import 'package:zenon_syrius_wallet_flutter/l10n/app_localizations.dart';
import 'package:zenon_syrius_wallet_flutter/l10n/l10n.dart';
import 'package:zenon_syrius_wallet_flutter/main.dart' as app;
import 'package:zenon_syrius_wallet_flutter/model/model.dart';
import 'package:zenon_syrius_wallet_flutter/services/shared_prefs_service.dart';
import 'package:zenon_syrius_wallet_flutter/utils/constants.dart';
import 'package:zenon_syrius_wallet_flutter/utils/global.dart';
import 'package:zenon_syrius_wallet_flutter/utils/node_transition.dart';
import 'package:zenon_syrius_wallet_flutter/utils/wallet_context_revision.dart';
import 'package:zenon_syrius_wallet_flutter/utils/wallet_initialization.dart';
import 'package:zenon_syrius_wallet_flutter/utils/wallet_initialization_source.dart';
import 'package:zenon_syrius_wallet_flutter/utils/wallet_maintenance.dart';
import 'package:zenon_syrius_wallet_flutter/utils/wallet_maintenance_binding.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

/// A password result and its original writes remain separate evidence.
class WalletLockAttemptOutcome {
  /// The password error is never replaced by a notice or persistence error.
  const WalletLockAttemptOutcome({
    required this.committed,
    required this.exhausted,
    this.originalError,
    this.notice,
    this.counter,
    this.noticeError,
    this.decryption,
    this.error,
  });

  /// Only a successful original counter write commits the count.
  final bool committed;

  /// The unchanged positive finite limit was reached by this original write.
  final bool exhausted;

  /// The identical decrypt or initialization error.
  final Object? originalError;

  /// A notice failure cannot skip the counter write.
  final WalletMaintenanceReceipt? notice;

  /// The actual original counter write, including its exact failure.
  final WalletMaintenanceReceipt? counter;

  /// Optional history or display failure, separate from the password result.
  final Object? noticeError;

  /// The original decrypt Future retains its exact original result or error.
  final Future<dynamic>? decryption;

  /// Original counter failure or a precise ownership refusal.
  final Object? error;
}

class _CounterOwner {
  WalletLockAttempt? active;
  final List<WalletLockAttemptOutcome> archive = <WalletLockAttemptOutcome>[];
}

/// One original counter owner spans decrypt, optional notice and persistence.
class WalletLockAttempt {
  WalletLockAttempt._({
    required this.path,
    required this.originalCount,
    required this.limit,
    required this.resetRequest,
    required this.initialization,
    required this._owner,
    required this._ownsResources,
    required this._sourceIsCurrent,
    required this._ownsCounter,
    required this._writeCounter,
    required this._commitCounter,
    required this._createNotice,
    required this._writeNotice,
    required this._displayNotice,
  });

  /// Binds inert ports in tests; a busy original Box cannot admit a new try.
  static WalletLockAttempt? bind({
    required Object counterOwner,
    required String path,
    required int originalCount,
    required double? limit,
    required bool Function() ownsResources,
    required bool Function() sourceIsCurrent,
    required bool Function(int? admittedValue) ownsCounter,
    required Future<dynamic> Function(int value) writeCounter,
    required void Function(int value) commitCounter,
    required Object Function(Object error, String title) createNotice,
    Future<dynamic> Function(Object notice)? writeNotice,
    void Function(Object notice)? displayNotice,
    WalletMaintenanceRequest? resetRequest,
    WalletInitializationBinding? initialization,
  }) {
    final _CounterOwner owner = _owners[counterOwner] ??= _CounterOwner();
    if (owner.active != null ||
        !ownsResources() ||
        !sourceIsCurrent() ||
        !ownsCounter(null) ||
        originalCount < 0 ||
        (limit != null &&
            limit.isFinite &&
            limit > 0 &&
            limit == limit.truncateToDouble() &&
            originalCount >= limit)) {
      resetRequest?.cancel();
      return null;
    }
    final WalletLockAttempt attempt = WalletLockAttempt._(
      path: path,
      originalCount: originalCount,
      limit: limit,
      resetRequest: resetRequest,
      initialization: initialization,
      owner: owner,
      ownsResources: ownsResources,
      sourceIsCurrent: sourceIsCurrent,
      ownsCounter: ownsCounter,
      writeCounter: writeCounter,
      commitCounter: commitCounter,
      createNotice: createNotice,
      writeNotice: writeNotice,
      displayNotice: displayNotice,
    );
    owner.active = attempt;
    return attempt;
  }

  static final Expando<_CounterOwner> _owners = Expando<_CounterOwner>();

  /// The selected locked file path, captured before decrypt begins.
  final String path;

  /// Only this original count can be changed by this attempt.
  final int originalCount;

  /// Existing global policy, with no invented nonpositive limit.
  final double? limit;

  /// Missing Main ownership refuses automatic cleanup rather than recapturing.
  final WalletMaintenanceRequest? resetRequest;

  /// Exact startup capabilities captured before this attempt decrypts a file.
  /// Null for an initialized session, which follows the existing unlock path.
  final WalletInitializationBinding? initialization;
  final _CounterOwner _owner;
  final bool Function() _ownsResources;
  final bool Function() _sourceIsCurrent;
  final bool Function(int?) _ownsCounter;
  final Future<dynamic> Function(int) _writeCounter;
  final void Function(int) _commitCounter;
  final Object Function(Object, String) _createNotice;
  final Future<dynamic> Function(Object)? _writeNotice;
  final void Function(Object)? _displayNotice;
  Future<WalletLockAttemptOutcome>? _operation;
  Future<dynamic>? _decryption;
  bool _revoked = false;
  bool _sourceRevoked = false;

  /// The exact original decryption Future, never a recaptured retry.
  Future<dynamic>? get decryption => _decryption;

  /// Admits decryption only after the path, counter and owner were captured.
  Future<T> decrypt<T>(Future<T> Function(String originalPath) operation) {
    if (_decryption != null) {
      return _decryption! as Future<T>;
    }
    if (!isCurrent) {
      throw const WalletMaintenanceRefused('lock-origin');
    }
    final Future<T> original = operation(path);
    _decryption = original;
    return original;
  }

  /// Counter resource authority ignores only the view's disposal after write.
  bool get ownsResources {
    if (_revoked) {
      return false;
    }
    final bool lost = !_ownsResources();
    _revoked = _revoked || lost;
    return !_revoked;
  }

  /// Stale callbacks cannot display or publish an unlocked session.
  bool get isCurrent {
    if (!ownsResources || _sourceRevoked) {
      return false;
    }
    final bool lost = !_sourceIsCurrent();
    _sourceRevoked = _sourceRevoked || lost;
    return !_revoked && !_sourceRevoked;
  }

  /// Every immutable result remains available across same-Box remounts.
  List<WalletLockAttemptOutcome> get outcomes =>
      List<WalletLockAttemptOutcome>.unmodifiable(_owner.archive);

  /// Duplicate failure callbacks observe the same original operation Future.
  Future<WalletLockAttemptOutcome> fail(
    Object error,
    String title, {
    required bool incorrectPassword,
  }) => _start(error, title, incorrectPassword);

  /// A correct password resets the count before publishing its new file.
  Future<WalletLockAttemptOutcome> resetAfterDecrypt() =>
      _start(null, null, false);

  Future<WalletLockAttemptOutcome> _start(
    Object? originalError,
    String? title,
    bool incorrectPassword,
  ) {
    if (_operation != null) {
      return _operation!;
    }
    final Completer<WalletLockAttemptOutcome> completion =
        Completer<WalletLockAttemptOutcome>();
    _operation = completion.future;
    unawaited(
      _finish(originalError, title, incorrectPassword).then<void>(
        completion.complete,
        onError: completion.completeError,
      ),
    );
    return completion.future;
  }

  Future<WalletLockAttemptOutcome> _finish(
    Object? originalError,
    String? title,
    bool incorrectPassword,
  ) async {
    WalletMaintenanceReceipt? notice;
    WalletMaintenanceReceipt? counter;
    Object? failure;
    Object? noticeError;
    bool committed = false;
    bool exhausted = false;
    bool uncertainCounter = false;
    if (originalError != null &&
        title != null &&
        isCurrent &&
        _writeNotice != null) {
      Future<dynamic>? original;
      try {
        final Object event = _createNotice(originalError, title);
        original = _writeNotice(event);
        final Object? result = await original;
        notice = WalletMaintenanceReceipt(
          name: 'original-lock-notice',
          future: original,
          result: result,
        );
        if (isCurrent) {
          _displayNotice?.call(event);
        }
      } on Object catch (error, trace) {
        noticeError = error;
        if (original != null && notice == null) {
          notice = WalletMaintenanceReceipt(
            name: 'original-lock-notice',
            future: original,
            error: error,
            stackTrace: trace,
          );
        }
      }
    }
    final bool write = originalError == null || incorrectPassword;
    if (write) {
      Future<dynamic>? original;
      final int value = incorrectPassword ? originalCount + 1 : 0;
      try {
        if (!ownsResources || !_ownsCounter(null)) {
          throw const WalletMaintenanceRefused('lock-counter');
        }
        uncertainCounter = true;
        original = _writeCounter(value);
        final Object? result = await original;
        counter = WalletMaintenanceReceipt(
          name: 'original-lock-counter',
          future: original,
          result: result,
        );
        if (!ownsResources || !_ownsCounter(value)) {
          throw const WalletMaintenanceRefused('lock-counter-owner');
        }
        _commitCounter(value);
        committed = true;
        uncertainCounter = false;
        final double? threshold = limit;
        exhausted =
            incorrectPassword &&
            threshold != null &&
            threshold.isFinite &&
            threshold > 0 &&
            threshold == threshold.truncateToDouble() &&
            value >= threshold;
      } on Object catch (error, trace) {
        failure = error;
        if (original != null && counter == null) {
          counter = WalletMaintenanceReceipt(
            name: 'original-lock-counter',
            future: original,
            error: error,
            stackTrace: trace,
          );
        }
      }
    }
    final WalletLockAttemptOutcome result = WalletLockAttemptOutcome(
      originalError: originalError,
      decryption: _decryption,
      committed: committed,
      exhausted: exhausted,
      notice: notice,
      noticeError: noticeError,
      counter: counter,
      error: failure,
    );
    _owner.archive.add(result);
    if (!uncertainCounter && identical(_owner.active, this)) {
      _owner.active = null;
    }
    if (!exhausted) {
      resetRequest?.cancel();
    }
    return result;
  }
}

/// Fixed preparation boundaries; no input or backend data is observed.
enum WalletLockCapturePhase {
  /// The original preferences capture boundary.
  preferences('capture_preferences'),
  /// The original wallet context capture boundary.
  walletContext('capture_wallet_context'),
  /// The original sdk capture boundary.
  sdk('capture_sdk'),
  /// The original notifications capture boundary.
  notifications('capture_notifications'),
  /// The original resources capture boundary.
  resources('capture_resources'),
  /// The original initialization capture boundary.
  initialization('capture_initialization'),
  /// The original reset capture boundary.
  reset('capture_reset'),
  /// The original binding capture boundary.
  binding('capture_binding');

  const WalletLockCapturePhase(this.label);

  /// A fixed public progress label, never a value from a private backend.
  final String label;
}

/// Binds original preferences, error history and locked path before decrypt.
WalletLockAttempt? captureWalletLockAttempt({
  required BuildContext context,
  required bool Function() sourceIsCurrent,
  void Function(WalletLockCapturePhase)? observePhase,
}) {
  observePhase?.call(WalletLockCapturePhase.preferences);
  final String? path = kWalletPath;
  final SharedPrefsService? preferences = app.sharedPrefsService;
  if (path == null ||
      preferences == null ||
      NodeTransitions.pending ||
      !Hive.isBoxOpen(kSharedPrefsBox)) {
    return null;
  }
  final Box<dynamic> box = Hive.box<dynamic>(kSharedPrefsBox);
  final bool countExists = box.containsKey(kNumUnlockFailedAttemptsKey);
  final Object? storedCount = box.get(kNumUnlockFailedAttemptsKey);
  final int? count = countExists
      ? storedCount is int
            ? storedCount
            : null
      : 0;
  if (count == null || (kNumFailedUnlockAttempts ?? 0) != count) {
    return null;
  }
  final double? limit = kAutoEraseWalletLimit;
  final bool limitExists = box.containsKey(kAutoEraseNumAttemptsKey);
  final Object? storedLimit = box.get(kAutoEraseNumAttemptsKey);
  observePhase?.call(WalletLockCapturePhase.walletContext);
  final Object? wallet = kWalletFile;
  final int revision = WalletContextRevision.value;
  final String? selected = kSelectedAddress;
  final List<String?> addresses = List<String?>.of(kDefaultAddressList);
  final String? node = kCurrentNode;
  final int? nodeChain = kNodeChainId;
  final int chain = getChainIdentifier();
  final bool initialized = kWalletInitCompleted;
  observePhase?.call(WalletLockCapturePhase.sdk);
  final Zenon? client = app.zenon;
  final WsClient? socket = client?.wsClient;
  final LedgerApi? ledger = client?.ledger;
  final StatsApi? stats = client?.stats;
  final Client? ledgerClient = ledger?.client;
  final Client? statsClient = stats?.client;
  final String? url = socket?.url;
  final String? ledgerUrl = ledgerClient is WsClient ? ledgerClient.url : null;
  final String? statsUrl = statsClient is WsClient ? statsClient.url : null;
  observePhase?.call(WalletLockCapturePhase.notifications);
  final NotificationsBloc? notifications =
      app.sl.isRegistered<NotificationsBloc>()
      ? app.sl<NotificationsBloc>()
      : null;
  final Box<dynamic>? noticeBox = Hive.isBoxOpen(kNotificationsBox)
      ? Hive.box<dynamic>(kNotificationsBox)
      : null;
  final AppLocalizations messages = currentL10n;
  observePhase?.call(WalletLockCapturePhase.resources);
  final WalletMaintenanceResources resources = WalletMaintenanceResources(
    originalIdentities: List<Object?>.unmodifiable(<Object?>[
      preferences,
      box,
      wallet,
      client,
      socket,
      ledger,
      stats,
      ledgerClient,
      statsClient,
      notifications,
      noticeBox,
    ]),
    originalValues: List<Object?>.unmodifiable(<Object?>[
      path,
      revision,
      selected,
      ...addresses,
      node,
      nodeChain,
      chain,
      url,
      ledgerUrl,
      statsUrl,
      limit,
      limitExists,
      storedLimit,
      initialized,
    ]),
    identities: () => <Object?>[
      app.sharedPrefsService,
      if (Hive.isBoxOpen(kSharedPrefsBox))
        Hive.box<dynamic>(kSharedPrefsBox)
      else
        null,
      kWalletFile,
      app.zenon,
      client?.wsClient,
      client?.ledger,
      client?.stats,
      ledger?.client,
      stats?.client,
      if (app.sl.isRegistered<NotificationsBloc>())
        app.sl<NotificationsBloc>()
      else
        null,
      if (Hive.isBoxOpen(kNotificationsBox))
        Hive.box<dynamic>(kNotificationsBox)
      else
        null,
    ],
    values: () => <Object?>[
      kWalletPath,
      WalletContextRevision.value,
      kSelectedAddress,
      ...kDefaultAddressList,
      kCurrentNode,
      kNodeChainId,
      getChainIdentifier(),
      client?.wsClient.url,
      if (ledgerClient is WsClient) ledgerClient.url else null,
      if (statsClient is WsClient) statsClient.url else null,
      kAutoEraseWalletLimit,
      box.containsKey(kAutoEraseNumAttemptsKey),
      box.get(kAutoEraseNumAttemptsKey),
      kWalletInitCompleted,
    ],
    ready: () => !NodeTransitions.pending && box.isOpen,
  );
  observePhase?.call(WalletLockCapturePhase.initialization);
  final WalletInitializationBinding? initialization = initialized
      ? null
      : WalletInitializationSource.capture(
          decrypting: true,
          sourceIsCurrent: sourceIsCurrent,
        );
  if (!initialized && initialization == null) return null;
  observePhase?.call(WalletLockCapturePhase.reset);
  final WalletMaintenanceRequest? reset =
      WalletMaintenanceOwner.forContext(context)?.capture(
        WalletMaintenanceKind.reset,
        sourceIsCurrent: sourceIsCurrent,
      );
  observePhase?.call(WalletLockCapturePhase.binding);
  return WalletLockAttempt.bind(
    counterOwner: box,
    path: path,
    originalCount: count,
    limit: limit,
    resetRequest: reset,
    initialization: initialization,
    ownsResources: () => resources.isCurrent,
    sourceIsCurrent: sourceIsCurrent,
    ownsCounter: (int? admitted) =>
        (kNumFailedUnlockAttempts ?? 0) == count &&
        (admitted == null
            ? box.containsKey(kNumUnlockFailedAttemptsKey) == countExists &&
                  box.get(kNumUnlockFailedAttemptsKey) == storedCount
            : box.containsKey(kNumUnlockFailedAttemptsKey) &&
                  box.get(kNumUnlockFailedAttemptsKey) == admitted),
    writeCounter: (int value) => box.put(kNumUnlockFailedAttemptsKey, value),
    commitCounter: (int value) => kNumFailedUnlockAttempts = value,
    createNotice: (Object error, String title) => WalletNotification(
      title: title,
      details: messages.notificationErrorWithDetails(title, error),
      timestamp: DateTime.now().millisecondsSinceEpoch,
      type: NotificationType.error,
    ),
    writeNotice: noticeBox?.add,
    displayNotice: notifications == null
        ? null
        : (Object event) => notifications.addEvent(event as WalletNotification),
  );
}
