import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/send/send.dart';

import 'package:zenon_syrius_wallet_flutter/utils/wallet_maintenance_binding.dart'
    as production;

/// Existing global cleanup policies, kept separate from wallet recovery.
enum WalletMaintenanceKind {
  /// Removes only the two reproducible cache backends.
  cache,

  /// Removes the selected original wallet file and the explicit reset boxes.
  reset,
}

/// Uncertain destructive work never becomes success through time or absence.
enum WalletMaintenanceStatus {
  /// No destructive action was admitted.
  refused,

  /// Original cleanup completed with positive owned receipts.
  completed,

  /// An admitted step or ownership transition has an uncertain outcome.
  unknown,
}

/// A refusal is safe to display through localized context without raw paths.
class WalletMaintenanceRefused implements Exception {
  /// Names a source-level missing capability, never a user's path or material.
  const WalletMaintenanceRefused(this.reason);

  /// The exact unavailable capability retained in the private result.
  final String reason;
}

/// One immutable step's actual original Future and terminal answer.
class WalletMaintenanceReceipt {
  /// The future is retained before it is awaited.
  const WalletMaintenanceReceipt({
    required this.name,
    required this.future,
    this.result,
    this.error,
    this.stackTrace,
  });

  /// A fixed operation name, not a path or a library diagnostic.
  final String name;

  /// The identical Future returned by that captured operation.
  final Future<dynamic> future;

  /// The original result, without manufacturing removal or shutdown proof.
  final Object? result;

  /// Its exact original error.
  final Object? error;

  /// The original error trace.
  final StackTrace? stackTrace;
}

/// One cleanup's immutable original receipts survive all route lifetimes.
class WalletMaintenanceOutcome {
  /// Copies only the receipt list; original results and errors stay identical.
  WalletMaintenanceOutcome({
    required this.status,
    required List<WalletMaintenanceReceipt> receipts,
    this.error,
  }) : receipts = List<WalletMaintenanceReceipt>.unmodifiable(receipts);

  /// Unknown never means the original cleanup was rolled back.
  final WalletMaintenanceStatus status;

  /// Every admitted original remains inspectable, including failed steps.
  final List<WalletMaintenanceReceipt> receipts;

  /// The original refusal or failure, never a display replacement.
  final Object? error;
}

/// One captured effect. Its closure must not resolve new global resources.
class WalletMaintenanceAction {
  /// Tests inject inert operations; production binds original resource handles.
  const WalletMaintenanceAction({required this.name, required this.run});

  /// A fixed journal step name.
  final String name;

  /// Returns the actual original Future for this operation.
  final Future<dynamic> Function() run;
}

/// The existing shared transition lease, with no timeout or automatic release.
abstract interface class WalletMaintenanceTransition {
  /// The fixed acquisition increment, bound before synchronous observers.
  int get revision;

  /// Only this original owner can release its quarantine.
  bool get isOwner;

  /// Successful verified cleanup may release this original transition.
  bool complete();
}

/// Positive quiescence is supplied by owners, never guessed from a timer.
class WalletMaintenanceWriters {
  /// Every identity is captured before the question or decrypt attempt.
  const WalletMaintenanceWriters({
    required this.sender,
    this.htlcHandler,
    this.autoUnlockWorker,
    this.autoReceiveWorker,
    this.notifications,
  });

  /// The exact shell sender whose original close Future can be observed.
  final SendTransactionBloc sender;

  /// The original periodic HTLC handler, if registered.
  final Object? htlcHandler;

  /// The original direct-publication HTLC worker, if registered.
  final Object? autoUnlockWorker;

  /// The original automatic receive owner, if registered.
  final Object? autoReceiveWorker;

  /// The original notification owner can independently await a Box write.
  final Object? notifications;
}

/// W02 can provide a positive pause/drain receipt for these exact originals.
typedef WalletMaintenanceQuiescence =
    Future<bool> Function(WalletMaintenanceWriters writers);

/// Resource ownership is separate from the source view's route lifetime.
abstract interface class WalletMaintenanceSession {
  /// Original wallet, path, client, preferences, Box and writers still own.
  bool get ownsResources;

