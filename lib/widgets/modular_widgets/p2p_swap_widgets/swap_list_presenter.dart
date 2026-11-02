import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:zenon_syrius_wallet_flutter/model/p2p_swap/p2p_swap.dart';

/// Public persisted facts only. Unlock material never enters the list model.
class SwapListRecord {
  /// Copies only public persisted facts; no preimage or signer capability fits
  /// this list record.
  const SwapListRecord({
    required this.id,
    required this.chainId,
    required this.direction,
    required this.selfAddress,
    required this.counterpartyAddress,
    required this.fromAmount,
    required this.fromStandard,
    required this.fromSymbol,
    required this.fromDecimals,
    required this.started,
    required this.state,
    required this.initialDepositId,
    required this.initialExpiration,
    required this.hashLock,
    required this.hashType,
    this.counterpartyDepositId,
    this.counterpartyExpiration,
  });

  /// Exact catalogue key, retained for row ownership checks.
  final String id;

  /// Chain recorded by the original catalogue.
  final int chainId;

  /// Whether this wallet created the initial or counterdeposit.
  final P2pSwapDirection direction;

  /// Original wallet member that owns this row's sending leg.
  final String selfAddress;

  /// Recorded other party, verified separately by confirmed deposit proofs.
  final String counterpartyAddress;

  /// Exact base-unit amount recorded for the sending leg.
  final BigInt fromAmount;

  /// Recorded sending token standard.
  final String fromStandard;

  /// Recorded sending symbol, requiring matching proof for a proven row value.
  final String fromSymbol;

  /// Recorded sending precision, checked against confirmed token metadata.
  final int fromDecimals;

  /// Recorded start timestamp used for stable list ordering.
  final int started;

  /// Historical state label; it does not authorize a financial action.
  final P2pSwapState state;

  /// Exact original initial deposit identifier.
  final String initialDepositId;

  /// Recorded initial expiration, requiring fresh proof for current countdowns.
  final int initialExpiration;

  /// Recorded counterdeposit identifier, absent until independently discovered.
  final String? counterpartyDepositId;

  /// Recorded counterdeposit expiration, when established.
  final int? counterpartyExpiration;

  /// Public digest that binds both deposit legs.
  final String hashLock;

  /// Recorded SDK hash algorithm identifier.
  final int hashType;

  /// Deposit sent by this wallet, according to its recorded direction.
  String? get ownDepositId => direction == P2pSwapDirection.outgoing
      ? initialDepositId
      : counterpartyDepositId;

  /// Deposit that this wallet may receive, requiring independent chain proof.
  String? get receiveDepositId => direction == P2pSwapDirection.outgoing
      ? counterpartyDepositId
      : initialDepositId;

  /// Whether recorded terminal history may enter the guarded deletion flow.
  bool get canDelete =>
      state == P2pSwapState.completed || state == P2pSwapState.unsuccessful;
}

/// A confirmed exact Create block from the captured original ledger.
class SwapDepositProof {
  /// Stores public facts copied from one exact confirmed Create block.
  const SwapDepositProof({
    required this.id,
    required this.chainId,
    required this.sender,
    required this.recipient,
    required this.amount,
    required this.standard,
    required this.symbol,
    required this.decimals,
    required this.expiration,
    required this.hashLock,
    required this.hashType,
    required this.confirmedAt,
  });

  /// Exact Create user-send hash used as the deposit identifier.
  final String id;

  /// Chain positively reported by the confirmed block.
  final int chainId;

  /// Create sender and time-locked reclaim owner.
  final String sender;

  /// Create hash-locked withdrawal recipient.
  final String recipient;

  /// Exact confirmed transferred amount in base units.
  final BigInt amount;

  /// Exact confirmed transferred token standard.
  final String standard;

  /// Symbol from matching confirmed token metadata.
  final String symbol;

  /// Precision from matching confirmed token metadata.
  final int decimals;

  /// Expiration encoded in the exact Create call.
  final int expiration;

  /// Public digest encoded in the exact Create call.
  final String hashLock;

