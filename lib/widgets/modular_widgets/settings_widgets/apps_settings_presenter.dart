import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// The transport that owns an actual connection.
enum AppsConnectionKind {
  /// Consent granted to a web origin over the local bridge.
  webApp,

  /// Consent granted to a requester using the application link channel.
  link,

  /// A session retained by the WalletConnect client.
  walletConnect,
}

/// Admits one selected pairing link while its original input owner is current.
typedef AppsPairAdmission =
    Future<void> Function(
      Uri uri,
      bool Function() sourceIsCurrent,
    );

/// A detached grant. The incarnation belongs to the original backend entry.
@immutable
class AppsConnection {
  /// Freezes one observed grant and copies its exposed account identifiers.
  AppsConnection({
    required this.identity,
    required this.incarnation,
    required this.kind,
    required this.site,
    required Iterable<String> accounts,
    this.url = '',
    this.pairingTopic,
    this.expiry,
    this.acknowledged,
    this.scope = '',
  }) : accounts = List<String>.unmodifiable(accounts);

  /// The requester or session topic used to locate this original grant.
  final String identity;

  /// The backend grant generation, or identical WalletConnect session object.
  final Object incarnation;

  /// The existing transport through which this grant was established.
  final AppsConnectionKind kind;

  /// The origin or peer metadata name shown in the connected-app list.
  final String site;

  /// Accounts actually exposed by this grant, without inferred permissions.
  final List<String> accounts;

  /// The peer metadata URL, when the backend supplies one.
  final String url;

  /// The pairing associated with a WalletConnect session, when present.
  final String? pairingTopic;

  /// The backend expiry in Unix seconds; null means unavailable.
  final int? expiry;

  /// The session acknowledgement reported by WalletConnect, when available.
  final bool? acknowledged;

  /// The exact backend permission summary supplied for this row.
  final String scope;

  /// Rejects replacement grants even when their visible identifiers match.
  bool sameGrant(AppsConnection other) =>
      identity == other.identity &&
      (kind == AppsConnectionKind.walletConnect
          ? identical(incarnation, other.incarnation)
          : incarnation == other.incarnation) &&
      kind == other.kind &&
      site == other.site &&
      url == other.url &&
      pairingTopic == other.pairingTopic &&
      expiry == other.expiry &&
      acknowledged == other.acknowledged &&
      scope == other.scope &&
      listEquals(accounts, other.accounts);
}

/// A real pairing is separate from the sessions established through it.
@immutable
class AppsPairing {
  /// Captures a pairing independently of the sessions that may outlive it.
  const AppsPairing({
    required this.topic,
    required this.incarnation,
    required this.site,
    required this.url,
    required this.expiry,
    required this.active,
  });

  /// The original pairing's backend identifier, never a pairing URI.
  final String topic;

  /// The identical pairing object observed when this row was captured.
  final Object incarnation;

  /// The peer name supplied by the original pairing metadata.
  final String site;

  /// The peer metadata URL, without inferred origin ownership.
  final String url;

  /// The original pairing's expiry in Unix seconds.
  final int expiry;

  /// Whether WalletConnect currently reports the pairing as active.
  final bool active;

  /// Compares the original pairing identity and all displayed facts.
  bool samePairing(AppsPairing other) =>
      topic == other.topic &&
      identical(incarnation, other.incarnation) &&
      site == other.site &&
      url == other.url &&
      expiry == other.expiry &&
      active == other.active;
}

/// Only facts returned by the original captured sources enter this snapshot.
@immutable
class AppsSnapshot {
  /// Copies only observed connection, pairing and account-label facts.
  AppsSnapshot({
    required this.webAppsAvailable,
    required this.walletConnectAvailable,
    this.enabled = false,
    this.port,
    Iterable<AppsConnection> connections = const <AppsConnection>[],
    Iterable<AppsPairing> pairings = const <AppsPairing>[],
    Map<String, String> labels = const <String, String>{},
  }) : connections = List<AppsConnection>.unmodifiable(connections),
       pairings = List<AppsPairing>.unmodifiable(pairings),
       labels = Map<String, String>.unmodifiable(labels);

  /// Represents unavailable sources without manufacturing connected entries.
  factory AppsSnapshot.unavailable() => AppsSnapshot(
    webAppsAvailable: false,
    walletConnectAvailable: false,
  );

  /// Whether an original web-app control capability was captured.
  final bool webAppsAvailable;

  /// Whether the original WalletConnect client can provide owned actions.
  final bool walletConnectAvailable;