  /// False when an original backend or positive writer drain is unavailable.
  bool get cleanupAvailable;

  /// Reset's original wallet/path/init state has positively reached cleared.
  bool get resetCleared;

  /// The monotonic revision is checked against only known owned increments.
  int get revision;

  /// Frozen before production capture can notify any synchronous observers.
  int get capturedRevision;

  /// Acquires the shared transport quarantine once.
  WalletMaintenanceTransition? beginTransition();

  /// Each exact writer Future is journaled separately before cleanup.
  List<WalletMaintenanceAction> get drains;

  /// Immutable captured actions, without names resolved against new globals.
  List<WalletMaintenanceAction> get actions;
}

/// Positive reset completion may be transferred once to a fresh startup owner.
class WalletMaintenanceStartupReceipt {
  WalletMaintenanceStartupReceipt._(this._request, this.route);

  final WalletMaintenanceRequest _request;

  /// Only the original Splash may consume this transfer.
  final Route<dynamic> route;
  bool _claimed = false;

  /// A fresh startup must claim before it changes any global resources.
  bool claim() {
    if (_claimed || !_request.canNavigate || !_request._session.resetCleared) {
      return false;
    }
    _claimed = true;
    return true;
  }
}

/// A separate startup owner must bind its new resources at positive transfer.
/// Absence refuses re-entry; maintenance never substitutes global startup.
typedef WalletMaintenanceStartup =
    Future<bool> Function(WalletMaintenanceStartupReceipt receipt);

/// Registered by the exact Main route, independent of covered child questions.
class WalletMaintenanceOwner {
  /// Optional source injection does not construct a wallet or native service.
  WalletMaintenanceOwner({
    this.quiescence,
    this._capture,
  });

  /// Every captured writer needs an original positive terminal drain.
  final WalletMaintenanceQuiescence? quiescence;
  final WalletMaintenanceSession? Function(
    WalletMaintenanceKind,
    SendTransactionBloc,
  )?
  _capture;
  NavigatorState? _navigator;
  TransitionRoute<dynamic>? _route;
  SendTransactionBloc? _sender;
  bool Function()? _isCurrent;
  WalletMaintenanceRequest? _pending;
  bool _disposed = false;

  static final Expando<WalletMaintenanceOwner> _owners =
      Expando<WalletMaintenanceOwner>();
  static final Map<WalletMaintenanceTransition, WalletMaintenanceRequest>
  _held = <WalletMaintenanceTransition, WalletMaintenanceRequest>{};

  /// An uncertain admitted original survives route disposal and remounts.
  static List<WalletMaintenanceRequest> get retainedUncertainty =>
      List<WalletMaintenanceRequest>.unmodifiable(_held.values);

  /// Finds only a registered owner; absence never recaptures another wallet.
  static WalletMaintenanceOwner? forContext(BuildContext context) {
    final NavigatorState? navigator = Navigator.maybeOf(
      context,
      rootNavigator: true,
    );
    return navigator == null ? null : _owners[navigator];
  }

  /// Main binds its exact route and sender before a child can ask a question.
  void attach({
    required NavigatorState navigator,
    required Route<dynamic>? route,
    required SendTransactionBloc sender,
    required bool Function() isCurrent,
  }) {
    if (_disposed || route is! TransitionRoute<dynamic>) {
      return;
    }
    if (_route != null &&
        (!identical(_route, route) || !identical(_navigator, navigator))) {
      _pending?.revoke();
      return;
    }
    _navigator = navigator;
    _route = route;
    _sender = sender;
    _isCurrent = isCurrent;
    _owners[navigator] = this;
  }

  /// Captures resources synchronously before an owned question or decrypt.
  WalletMaintenanceRequest? capture(
    WalletMaintenanceKind kind, {
    required bool Function() sourceIsCurrent,
  }) {
    final NavigatorState? navigator = _navigator;
    final TransitionRoute<dynamic>? route = _route;
    final SendTransactionBloc? sender = _sender;
    if (_disposed ||
        navigator == null ||
        route == null ||
        sender == null ||
        !route.isCurrent ||
        !(_isCurrent?.call() ?? false) ||
        !sourceIsCurrent()) {
      return null;
    }
    if (_pending != null) {
      return null;
    }
    final WalletMaintenanceSession? session = _capture == null
        ? production.captureWalletMaintenanceSession(
            kind: kind,
            sender: sender,
            quiescence: quiescence,
          )
        : _capture(kind, sender);
    if (session == null ||
        !session.ownsResources ||
        session.revision != session.capturedRevision) {
      return null;
    }
    return _pending = WalletMaintenanceRequest._(
      this,
      kind,
      session,
      navigator,
      route,
      sourceIsCurrent,
    );
  }