  /// SDK hash algorithm encoded in that Create call.
  final int hashType;

  /// Positive momentum timestamp of the confirmed Create.
  final int confirmedAt;

  /// Checks the exact deposit, parties, hash terms and expected sending facts
  /// before associating this proof with a persisted public row.
  bool belongsTo(SwapListRecord record, {required bool sending}) =>
      id == (sending ? record.ownDepositId : record.receiveDepositId) &&
      chainId == record.chainId &&
      amount > BigInt.zero &&
      decimals >= 0 &&
      decimals <= 255 &&
      symbol.isNotEmpty &&
      sender == (sending ? record.selfAddress : record.counterpartyAddress) &&
      recipient ==
          (sending ? record.counterpartyAddress : record.selfAddress) &&
      hashLock == record.hashLock &&
      hashType == record.hashType &&
      expiration ==
          (id == record.initialDepositId
              ? record.initialExpiration
              : record.counterpartyExpiration) &&
      confirmedAt > 0 &&
      expiration > confirmedAt &&
      (!sending ||
          (amount == record.fromAmount &&
              standard == record.fromStandard &&
              decimals == record.fromDecimals));
}

/// Only a positive current HTLC read may supply a current expiration.
class SwapLiveDeposit {
  /// Copies a positive current getById result without inventing absent facts.
  const SwapLiveDeposit({
    required this.id,
    required this.expiration,
    required this.sender,
    required this.recipient,
    required this.amount,
    required this.standard,
    required this.hashLock,
    required this.hashType,
  });

  /// Exact current deposit identifier.
  final String id;

  /// Current contract expiration, usable only with a matching Create proof.
  final int expiration;

  /// Current time-locked reclaim owner.
  final String sender;

  /// Current hash-locked withdrawal recipient.
  final String recipient;

  /// Exact current deposit amount in base units.
  final BigInt amount;

  /// Exact current token standard.
  final String standard;

  /// Current public hash-lock digest.
  final String hashLock;

  /// Current SDK hash algorithm identifier.
  final int hashType;

  /// Requires all current deposit facts to agree with the confirmed Create.
  bool matches(SwapDepositProof proof) =>
      id == proof.id &&
      expiration == proof.expiration &&
      sender == proof.sender &&
      recipient == proof.recipient &&
      amount == proof.amount &&
      standard == proof.standard &&
      hashLock == proof.hashLock &&
      hashType == proof.hashType;
}

/// A finite slice of one original complete store snapshot.
class SwapListPage {
  /// Freezes one bounded page from a complete captured catalogue.
  SwapListPage({
    required this.total,
    required this.more,
    required Iterable<SwapListRecord> records,
  }) : records = List<SwapListRecord>.unmodifiable(records);

  /// Exact size of the complete original catalogue.
  final int total;

  /// Whether that same original snapshot contains another page.
  final bool more;

  /// Immutable public records for this page.
  final List<SwapListRecord> records;
}

/// Captured resources and independently bound readers. No callback recaptures.
class SwapListBinding {
  /// Freezes public membership and every original read and deletion capability.
  SwapListBinding({
    required this.identity,
    required this.chainId,
    required this.selected,
    required Iterable<String> members,
    required this.ownsResources,
    required this.catalogueIsCurrent,
    required this.rowIsCurrent,
    required this.readPage,
    required this.readChainTime,
    required this.readDeposit,
    required this.readLiveDeposit,
    required this.deleteRecords,
  }) : members = List<String>.unmodifiable(members);

  /// Original encrypted catalogue Box identity for shared deletion admission.
  final Object identity;

  /// Positive chain captured with the original store and APIs.
  final int chainId;

  /// Original selected member, used to guard wallet-context changes.
  final String selected;

  /// Complete immutable original wallet membership.
  final List<String> members;

  /// Monotonic original wallet, Box, API and transport ownership check.
  final bool Function() ownsResources;

  /// Whether the complete captured catalogue still matches its original bytes.
  final bool Function() catalogueIsCurrent;