  /// The persisted local bridge enablement preference.
  final bool enabled;

  /// The local bridge's actual listening port, when available.
  final int? port;

  /// Original web grants and active WalletConnect sessions in one list.
  final List<AppsConnection> connections;

  /// Pairings reported separately from active sessions.
  final List<AppsPairing> pairings;

  /// Captured wallet labels used to display exposed account identifiers.
  final Map<String, String> labels;

  /// Counts only actual active WalletConnect session entries.
  int get sessionCount => connections
      .where(
        (AppsConnection row) => row.kind == AppsConnectionKind.walletConnect,
      )
      .length;
}

/// The existing backend operation recorded by a nonsecret intent.
enum AppsActionKind {
  /// Changes the persisted local bridge enablement setting.
  webApps,

  /// Revokes one web grant or disconnects one WalletConnect session.
  disconnect,

  /// Disconnects a pairing without claiming to delete its sessions.
  disconnectPairing,

  /// Pairs the captured client with one strictly selected link.
  pair,
}

/// Separates admission, persistence and original backend completion.
enum AppsActionStatus {
  /// No backend operation was admitted for the departed or unavailable owner.
  refused,

  /// The durable intent failed before a backend effect was admitted.
  saveFailed,

  /// The admitted original backend operation reported an error.
  failed,

  /// The original backend Future completed successfully.
  completed,
}

/// No URI, topic, address or requester is written in the durable intent.
@immutable
class AppsIntent {
  /// Records the action kind and journal sequence without request material.
  const AppsIntent(this.sequence, this.kind);

  /// The increasing sequence within this original settings backend.
  final int sequence;

  /// The action to be admitted after this intent is persisted.
  final AppsActionKind kind;

  /// The complete durable receipt; it contains no URI or account identifier.
  Map<String, Object> get stored => <String, Object>{
    'version': 1,
    'sequence': sequence,
    'action': kind.name,
  };
}

/// The identical original Futures and errors survive the owning view.
@immutable
class AppsActionOutcome {
  /// Retains the original persistence and effect Futures and their outcome.
  const AppsActionOutcome({
    required this.kind,
    required this.status,
    this.persistence,
    this.effect,
    this.effectResult,
    this.error,
    this.stackTrace,
  });

  /// The action attempted by the original owner.
  final AppsActionKind kind;

  /// The furthest positively established result of that attempt.
  final AppsActionStatus status;

  /// The identical intent persistence Future, if a save was admitted.
  final Future<void>? persistence;

  /// The identical original backend Future, if an effect was admitted.
  final Future<dynamic>? effect;

  /// The unchanged value returned by the original backend effect.
  final Object? effectResult;

  /// The unchanged admission, persistence or backend error.
  final Object? error;

  /// The stack trace associated with the original failure.
  final StackTrace? stackTrace;
}

/// A complete original boundary. Tests supply it without Hive or native APIs.
class AppsSettingsBinding {
  /// Captures one complete source and shares its journal across remounts.
  AppsSettingsBinding({
    required this.identity,
    required this._ownsResources,
    required this._read,
    required this.changes,
    required this._persist,
    required this._setEnabled,
    required this._disconnect,
    required this._disconnectPairing,
    required this._pair,
    this.incomingLink,
  }) : _journal = _journals[identity] ??= _AppsJournal();

  /// The original backend identity that owns the shared action journal.
  final Object identity;
  final bool Function() _ownsResources;
  final AppsSnapshot Function() _read;

  /// Backend notifications that the captured connection facts may have changed.
  final Stream<void> changes;
  final Future<void> Function(AppsIntent) _persist;
  final Future<dynamic> Function({
    required bool enabled,
    required bool Function() owns,
  })
  _setEnabled;
  final Future<dynamic> Function(AppsConnection, bool Function()) _disconnect;
  final Future<dynamic> Function(AppsPairing, bool Function())
  _disconnectPairing;
  final Future<dynamic> Function(Uri, bool Function()) _pair;

  /// The original ephemeral application-link input, never persisted here.
  final ValueNotifier<String?>? incomingLink;
  final _AppsJournal _journal;
  static final Expando<_AppsJournal> _journals = Expando<_AppsJournal>();
  bool _revoked = false;

  /// A source that leaves cannot be revived by returning to the same values.
  bool get isCurrent {
    if (_revoked) return false;
    try {
      final bool valid = _ownsResources();
      _revoked = _revoked || !valid;
      return !_revoked;
    } on Object {
      _revoked = true;
      return false;
    }
  }