  /// Called immediately before Main's existing single revision invalidation.
  void beforeDispose() => _pending?._beforeOwnerDispose();

  /// Called immediately after that invalidation, before unrelated teardown.
  void afterDispose() {
    _disposed = true;
    _pending?._afterOwnerDispose();
    final NavigatorState? navigator = _navigator;
    if (navigator != null && identical(_owners[navigator], this)) {
      _owners[navigator] = null;
    }
  }
}

/// A one-use capability; saved callbacks observe only its original Future.
class WalletMaintenanceRequest {
  WalletMaintenanceRequest._(
    this._owner,
    this.kind,
    this._session,
    this.navigator,
    this.sourceRoute,
    this._sourceIsCurrent,
  ) : _expectedRevision = _session.capturedRevision {
    sourceRoute.secondaryAnimation?.addStatusListener(_sourceAnimationChanged);
  }

  final WalletMaintenanceOwner _owner;
  final WalletMaintenanceSession _session;
  final bool Function() _sourceIsCurrent;

  /// The original explicit policy.
  final WalletMaintenanceKind kind;

  /// Navigation never resolves another Navigator after an await.
  final NavigatorState navigator;

  /// The original Main route must positively complete disposal.
  final TransitionRoute<dynamic> sourceRoute;
  final Completer<WalletMaintenanceOutcome> _completion =
      Completer<WalletMaintenanceOutcome>();
  final List<WalletMaintenanceReceipt> _receipts = <WalletMaintenanceReceipt>[];
  Route<dynamic>? _question;
  Route<dynamic>? _splash;
  WalletMaintenanceTransition? _transition;
  int _expectedRevision;
  bool _revoked = false;
  bool _handoff = false;
  bool _installationConsumed = false;
  bool _installingSplash = false;
  bool _beforeDisposal = false;
  bool _acknowledged = false;
  bool _routeCompleted = false;
  bool _filmCompleted = false;
  bool _started = false;
  bool _startupTransferred = false;
  WalletMaintenanceStatus? _status;
  Future<dynamic>? _sourceCompletion;

  /// The identical original Main route completion, observed after handoff.
  Future<dynamic>? get sourceCompletion => _sourceCompletion;

  void _sourceAnimationChanged(AnimationStatus status) {
    if (!_handoff &&
        _question == null &&
        (status == AnimationStatus.forward ||
            status == AnimationStatus.completed)) {
      revoke();
    }
  }

  /// The same Future is returned before and after every lifecycle transition.
  Future<WalletMaintenanceOutcome> get settlement => _completion.future;

  /// Positive cleanup availability is checked before taking Main away.
  bool get canApprove =>
      !_completion.isCompleted &&
      !_revoked &&
      !_handoff &&
      _session.cleanupAvailable &&
      _session.ownsResources &&
      _session.revision == _expectedRevision &&
      _sourceIsCurrent() &&
      (_question?.isCurrent ?? sourceRoute.isCurrent);

  /// Reserves this exact question before it is pushed.
  bool reserveQuestion(Route<dynamic> route) {
    if (_question != null || !sourceRoute.isCurrent || !_sourceCurrent) {
      return false;
    }
    _question = route;
    return true;
  }

  bool get _sourceCurrent =>
      !_revoked &&
      !_completion.isCompleted &&
      _session.ownsResources &&
      _session.revision == _expectedRevision &&
      _sourceIsCurrent() &&
      (_owner._isCurrent?.call() ?? false);