  /// Whether this exact rendered record still matches its original bytes.
  final bool Function(SwapListRecord) rowIsCurrent;

  /// Bounded pages over one complete original catalogue snapshot.
  final Future<SwapListPage> Function(int page, int size) readPage;

  /// Positive original chain timestamp, with no local-clock fallback.
  final Future<int> Function() readChainTime;

  /// Exact confirmed Create proof, or an honest unavailable result.
  final Future<SwapDepositProof?> Function(String id) readDeposit;

  /// Current live deposit facts, kept separate from persisted history.
  final Future<SwapLiveDeposit?> Function(String id) readLiveDeposit;

  /// Original serial deletion capability for exact confirmed inactive rows.
  final Future<dynamic> Function(List<String> ids) deleteRecords;
}

/// A refusal carries no wallet or backend diagnostics into presentation.
class SwapListRefused implements Exception {
  /// Reports a fixed ownership refusal without raw backend diagnostics.
  const SwapListRefused();
}

/// The original Future and unchanged completion survive disposal of a view.
class SwapListOutcome {
  /// Retains the identical original Future before any asynchronous observation.
  SwapListOutcome(this.operation);

  /// Actual original read or write Future.
  final Future<dynamic> operation;

  /// Unchanged successful result, if established.
  Object? result;

  /// Unchanged original failure, retained even after view disposal.
  Object? error;

  /// Original trace associated with [error].
  StackTrace? stackTrace;

  /// Whether observation reached a positive or negative terminal result.
  bool completed = false;

  /// Observes the original Future and forwards its unchanged result or failure.
  Future<dynamic> settle() async {
    try {
      return result = await operation;
    } on Object catch (value, trace) {
      error = value;
      stackTrace = trace;
      rethrow;
    } finally {
      completed = true;
    }
  }
}

/// One immutable public row. Stored history labels are not chain authority.
class SwapListRow {
  /// Joins public history with only independently matching chain facts.
  const SwapListRow({
    required this.record,
    this.sending,
    this.receiving,
    this.currentExpiration,
    this.chainTime,
  });

  /// Public recorded history used for labels and exact row ownership.
  final SwapListRecord record;

  /// Independently confirmed sending deposit, when positively established.
  final SwapDepositProof? sending;

  /// Independently confirmed receiving deposit, when positively established.
  final SwapDepositProof? receiving;

  /// Expiration from a current deposit that matches its confirmed Create.
  final int? currentExpiration;

  /// Positive captured chain time, absent when unavailable.
  final int? chainTime;

  /// Rates are exact terminating decimals, never a rounded quote.
  String? get rate {
    final SwapDepositProof? from = sending;
    final SwapDepositProof? to = receiving;
    if (from == null || to == null) return null;
    BigInt numerator = to.amount * BigInt.from(10).pow(from.decimals);
    BigInt denominator = from.amount * BigInt.from(10).pow(to.decimals);
    if (denominator <= BigInt.zero) return null;
    final BigInt gcd = numerator.gcd(denominator);
    numerator ~/= gcd;
    denominator ~/= gcd;
    final String whole = (numerator ~/ denominator).toString();
    BigInt remainder = numerator.remainder(denominator);
    final StringBuffer fraction = StringBuffer();
    for (int digit = 0; remainder != BigInt.zero && digit < 18; digit++) {
      remainder *= BigInt.from(10);
      fraction.write(remainder ~/ denominator);
      remainder = remainder.remainder(denominator);
    }
    if (remainder != BigInt.zero) return null;
    final String value = fraction.isEmpty ? whole : '$whole.$fraction';
    return '1 ${from.symbol} = $value ${to.symbol}';
  }
}

/// A complete immutable catalogue whose strip counts share the table's rows.
class SwapListSnapshot {
  /// Freezes the entire proven public row set from one load.
  SwapListSnapshot(Iterable<SwapListRow> rows)
    : rows = List<SwapListRow>.unmodifiable(rows);

  /// Complete immutable rows, rather than an independently counted subset.
  final List<SwapListRow> rows;