  /// Remains true until the admitted original persistence and effect settle.
  bool get busy => _journal.busy;

  /// Notifies views about progress without transferring backend ownership.
  Stream<void> get journalChanges => _journal.changes.stream;

  /// Immutable terminal outcomes retained after requesting views are disposed.
  List<AppsActionOutcome> get outcomes =>
      List<AppsActionOutcome>.unmodifiable(_journal.outcomes);

  /// Reads only this source; a departed or failing backend becomes unavailable.
  AppsSnapshot read() {
    if (!isCurrent) return AppsSnapshot.unavailable();
    try {
      final AppsSnapshot snapshot = _read();
      return isCurrent ? snapshot : AppsSnapshot.unavailable();
    } on Object {
      _revoked = true;
      return AppsSnapshot.unavailable();
    }
  }

  /// Refreshing a replacement never removes a hold owned by an old action.
  bool _hasConnection(AppsConnection original) => read().connections.any(
    (AppsConnection row) => row.sameGrant(original),
  );

  bool _hasPairing(AppsPairing original) => read().pairings.any(
    (AppsPairing row) => row.samePairing(original),
  );

  /// Saves an intent before changing the original local bridge preference.
  Future<AppsActionOutcome> setEnabled({
    required bool enabled,
    required bool Function() visible,
  }) => _run(
    AppsActionKind.webApps,
    visible,
    () => read().webAppsAvailable,
    (bool Function() owns) => _setEnabled(enabled: enabled, owns: owns),
  );

  /// Disconnects only the captured grant incarnation after durable admission.
  Future<AppsActionOutcome> disconnect(
    AppsConnection connection,
    bool Function() visible,
  ) => _run(
    AppsActionKind.disconnect,
    visible,
    () => _hasConnection(connection),
    (bool Function() owns) => _disconnect(connection, owns),
  );

  /// Disconnects one original pairing without deleting or hiding its sessions.
  Future<AppsActionOutcome> disconnectPairing(
    AppsPairing pairing,
    bool Function() visible,
  ) => _run(
    AppsActionKind.disconnectPairing,
    visible,
    () => _hasPairing(pairing),
    (bool Function() owns) => _disconnectPairing(pairing, owns),
  );

  /// Admits one valid link to the original WalletConnect client after saving.
  Future<AppsActionOutcome> pair(Uri uri, bool Function() visible) => _run(
    AppsActionKind.pair,
    visible,
    () =>
        read().walletConnectAvailable && parseWalletConnectLink('$uri') != null,
    (bool Function() owns) => _pair(uri, owns),
  );

  Future<AppsActionOutcome> _run(
    AppsActionKind kind,
    bool Function() visible,
    bool Function() available,
    Future<dynamic> Function(bool Function()) effect,
  ) async {
    bool revoked = false;
    bool owns() {
      if (revoked) return false;
      try {
        return !(revoked = !isCurrent || !visible() || !available());
      } on Object {
        revoked = true;
        return false;
      }
    }

    if (_journal.busy || !owns()) {
      return AppsActionOutcome(kind: kind, status: AppsActionStatus.refused);
    }
    _journal.busy = true;
    _journal.changes.add(null);
    Future<void>? persistence;
    Future<dynamic>? originalEffect;
    bool persisted = false;
    late AppsActionOutcome outcome;
    try {
      persistence = _persist(AppsIntent(++_journal.sequence, kind));
      await persistence;
      persisted = true;
      if (!owns()) {
        outcome = AppsActionOutcome(
          kind: kind,
          status: AppsActionStatus.refused,
          persistence: persistence,
        );
      } else {
        originalEffect = effect(owns);
        final Object? result = await originalEffect;
        // Completion is the original result even when its view has gone.
        outcome = AppsActionOutcome(
          kind: kind,
          status: AppsActionStatus.completed,
          persistence: persistence,
          effect: originalEffect,
          effectResult: result,
        );
      }
    } on Object catch (error, stack) {
      outcome = AppsActionOutcome(
        kind: kind,
        status: persisted
            ? AppsActionStatus.failed
            : AppsActionStatus.saveFailed,
        persistence: persistence,
        effect: originalEffect,
        error: error,
        stackTrace: stack,
      );
    } finally {
      _journal.busy = false;
    }
    _journal.outcomes.add(outcome);
    _journal.changes.add(null);
    return outcome;
  }
}

