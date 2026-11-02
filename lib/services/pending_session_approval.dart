import 'dart:async';

import 'package:flutter/foundation.dart';

/// A copied namespace, detached from the SDK's mutable proposal event.
@immutable
class ApprovalNamespace {
  /// Copies the offered chains, accounts, methods and events into fixed lists.
  ApprovalNamespace({
    Iterable<String> chains = const <String>[],
    Iterable<String> accounts = const <String>[],
    Iterable<String> methods = const <String>[],
    Iterable<String> events = const <String>[],
  }) : chains = List<String>.unmodifiable(chains),
       accounts = List<String>.unmodifiable(accounts),
       methods = List<String>.unmodifiable(methods),
       events = List<String>.unmodifiable(events);

  /// CAIP chain identifiers covered by this namespace.
  final List<String> chains;

  /// CAIP accounts offered by the wallet.
  final List<String> accounts;

  /// RPC methods requested or offered for the session.
  final List<String> methods;

  /// Events requested or offered for the session.
  final List<String> events;
}

/// An immutable connection proposal bound to its client and wallet context.
@immutable
class PendingSessionApproval {
  /// Copies the proposal and the exact namespaces shown before a decision.
  PendingSessionApproval({
    required this.id,
    required this.expiresAt,
    required this.name,
    required this.url,
    required this.walletScope,
    required this.clientIdentity,
    required Map<String, ApprovalNamespace> requiredNamespaces,
    required Map<String, ApprovalNamespace> optionalNamespaces,
    required Map<String, ApprovalNamespace> approvedNamespaces,
    this.busy = false,
    this.failed = false,
  }) : requiredNamespaces = Map<String, ApprovalNamespace>.unmodifiable(
         requiredNamespaces,
       ),
       optionalNamespaces = Map<String, ApprovalNamespace>.unmodifiable(
         optionalNamespaces,
       ),
       approvedNamespaces = Map<String, ApprovalNamespace>.unmodifiable(
         approvedNamespaces,
       );

  /// The proposal identifier assigned by the originating client.
  final int id;

  /// The last instant at which a new decision may start.
  final DateTime expiresAt;

  /// The proposer-reported application name.
  final String name;

  /// The proposer-reported application URL.
  final String url;

  /// The chain and wallet anchor captured when this proposal arrived.
  final String walletScope;

  /// The exact client instance that owns the original proposal.
  final Object clientIdentity;

  /// Namespaces the application requires to establish the session.
  final Map<String, ApprovalNamespace> requiredNamespaces;

  /// Additional namespaces requested by the application.
  final Map<String, ApprovalNamespace> optionalNamespaces;

  /// The exact wallet grant that an approval will submit.
  final Map<String, ApprovalNamespace> approvedNamespaces;

  /// Whether the original decision is awaiting its transport result.
  final bool busy;

  /// Whether an uncertain result has disabled further decisions.
  final bool failed;

  /// A stable identity for this proposal's displayed lifetime.
  String get identity => 'proposal:$id:${expiresAt.millisecondsSinceEpoch}';

  /// Whether the user may start a decision for this snapshot.
  bool get canDecide => !busy && !failed;

  PendingSessionApproval _with({bool? busy, bool? failed}) =>
      PendingSessionApproval(
        id: id,
        expiresAt: expiresAt,
        name: name,
        url: url,
        walletScope: walletScope,
        clientIdentity: clientIdentity,
        requiredNamespaces: requiredNamespaces,
        optionalNamespaces: optionalNamespaces,
        approvedNamespaces: approvedNamespaces,
        busy: busy ?? this.busy,
        failed: failed ?? this.failed,
      );
}

/// The established result, or the reason no established result is available.
enum ApprovalDecision {
  /// The original proposal was approved in the same context.
  approved,

  /// The original proposal was declined in the same context.
  declined,

  /// The proposal cannot accept a new decision.
  unavailable,

  /// Transport or context changes prevent claiming a final decision.
  uncertain,
}