  /// Count of recorded pending and active rows in this same snapshot.
  int get active => rows
      .where(
        (SwapListRow row) =>
            row.record.state == P2pSwapState.pending ||
            row.record.state == P2pSwapState.active,
      )
      .length;

  /// Count of recorded completed rows in this same snapshot.
  int get completed => rows
      .where((SwapListRow row) => row.record.state == P2pSwapState.completed)
      .length;

  /// Count of recorded reclaimable rows in this same snapshot.
  int get reclaimable => rows
      .where((SwapListRow row) => row.record.state == P2pSwapState.reclaimable)
      .length;
}

/// A single original-Box lane prevents overlapping history deletion admissions.
class _SwapListLane {
  bool admitting = false;
  SwapListOutcome? active;
  final List<SwapListOutcome> outcomes = <SwapListOutcome>[];
}

/// Read ownership is separate from delivery to a mounted widget.
class SwapListPresenter extends ChangeNotifier {
  /// Observes only the provided original binding; it never recaptures globals.
  SwapListPresenter(this.binding);

  /// Captured resources and exact read/deletion capabilities.
  final SwapListBinding binding;
  static final Expando<_SwapListLane> _lanes = Expando<_SwapListLane>();

  /// Retained actual read Futures, including optional unavailable facts.
  final List<SwapListOutcome> reads = <SwapListOutcome>[];

  /// Complete snapshot currently deliverable to a live view.
  SwapListSnapshot? snapshot;

  /// Last original complete result, retained independently of view disposal.
  SwapListSnapshot? originalResult;

  /// Original complete-load failure, retained outside interface text.
  Object? error;

  /// Original trace associated with [error].
  StackTrace? stackTrace;

  /// Whether the single admitted original load is still pending.
  bool loading = false;
  bool _disposed = false;
  Future<void>? _pending;

  /// Whether original resources and the entire catalogue still match capture.
  bool get isCurrent => binding.ownsResources() && binding.catalogueIsCurrent();
  _SwapListLane get _lane => _lanes[binding.identity] ??= _SwapListLane();

  /// Whether the shared original-Box lane owns a deletion admission or Future.
  bool get deleting => _lane.admitting || _lane.active != null;

  /// Every original deletion outcome retained on the shared original Box lane.
  List<SwapListOutcome> get writes =>
      List<SwapListOutcome>.unmodifiable(_lane.outcomes);

  /// Requires a live observer and exact original bytes for the rendered row.
  bool canOpen(SwapListRecord record) =>
      !_disposed && binding.ownsResources() && binding.rowIsCurrent(record);

  void _requireCurrent() {
    if (_disposed || !isCurrent) throw const SwapListRefused();
  }

  Future<T> _read<T>(Future<T> Function() call) async {
    _requireCurrent();
    final Future<T> operation;
    try {
      operation = call();
    } on Object catch (value, trace) {
      final SwapListOutcome failed = SwapListOutcome(
        Future<T>.error(value, trace),
      );
      reads.add(failed);
      return (await failed.settle()) as T;
    }
    final SwapListOutcome outcome = SwapListOutcome(operation);
    reads.add(outcome);
    final T result = (await outcome.settle()) as T;
    _requireCurrent();
    return result;
  }

  Future<T?> _optional<T>(Future<T?> Function() call) async {
    try {
      return await _read<T?>(call);
    } on SwapListRefused {
      rethrow;
    } on Object {
      // An unavailable deposit remains unknown; its original error is retained.
      _requireCurrent();
      return null;
    }
  }

  /// Shares one pending load, requiring complete pages before exposing counts.
  Future<void> load() =>
      _pending ??= _load().whenComplete(() => _pending = null);

