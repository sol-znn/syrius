import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/notifications/bell_history.dart';
import 'package:zenon_syrius_wallet_flutter/services/pending_session_approval.dart';

export 'bell_history.dart';
export 'bell_scope.dart';

/// The visible history, pending decisions and privacy state of one wallet bell.
@immutable
class BellState {
  /// Creates a private empty snapshot unless visible content is supplied.
  const BellState({
    this.records = const <BellRecord>[],
    this.runs = const <BellRun>[],
    this.approvals = const <PendingSessionApproval>[],
    this.unseen = const <String>{},
    this.private = true,
    this.historyFailed = false,
  });

  /// Individual retained events in display order.
  final List<BellRecord> records;

  /// Adjacent publication groups derived from [records].
  final List<BellRun> runs;

  /// Current connection proposals shown ahead of retained history.
  final List<PendingSessionApproval> approvals;

  /// Visible event identities that have not been rendered to the user.
  final Set<String> unseen;

  /// Whether wallet details must remain hidden.
  final bool private;

  /// Whether history could not be read, rather than being empty.
  final bool historyFailed;

  /// Exact identities represented by this displayed snapshot.
  Set<String> get identities => <String>{
    for (final BellRecord record in records) record.identity,
    for (final PendingSessionApproval proposal in approvals) proposal.identity,
  };
}

/// One shell-owned history subscription that never toasts a stored snapshot.
class BellController extends Cubit<BellState> {
  /// Owns the history listener and seen-state writes for one wallet scope.
  BellController({
    required this.history,
    required this.scope,
    required List<String> Function(String scope) readSeen,
    required this.writeSeen,
    this.approvals,
  }) : assert(scope != '', 'A bell requires a wallet and chain scope.'),
       super(const BellState()) {
    try {
      _seen.addAll(readSeen(scope));
    } on Object {
      _historyFailed = true;
    }
    _subscription = history.changes.listen(
      _onHistoryChange,
      onError: (Object error, StackTrace trace) {
        _historyFailed = true;
        _publish();
      },
    );
    approvals?.addListener(_publish);
    refresh();
  }

  /// The retained-event store owned by the application.
  final BellHistory history;

  /// The stable chain and wallet anchor for displayed and seen identities.
  final String scope;

  /// Persists a complete seen-state snapshot for [scope].
  final Future<void> Function(String scope, List<String> identities) writeSeen;

  /// The existing connection-decision owner, when WalletConnect is available.
  final PendingApprovalController? approvals;
  final Set<String> _seen = <String>{};
  final ValueNotifier<bool> _hasUnseen = ValueNotifier<bool>(false);
  final StreamController<BellRecord> _toasts =
      StreamController<BellRecord>.broadcast(sync: true);
  late final StreamSubscription<BellHistoryChange> _subscription;
  List<BellRecord> _records = const <BellRecord>[];
  Future<void> _writes = Future<void>.value();
  bool _private = true;
  bool _historyFailed = false;
  bool _closing = false;
  Future<void>? _closed;

  /// Whether the unlocked shell should show its unseen-event dot.
  ValueListenable<bool> get hasUnseen => _hasUnseen;

  /// Fresh visible inserts only; retained history is never replayed here.
  Stream<BellRecord> get toasts => _toasts.stream;

  /// The shell sets this before a lock, wallet change or chain change.
  void setPrivate({required bool value}) {
    if (isClosed || _closing || _private == value) return;
    _private = value;
    _publish();
  }

  bool _belongs(BellRecord record) =>
      record.notification.walletScope == null ||
      record.notification.walletScope == scope;

  /// Reloads retained history without treating its contents as new inserts.
  void refresh() {
    if (isClosed || _closing) return;
    try {
      final List<BellRecord> snapshot = history.read();
      // A timestamp can repeat or be absent. Original insertion order breaks
      // ties; it never becomes a deletion identity.
      final Map<Object, int> order = <Object, int>{
        for (int i = 0; i < snapshot.length; i++) snapshot[i].key: i,
      };
      snapshot.sort((BellRecord a, BellRecord b) {
        final int stamp = (b.notification.timestamp ?? 0).compareTo(
          a.notification.timestamp ?? 0,
        );
        return stamp != 0 ? stamp : order[b.key]!.compareTo(order[a.key]!);
      });
      _records = List<BellRecord>.unmodifiable(snapshot.where(_belongs));
      _historyFailed = false;
      _pruneSeen();
    } on Object {
      _historyFailed = true;
    }
    _publish();
  }