  /// Reserves the exact destination and fixed lease revision before navigation.
  bool reserveSplash(Route<dynamic> route) {
    if (!canApprove || _splash != null) {
      return false;
    }
    final int originalRevision = _expectedRevision;
    _expectedRevision = originalRevision + 1;
    final WalletMaintenanceTransition? transition = _session.beginTransition();
    _transition = transition;
    if (transition == null) {
      cancel();
      return false;
    }
    WalletMaintenanceOwner._held[transition] = this;
    if (transition.revision != _expectedRevision || !_resourcesCurrent) {
      revoke();
      return false;
    }
    _splash = route;
    _handoff = true;
    final Future<dynamic> original = sourceRoute.completed;
    _sourceCompletion = original;
    unawaited(
      original.then<void>(
        (dynamic _) {
          _routeCompleted = true;
          _maybeRun();
        },
        onError: (Object error, StackTrace _) {
          _finish(WalletMaintenanceStatus.unknown, error);
        },
      ),
    );
    return true;
  }

  /// Admits one synchronous installation of the exact reserved destination.
  ///
  /// Only its original question may temporarily cover Splash during this call.
  /// Admission is not a disposal, film, drain or cleanup completion receipt.
  bool installReservedSplash(Route<dynamic> route, VoidCallback install) {
    if (_installationConsumed ||
        _completion.isCompleted ||
        _revoked ||
        !_handoff ||
        !identical(route, _splash) ||
        !navigator.mounted) {
      return false;
    }
    // Reserve before original authority callbacks can re-enter this method.
    _installationConsumed = true;
    if (_transition == null ||
        !_resourcesCurrent ||
        _revoked ||
        _completion.isCompleted ||
        !navigator.mounted) {
      revoke();
      return false;
    }
    _installingSplash = true;
    try {
      install();
      return true;
    } finally {
      _installingSplash = false;
    }
  }

  /// An exact owned question may be covered only by its reserved destination.
  void routeCovered(Route<dynamic> route, Route<dynamic>? next) {
    if (next == null) {
      return;
    }
    if (identical(route, _question) && identical(next, _splash) && _handoff) {
      return;
    }
    if (_installingSplash &&
        identical(route, _splash) &&
        identical(next, _question)) {
      return;
    }
    if (identical(route, _question) || identical(route, _splash)) {
      revoke();
    }
  }

  /// Saved callbacks cannot revive a popped original question or destination.
  void routeLeft(Route<dynamic> route) {
    if (identical(route, _splash) ||
        (identical(route, _question) && !_handoff)) {
      revoke();
    }
  }

  /// True only while the originally reserved question owns the top route.
  bool ownsQuestion(Route<dynamic>? route) =>
      identical(route, _question) && canApprove;

  /// Cancel also works for a positively owned but unavailable question.
  bool ownsCancellation(Route<dynamic>? route) =>
      !_completion.isCompleted &&
      !_handoff &&
      identical(route, _question) &&
      (route?.isCurrent ?? false);

  /// Original navigation errors remain separate from cleanup receipts.
  void navigationFailed(Object error) {
    _revoked = true;
    if (!_started) {
      _finish(
        _transition == null
            ? WalletMaintenanceStatus.refused
            : WalletMaintenanceStatus.unknown,
        error,
      );
    }
  }

  /// Selects exact-route navigation before the first handoff mutation.
  bool get questionIsCurrent => _question?.isCurrent ?? false;

  /// The reserved question is removed only after replacing its original Main.
  Route<dynamic>? get questionRoute => _question;

  /// A successful reservation is one-use, including direct saved callbacks.
  bool get handoffReserved => _handoff;

  /// No time, route absence or SDK acceptance can manufacture this receipt.
  WalletMaintenanceStartupReceipt? takeStartupReceipt(Route<dynamic>? route) {
    if (_startupTransferred ||
        _status != WalletMaintenanceStatus.completed ||
        kind != WalletMaintenanceKind.reset ||
        !identical(route, _splash) ||
        !canNavigate ||
        !_session.resetCleared ||
        route == null) {
      return null;
    }
    _startupTransferred = true;
    return WalletMaintenanceStartupReceipt._(this, route);
  }

  bool get _resourcesCurrent =>
      !_revoked &&
      _session.ownsResources &&
      _session.revision == _expectedRevision &&
      (_transition?.isOwner ?? true);