  Future<void> _load() async {
    loading = true;
    error = null;
    _notify();
    try {
      const int pageSize = 32;
      const int maxRecords = 1000;
      int? total;
      final List<SwapListRecord> records = <SwapListRecord>[];
      final Set<String> identities = <String>{};
      for (int page = 0; page <= maxRecords ~/ pageSize; page++) {
        final SwapListPage value = await _read<SwapListPage>(
          () => binding.readPage(page, pageSize),
        );
        total ??= value.total;
        if (total < 0 ||
            total > maxRecords ||
            value.total != total ||
            value.records.length > pageSize ||
            records.length + value.records.length > total) {
          throw const SwapListRefused();
        }
        for (final SwapListRecord record in value.records) {
          if (!identities.add(record.id) ||
              record.chainId != binding.chainId ||
              !binding.members.contains(record.selfAddress) ||
              !binding.rowIsCurrent(record)) {
            throw const SwapListRefused();
          }
          records.add(record);
        }
        final bool expectedMore = records.length < total;
        if (value.more != expectedMore ||
            (expectedMore && value.records.length != pageSize)) {
          throw const SwapListRefused();
        }
        if (!expectedMore) break;
      }
      if (records.length != total) throw const SwapListRefused();
      final int chainTime = await _read<int>(binding.readChainTime);
      if (chainTime <= 0) throw const SwapListRefused();
      final List<SwapListRow> rows = <SwapListRow>[];
      for (final SwapListRecord record in records) {
        final String? ownId = record.ownDepositId;
        final String? receiveId = record.receiveDepositId;
        final SwapDepositProof? own = ownId == null
            ? null
            : await _optional<SwapDepositProof>(
                () => binding.readDeposit(ownId),
              );
        final SwapDepositProof? receive = receiveId == null
            ? null
            : await _optional<SwapDepositProof>(
                () => binding.readDeposit(receiveId),
              );
        final SwapDepositProof? sending =
            own != null &&
                own.belongsTo(record, sending: true) &&
                own.confirmedAt <= chainTime
            ? own
            : null;
        final SwapDepositProof? receiving =
            receive != null &&
                receive.belongsTo(record, sending: false) &&
                receive.confirmedAt <= chainTime
            ? receive
            : null;
        final SwapLiveDeposit? live = sending == null
            ? null
            : await _optional<SwapLiveDeposit>(
                () => binding.readLiveDeposit(sending.id),
              );
        rows.add(
          SwapListRow(
            record: record,
            sending: sending,
            receiving: receiving,
            chainTime: chainTime,
            currentExpiration: live != null && live.matches(sending!)
                ? live.expiration
                : null,
          ),
        );
      }
      rows.sort((SwapListRow a, SwapListRow b) {
        final int byTime = b.record.started.compareTo(a.record.started);
        return byTime != 0 ? byTime : a.record.id.compareTo(b.record.id);
      });
      originalResult = SwapListSnapshot(rows);
      _requireCurrent();
      if (!_disposed) snapshot = originalResult;
    } on Object catch (value, trace) {
      error = value;
      stackTrace = trace;
      if (!_disposed) snapshot = null;
    } finally {
      loading = false;
      _notify();
    }
  }

  /// Call after confirmation. The exact captured rows are checked at admission.
  Future<SwapListOutcome?> delete(List<SwapListRecord> records) async {
    if (_disposed ||
        deleting ||
        records.isEmpty ||
        !isCurrent ||
        records.any(
          (SwapListRecord record) =>
              !record.canDelete || !binding.rowIsCurrent(record),
        ) ||
        records.map((SwapListRecord row) => row.id).toSet().length !=
            records.length) {
      return null;
    }
    final List<String> ids = List<String>.unmodifiable(
      records.map((SwapListRecord row) => row.id),
    );
    _lane.admitting = true;
    late Future<dynamic> operation;
    try {
      operation = binding.deleteRecords(ids);
    } on Object catch (value, trace) {
      operation = Future<dynamic>.error(value, trace);
    }
    final SwapListOutcome outcome = SwapListOutcome(operation);
    _lane.active = outcome;
    _lane.admitting = false;
    _lane.outcomes.add(outcome);
    _notify();
    try {
      await outcome.settle();
    } on Object {
      // The original receipt is the only completion authority, even offscreen.
    } finally {
      if (identical(_lane.active, outcome)) _lane.active = null;
      _notify();
    }
    return outcome;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