  void _onHistoryChange(BellHistoryChange change) {
    if (isClosed || _closing) return;
    final bool inserted =
        change.record != null &&
        !_records.any((BellRecord record) => record.key == change.key);
    refresh();
    final BellRecord? record = change.record;
    if (inserted && record != null && _belongs(record) && !_private) {
      _toasts.add(record);
    }
  }

  Set<String> _identities() => <String>{
    for (final BellRecord record in _records) record.identity,
    for (final PendingSessionApproval proposal
        in approvals?.value ?? const <PendingSessionApproval>[])
      if (proposal.walletScope == scope) proposal.identity,
  };

  void _pruneSeen() {
    final int before = _seen.length;
    _seen.retainAll(_identities());
    if (before != _seen.length) _persist();
  }

  /// Called after an unlocked current route actually renders this snapshot.
  void markSeen(Iterable<String> identities) {
    if (isClosed || _closing || _private) return;
    final Set<String> visible = _identities();
    final int before = _seen.length;
    _seen.addAll(identities.where(visible.contains));
    if (_seen.length != before) {
      _persist();
      _publish();
    }
  }

  void _persist() {
    final List<String> snapshot = List<String>.unmodifiable(_seen);
    _writes = _writes.then((_) async {
      try {
        await writeSeen(scope, snapshot);
      } on Object {
        // Memory retains the acknowledgment, but a failed write must not turn
        // into an unhandled future or prevent later preference writes.
      }
    });
  }

  void _publish() {
    if (isClosed) return;
    final Set<String> unseen = _identities().difference(_seen);
    _hasUnseen.value = !_private && unseen.isNotEmpty;
    emit(
      BellState(
        records: _private ? const <BellRecord>[] : _records,
        runs: _private ? const <BellRun>[] : foldBellRecords(_records, scope),
        approvals: _private
            ? const <PendingSessionApproval>[]
            : List<PendingSessionApproval>.unmodifiable(
                (approvals?.value ?? const <PendingSessionApproval>[]).where(
                  (PendingSessionApproval proposal) =>
                      proposal.walletScope == scope,
                ),
              ),
        unseen: _private ? const <String>{} : Set<String>.unmodifiable(unseen),
        private: _private,
        historyFailed: _historyFailed,
      ),
    );
  }

  /// Deletes the displayed history snapshot while retaining new arrivals.
  Future<void> clearHistory() => removeRecords(state.records);

  /// Deletes only exact records still represented by the visible snapshot.
  Future<void> removeRecords(Iterable<BellRecord> records) async {
    if (isClosed || _closing || _private) return;
    final Set<String> allowed = <String>{
      for (final BellRecord record in state.records) record.identity,
    };
    final List<BellRecord> snapshot = records
        .where(
          (BellRecord record) => allowed.contains(record.identity),
        )
        .toList(growable: false);
    if (snapshot.isEmpty) return;
    try {
      await history.deleteRecords(snapshot);
      refresh();
    } on Object {
      _historyFailed = true;
      _publish();
    }
  }

  @override
  Future<void> close() async {
    final Future<void>? closed = _closed;
    if (closed != null) return closed;
    final Completer<void> completion = Completer<void>();
    _closed = completion.future;
    try {
      await _closeOwned();
      await super.close();
      completion.complete();
    } on Object catch (error, trace) {
      completion.completeError(error, trace);
    }
    return completion.future;
  }

  Future<void> _closeOwned() async {
    if (isClosed) return;
    _private = true;
    _publish();
    _closing = true;
    approvals?.removeListener(_publish);
    await _subscription.cancel();
    await _writes;
    await _toasts.close();
    _hasUnseen.dispose();
  }
}