class _AppsJournal {
  int sequence = 0;
  bool busy = false;
  final List<AppsActionOutcome> outcomes = <AppsActionOutcome>[];
  final StreamController<void> changes = StreamController<void>.broadcast(
    sync: true,
  );
}

/// Display state derived from captured facts and original action outcomes.
@immutable
class AppsSettingsState {
  /// Combines a complete observed snapshot with journal progress.
  const AppsSettingsState(this.snapshot, {this.busy = false, this.outcome});

  /// The latest facts read from the original backend.
  final AppsSnapshot snapshot;

  /// Whether an original action still owns the shared journal's busy slot.
  final bool busy;

  /// The completed action, shown only while its requesting view is current.
  final AppsActionOutcome? outcome;
}

/// Original actions finish independently of Cubit disposal.
class AppsSettingsPresenter extends Cubit<AppsSettingsState> {
  /// Subscribes to the captured source without creating replacement services.
  AppsSettingsPresenter(this.binding)
    : super(
        AppsSettingsState(
          binding?.read() ?? AppsSnapshot.unavailable(),
          busy: binding?.busy ?? false,
        ),
      ) {
    _changes = binding?.changes.listen((_) => refresh());
    _journalChanges = binding?.journalChanges.listen((_) => refresh());
  }

  /// The original source; null renders explicit unavailable capability.
  final AppsSettingsBinding? binding;
  StreamSubscription<void>? _changes;
  StreamSubscription<void>? _journalChanges;

  /// Refreshes observed facts while leaving original operation holds intact.
  void refresh() {
    if (!isClosed) {
      emit(
        AppsSettingsState(
          binding?.read() ?? AppsSnapshot.unavailable(),
          busy: binding?.busy ?? false,
        ),
      );
    }
  }

  /// Retains the original result while fencing display against stale views.
  Future<AppsActionOutcome> run(
    Future<AppsActionOutcome> Function(AppsSettingsBinding) action,
    bool Function() canDisplay,
  ) async {
    final AppsSettingsBinding? original = binding;
    if (original == null || isClosed || !canDisplay()) {
      return const AppsActionOutcome(
        kind: AppsActionKind.webApps,
        status: AppsActionStatus.refused,
      );
    }
    final Future<AppsActionOutcome> pending = action(original);
    if (!isClosed) emit(AppsSettingsState(state.snapshot, busy: true));
    final AppsActionOutcome outcome = await pending;
    if (!isClosed && original.isCurrent && canDisplay()) {
      emit(
        AppsSettingsState(
          original.read(),
          busy: original.busy,
          outcome: outcome,
        ),
      );
    }
    return outcome;
  }

  @override
  Future<void> close() async {
    await _changes?.cancel();
    await _journalChanges?.cancel();
    return super.close();
  }
}

/// Only a selected, well-formed v2 pairing URI may reach the existing client.
/// The value is deliberately absent from errors, logs and durable receipts.
Uri? parseWalletConnectLink(String input) {
  try {
    return _parseWalletConnectLink(input);
  } on FormatException {
    return null;
  }
}

Uri? _parseWalletConnectLink(String input) {
  final String text = input.trim();
  if (text.isEmpty || text.length > 8192) return null;
  final Uri? uri = Uri.tryParse(text);
  if (uri == null ||
      uri.scheme != 'wc' ||
      uri.hasAuthority ||
      uri.hasFragment) {
    return null;
  }
  final RegExp hex = RegExp(r'^[0-9a-fA-F]{64}$');
  final List<String> identity = uri.path.split('@');
  if (identity.length != 2 ||
      identity[1] != '2' ||
      !hex.hasMatch(identity[0])) {
    return null;
  }
  final Map<String, List<String>> query = uri.queryParametersAll;
  if (query['relay-protocol']?.length != 1 ||
      query['relay-protocol']?.single != 'irn' ||
      query['symKey']?.length != 1 ||
      !hex.hasMatch(query['symKey']!.single)) {
    return null;
  }
  final List<String>? expiry = query['expiryTimestamp'];
  if (expiry != null &&
      (expiry.length != 1 ||
          int.tryParse(expiry.single) == null ||
          int.parse(expiry.single) < 0)) {
    return null;
  }
  return uri;
}

/// The selected barcode, rather than another item in the capture, is paired.
Uri? selectWalletConnectLink(Iterable<String?> candidates) {
  for (final String? candidate in candidates) {
    if (candidate == null) continue;
    final Uri? selected = parseWalletConnectLink(candidate);
    if (selected != null) return selected;
  }
  return null;
}