/// Owns only the existing connection decision. It never signs or sends.
class PendingApprovalController extends ChangeNotifier
    implements ValueListenable<List<PendingSessionApproval>> {
  /// Binds decisions to context checks and the existing proposal transport.
  PendingApprovalController({
    required this._isCurrentContext,
    required this._proposalExists,
    required this._approve,
    required this._decline,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final bool Function(PendingSessionApproval) _isCurrentContext;
  final bool Function(PendingSessionApproval) _proposalExists;
  final Future<void> Function(PendingSessionApproval) _approve;
  final Future<void> Function(PendingSessionApproval) _decline;
  final DateTime Function() _now;
  final Map<int, PendingSessionApproval> _pending =
      <int, PendingSessionApproval>{};
  final Set<(Object, int)> _retired = <(Object, int)>{};
  Timer? _expiry;
  bool _disposed = false;

  @override
  List<PendingSessionApproval> get value =>
      List<PendingSessionApproval>.unmodifiable(_pending.values);

  /// Retains a fresh proposal once without reviving a retired decision.
  void enqueue(PendingSessionApproval proposal) {
    if (_disposed ||
        _pending.containsKey(proposal.id) ||
        _retired.contains((proposal.clientIdentity, proposal.id)) ||
        !proposal.expiresAt.isAfter(_now())) {
      return;
    }
    _pending[proposal.id] = proposal;
    _changed();
  }

  /// Removes an expired or withdrawn proposal without sending a decision.
  void expire(int id) {
    final PendingSessionApproval? removed = _pending.remove(id);
    if (removed == null || _disposed) return;
    _retired.add((removed.clientIdentity, id));
    _changed();
  }

  /// A context change hides stale decisions without sending an implicit answer.
  void invalidate() {
    if (_disposed) return;
    for (final PendingSessionApproval proposal in _pending.values) {
      _retired.add((proposal.clientIdentity, proposal.id));
    }
    _pending.clear();
    _changed();
  }

  /// Removes expired proposals and idle proposals missing from their client.
  void refresh() {
    if (_disposed) return;
    final List<int> stale = <int>[
      for (final PendingSessionApproval proposal in _pending.values)
        if (!proposal.expiresAt.isAfter(_now()) ||
            (!proposal.busy && !_stillExists(proposal)))
          proposal.id,
    ];
    for (final int id in stale) {
      final PendingSessionApproval proposal = _pending.remove(id)!;
      _retired.add((proposal.clientIdentity, id));
    }
    if (stale.isNotEmpty) _changed();
  }

  bool _stillExists(PendingSessionApproval proposal) {
    try {
      return _proposalExists(proposal);
    } on Object {
      return false;
    }
  }

  /// Decides the original proposal once after checking its current context.
  Future<ApprovalDecision> resolve(int id, {required bool accept}) async {
    final PendingSessionApproval? proposal = _pending[id];
    if (_disposed || proposal == null || !proposal.canDecide) {
      return ApprovalDecision.unavailable;
    }
    bool current;
    try {
      current =
          proposal.expiresAt.isAfter(_now()) &&
          _isCurrentContext(proposal) &&
          _proposalExists(proposal);
    } on Object {
      current = false;
    }
    if (!current) {
      expire(id);
      return ApprovalDecision.unavailable;
    }
    final PendingSessionApproval busy = proposal._with(busy: true);
    _pending[id] = busy;
    _changed();
    try {
      // Dispatch has no intervening await after its context/proposal check.
      await (accept ? _approve(proposal) : _decline(proposal));
      if (_disposed || !identical(_pending[id], busy)) {
        return ApprovalDecision.uncertain;
      }
      if (!_isCurrentContext(proposal)) {
        _pending.remove(id);
        _retired.add((proposal.clientIdentity, id));
        _changed();
        return ApprovalDecision.uncertain;
      }
      _pending.remove(id);
      _retired.add((proposal.clientIdentity, id));
      _changed();
      return accept ? ApprovalDecision.approved : ApprovalDecision.declined;
    } on Object {
      if (!_disposed && identical(_pending[id], busy)) {
        // A transport error may follow acceptance. Keep a disabled fact; an
        // automatic retry could authorize a second operation.
        _pending[id] = proposal._with(failed: true);
        _retired.add((proposal.clientIdentity, id));
        _changed();
      }
      return ApprovalDecision.uncertain;
    }
  }

  void _changed() {
    _expiry?.cancel();
    if (_pending.isNotEmpty) {
      final DateTime first = _pending.values
          .map((PendingSessionApproval p) => p.expiresAt)
          .reduce((DateTime a, DateTime b) => a.isBefore(b) ? a : b);
      final Duration remaining = first.difference(_now());
      _expiry = Timer(
        remaining.isNegative ? Duration.zero : remaining,
        refresh,
      );
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _expiry?.cancel();
    _pending.clear();
    _retired.clear();
    super.dispose();
  }
}