  void _beforeOwnerDispose() {
    if (!_handoff || !_resourcesCurrent) {
      revoke();
      return;
    }
    // Bind before synchronous revision observers run. Never adopt latest.
    _expectedRevision++;
    _beforeDisposal = true;
  }

  void _afterOwnerDispose() {
    if (!_beforeDisposal || !_resourcesCurrent) {
      revoke();
      return;
    }
    _acknowledged = true;
    _maybeRun();
  }

  /// Only the original destination's film may unlock the admitted handoff.
  Future<WalletMaintenanceOutcome> filmDone(Route<dynamic>? route) {
    if (!identical(route, _splash)) {
      revoke();
      return settlement;
    }
    _filmCompleted = true;
    _maybeRun();
    return settlement;
  }

  /// Exact owned route coverage revokes synchronously, even after rapid return.
  void revoke() {
    _revoked = true;
    if (!_started) {
      _finish(
        _transition == null
            ? WalletMaintenanceStatus.refused
            : WalletMaintenanceStatus.unknown,
        const WalletMaintenanceRefused('authority'),
      );
    }
  }

  /// A declined pre-admission question never releases an uncertain lease.
  void cancel() {
    if (_handoff || _transition != null) {
      revoke();
      return;
    }
    _finish(WalletMaintenanceStatus.refused);
  }

  /// Only this original destination may exit or navigate after cleanup.
  bool get canNavigate =>
      !_revoked &&
      navigator.mounted &&
      _session.ownsResources &&
      _session.revision == _expectedRevision &&
      (_splash?.isCurrent ?? false) &&
      (_splash?.isActive ?? false);

  void _maybeRun() {
    if (_started ||
        _completion.isCompleted ||
        !_handoff ||
        !_acknowledged ||
        !_routeCompleted ||
        !_filmCompleted) {
      return;
    }
    _started = true;
    unawaited(_run());
  }

  Future<void> _run() async {
    try {
      _require();
      for (final WalletMaintenanceAction drain in _session.drains) {
        _require();
        await _observe(drain.name, drain.run);
        _require();
      }
      for (final WalletMaintenanceAction action in _session.actions) {
        _require();
        await _observe(action.name, action.run);
        _require();
      }
      final WalletMaintenanceTransition? transition = _transition;
      if (transition == null || !transition.isOwner) {
        throw const WalletMaintenanceRefused('transition');
      }
      // Bind the one known release increment before synchronous observers.
      _expectedRevision++;
      if (!transition.complete() ||
          _session.revision != _expectedRevision ||
          !_session.ownsResources) {
        throw const WalletMaintenanceRefused('release');
      }
      _finish(WalletMaintenanceStatus.completed);
    } on Object catch (error) {
      _finish(WalletMaintenanceStatus.unknown, error);
    }
  }

  void _require() {
    if (!_resourcesCurrent || !canNavigate) {
      throw const WalletMaintenanceRefused('authority');
    }
  }

  Future<void> _observe(
    String name,
    Future<dynamic> Function() operation,
  ) async {
    final Future<dynamic> original = operation();
    Object? result;
    try {
      result = await original;
    } on Object catch (error, trace) {
      _receipts.add(
        WalletMaintenanceReceipt(
          name: name,
          future: original,
          error: error,
          stackTrace: trace,
        ),
      );
      rethrow;
    }
    _receipts.add(
      WalletMaintenanceReceipt(
        name: name,
        future: original,
        result: result,
      ),
    );
    if (result == false) {
      throw const WalletMaintenanceRefused('positive-receipt');
    }
  }

  void _finish(WalletMaintenanceStatus status, [Object? error]) {
    if (_completion.isCompleted) {
      return;
    }
    sourceRoute.secondaryAnimation?.removeStatusListener(
      _sourceAnimationChanged,
    );
    _status = status;
    if (status == WalletMaintenanceStatus.completed && _transition != null) {
      WalletMaintenanceOwner._held.remove(_transition);
    }
    _completion.complete(
      WalletMaintenanceOutcome(
        status: status,
        receipts: _receipts,
        error: error,
      ),
    );
    if (_transition == null && identical(_owner._pending, this)) {
      _owner._pending = null;
    }
  }
}
