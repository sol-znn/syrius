import 'package:flutter/foundation.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/plasma_owner/plasma_session.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/send/send.dart';
import 'package:zenon_syrius_wallet_flutter/utils/plasma_purpose.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

/// Loading and failure remain distinct from a successful empty owner response.
enum PlasmaOwnerStatus {
  /// No owner read has started.
  initial,

  /// A fresh owner response is being read.
  loading,

  /// The current owner read completed successfully.
  success,

  /// The latest read failed and grants no cancellation authority.
  failure,
}

/// The complete SDK aggregate with the immutable pages actually loaded.
class PlasmaOwnerRead {
  /// Copies the loaded entries while preserving the SDK's complete aggregate.
  PlasmaOwnerRead({
    required this.ticket,
    required this.total,
    required this.count,
    required this.frontierHeight,
    required this.pages,
    required List<PlasmaFusion> entries,
  }) : entries = List<PlasmaFusion>.unmodifiable(entries);

  /// Identity shared only by pages belonging to this exact owner read.
  final Object ticket;

  /// The complete owned fusion amount from the SDK, in QSR smallest units.
  final BigInt total;

  /// The complete number of owned fusions reported by the SDK.
  final int count;

  /// The frontier read with these owner pages.
  final int frontierHeight;

  /// The number of owner pages already loaded.
  final int pages;

  /// Immutable original facts for the rows actually loaded.
  final List<PlasmaFusion> entries;

  /// Whether the SDK count establishes that another page remains.
  bool get hasMore => entries.length < count;
}

/// Exact entries, selection and authority captured before the user's question.
class PlasmaCancelIntent {
  PlasmaCancelIntent._({
    required this.session,
    required this.read,
    required this.selectionEpoch,
    required this.isCurrent,
    required List<PlasmaFusion> entries,
  }) : entries = List<PlasmaFusion>.unmodifiable(entries);

  /// The account and transport captured before the question opened.
  final PlasmaSession session;

  /// The exact owner read shown when the question opened.
  final PlasmaOwnerRead read;

  /// The original selection revision, preventing later selection substitution.
  final int selectionEpoch;

  /// Additional authority from the original page or question.
  final bool Function() isCurrent;

  /// Immutable original rows, including their complete cancellation hashes.
  final List<PlasmaFusion> entries;

  /// The exact smallest-unit amount selected by the original question.
  BigInt get total => entries.fold(
    BigInt.zero,
    (BigInt sum, PlasmaFusion entry) => sum + entry.amount,
  );
}

/// Submission is distinct from the contract removing an owned fusion.
enum PlasmaCancellationStatus {
  /// The original admitted request has not yet returned a result.
  publishing,

  /// An accepted original publication matched every expected field.
  submitted,

  /// An admitted request did not establish an exact accepted publication.
  unknown,

  /// The request was refused before admission and may be rearmed by a read.
  refused,
}

/// Retains the original request's response. Later reads never replace it.
class PlasmaCancellationOutcome {
  /// Captures the original row and its per-request outcome.
  const PlasmaCancellationOutcome({
    required this.entry,
    required this.status,
    this.requestId,
    this.result,
    this.publicationHash,
    this.error,
    this.readTicket,
  });

  /// The original immutable fusion facts, including the full hash.
  final PlasmaFusion entry;

  /// The original request's admission and publication status.
  final PlasmaCancellationStatus status;

  /// The identifier allocated for this original request, if one was prepared.
  final Object? requestId;

  /// The sender's original result, retained after page disposal.
  final SendRequestResult? result;

  /// The original returned hash, without an inference of confirmation.
  final String? publicationHash;

  /// The original preparation or publication error, if any.
  final Object? error;

  /// The read under which this request was attempted.
  final Object? readTicket;
}

/// A serial batch's original partial result, including the unstarted suffix.
class PlasmaCancellationBatch {
  /// Retains the original intent and every attempted per-hash outcome.
  PlasmaCancellationBatch({
    required this.intent,
    required List<PlasmaCancellationOutcome> outcomes,
  }) : outcomes = List<PlasmaCancellationOutcome>.unmodifiable(outcomes);

  /// The exact question and selection that authorized this serial batch.
  final PlasmaCancelIntent intent;

  /// Original outcomes in dispatch order, stopping at the first unresolved one.
  final List<PlasmaCancellationOutcome> outcomes;

  /// Number of exact accepted submissions, without a confirmation claim.
  int get submitted => outcomes
      .where(
        (PlasmaCancellationOutcome outcome) =>
            outcome.status == PlasmaCancellationStatus.submitted,
      )
      .length;
}

/// One owner list and cancellation journal retained by the existing sender.
/// Page disposal revokes future work without losing an admitted result.
class PlasmaOwnerController extends ChangeNotifier {
  /// Creates one owner list and journal using the shell's shared sender.
  PlasmaOwnerController({
    required this.sender,
    required this.address,
    required this.chainId,
    this.pageSize = 20,
  }) : assert(pageSize > 0, 'Owner page size must be positive');

  /// Reuses the original owner's journal across page disposal and navigation.
  factory PlasmaOwnerController.retained({
    required SendTransactionBloc sender,
    required String address,
    required int chainId,
  }) {
    final Map<(String, int), PlasmaOwnerController> owners = _owners[sender] ??=
        <(String, int), PlasmaOwnerController>{};
    return owners.putIfAbsent(
      (address, chainId),
      () => PlasmaOwnerController(
        sender: sender,
        address: address,
        chainId: chainId,
      ),
    );
  }

  static final Expando<Map<(String, int), PlasmaOwnerController>> _owners =
      Expando<Map<(String, int), PlasmaOwnerController>>();

  /// The shell's single sender for Fuse and cancellation admission.
  final SendTransactionBloc sender;

  /// The exact account owning these fusions.
  final String address;

  /// The signing chain paired with the owning account.
  final int chainId;

  /// Maximum number of original entries requested per owner page.
  final int pageSize;
  PlasmaOwnerStatus _status = PlasmaOwnerStatus.initial;
  PlasmaOwnerRead? _read;
  PlasmaSession? _session;
  int _epoch = 0;
  int _selectionEpoch = 0;
  bool _moreLoading = false;
  bool _busy = false;
  bool _disposed = false;
  PlasmaCancelIntent? _question;
  PlasmaCancellationBatch? _lastBatch;
  final List<PlasmaCancellationBatch> _batches = <PlasmaCancellationBatch>[];
  final Set<String> _selected = <String>{};
  final Map<String, PlasmaCancellationOutcome> _outcomes =
      <String, PlasmaCancellationOutcome>{};

  /// The latest read status, distinct from retained display rows.
  PlasmaOwnerStatus get status => _status;

  /// Whether an original serial cancellation batch is still settling.
  bool get busy => _busy;

  /// Whether one exact question already holds the selection.
  bool get questioning => _question != null;

  /// Whether the next owner page is already being fetched.
  bool get moreLoading => _moreLoading;

  /// The most recent original batch result, including a partial result.
  PlasmaCancellationBatch? get lastBatch => _lastBatch;

  /// Immutable history that preserves earlier known refusals after rearming.
  List<PlasmaCancellationBatch> get batches =>
      List<PlasmaCancellationBatch>.unmodifiable(_batches);

  /// Complete hashes selected in the current owner read.
  Set<String> get selected => Set<String>.unmodifiable(_selected);

  /// Original per-hash results, retained independently of page display.
  Map<String, PlasmaCancellationOutcome> get outcomes =>
      Map<String, PlasmaCancellationOutcome>.unmodifiable(_outcomes);

  /// A fresh explicit read may rearm a known refusal, keeping its history.
  PlasmaCancellationOutcome? displayOutcome(String hash) {
    final PlasmaCancellationOutcome? outcome = _outcomes[hash];
    return outcome?.status == PlasmaCancellationStatus.refused && !_held(hash)
        ? null
        : outcome;
  }

  /// A retained response loses authority as soon as its original session does.
  PlasmaOwnerRead? get read =>
      !_disposed &&
          _status == PlasmaOwnerStatus.success &&
          (_session?.isCurrent ?? false)
      ? _read
      : null;

  /// A failed follow-up does not erase rows whose contract removal is unknown.
  /// Retained rows are display only while [read] is unavailable.
  PlasmaOwnerRead? get displayRead =>
      !_disposed && (_session?.isCurrent ?? false) ? _read : null;

  bool _accepts(PlasmaSession session) =>
      !_disposed &&
      session.address == address &&
      session.chainId == chainId &&
      session.isCurrent;

  bool _owns(PlasmaSession session, int epoch) =>
      _accepts(session) && identical(_session, session) && epoch == _epoch;

  /// Supersedes older pages and clears their selection before starting RPCs.
  Future<void> load(PlasmaSession session) async {
    if (!_accepts(session)) return;
    final PlasmaOwnerRead? retained = displayRead;
    final int epoch = ++_epoch;
    _session = session;
    _read = retained;
    _status = PlasmaOwnerStatus.loading;
    _moreLoading = false;
    _selected.clear();
    _selectionEpoch++;
    _changed();
    try {
      final _PlasmaPage page = _PlasmaPage.copy(
        await session.readEntries(0, pageSize),
        pageSize,
      );
      if (!_owns(session, epoch)) return;
      final int frontier = await session.readFrontier();
      if (!_owns(session, epoch)) return;
      if (frontier < 0) throw const FormatException('Invalid frontier height');
      _read = PlasmaOwnerRead(
        ticket: Object(),
        total: page.total,
        count: page.count,
        frontierHeight: frontier,
        pages: 1,
        entries: page.entries,
      );
      _status = PlasmaOwnerStatus.success;
      _changed();
    } on Object {
      if (!_owns(session, epoch)) return;
      _status = PlasmaOwnerStatus.failure;
      _changed();
    }
  }

  /// Concurrent scroll callbacks share one next page and one exact read epoch.
  Future<void> loadMore() async {
    final PlasmaSession? session = _session;
    final PlasmaOwnerRead? before = read;
    if (_moreLoading || session == null || before == null || !before.hasMore) {
      return;
    }
    final int epoch = _epoch;
    _moreLoading = true;
    _changed();
    try {
      final _PlasmaPage page = _PlasmaPage.copy(
        await session.readEntries(before.pages, pageSize),
        pageSize,
      );
      if (!_owns(session, epoch) || !identical(_read, before)) return;
      if (page.total != before.total || page.count != before.count) {
        throw const FormatException('Owner aggregate changed between pages');
      }
      final Set<String> hashes = before.entries
          .map((PlasmaFusion entry) => entry.hash)
          .toSet();
      if (page.entries.any((PlasmaFusion entry) => !hashes.add(entry.hash))) {
        throw const FormatException('Overlapping owner pages');
      }
      final List<PlasmaFusion> entries = <PlasmaFusion>[
        ...before.entries,
        ...page.entries,
      ];
      if (entries.length > page.count || page.entries.isEmpty) {
        throw const FormatException('Incomplete owner page');
      }
      if (entries.length == page.count &&
          entries.fold<BigInt>(
                BigInt.zero,
                (BigInt total, PlasmaFusion entry) => total + entry.amount,
              ) !=
              page.total) {
        throw const FormatException('Incomplete owner aggregate');
      }
      final int frontier = await session.readFrontier();
      if (!_owns(session, epoch) || !identical(_read, before)) return;
      if (frontier < 0) throw const FormatException('Invalid frontier height');
      _read = PlasmaOwnerRead(
        // Pagination extends the same displayed read; an ordinary scroll
        // does not change what an already selected exact row identifies.
        ticket: before.ticket,
        total: page.total,
        count: page.count,
        frontierHeight: frontier,
        pages: before.pages + 1,
        entries: entries,
      );
    } on Object {
      if (_owns(session, epoch)) _status = PlasmaOwnerStatus.failure;
    } finally {
      if (_owns(session, epoch)) {
        _moreLoading = false;
        _changed();
      }
    }
  }

  /// Checks exact current ownership, strict expiry and original request holds.
  bool canSelect(PlasmaFusion entry) {
    final PlasmaOwnerRead? current = read;
    return !_busy &&
        !questioning &&
        !sender.busy.value &&
        current != null &&
        !_held(entry.hash) &&
        current.entries.any((PlasmaFusion item) => item.matches(entry)) &&
        entry.eligibleAt(current.frontierHeight);
  }

  bool _held(String hash) {
    final PlasmaCancellationOutcome? outcome = _outcomes[hash];
    if (outcome == null) return false;
    return outcome.status != PlasmaCancellationStatus.refused ||
        identical(outcome.readTicket, read?.ticket);
  }

  /// Changes selection only while this exact displayed row is eligible.
  void select(PlasmaFusion entry, {required bool selected}) {
    if (!canSelect(entry)) return;
    if (selected ? _selected.add(entry.hash) : _selected.remove(entry.hash)) {
      _selectionEpoch++;
      _changed();
    }
  }

  /// Freezes row facts and selection before the first confirmation is shown.
  PlasmaCancelIntent? beginCancellation({
    required PlasmaSession session,
    required bool Function() isCurrent,
    String? hash,
  }) {
    final PlasmaOwnerRead? current = read;
    if (!_accepts(session) || current == null || !isCurrent()) return null;
    final List<PlasmaFusion> entries = <PlasmaFusion>[
      for (final PlasmaFusion entry in current.entries)
        if (hash == null ? _selected.contains(entry.hash) : entry.hash == hash)
          entry,
    ];
    if (entries.isEmpty || entries.any((PlasmaFusion e) => !canSelect(e))) {
      return null;
    }
    final PlasmaCancelIntent intent = PlasmaCancelIntent._(
      session: session,
      read: current,
      selectionEpoch: _selectionEpoch,
      isCurrent: isCurrent,
      entries: entries,
    );
    _question = intent;
    _changed();
    return intent;
  }

  /// Releases only the original unsubmitted question's selection hold.
  void finishQuestion(PlasmaCancelIntent intent) {
    if (!identical(_question, intent) || _busy) return;
    _question = null;
    _changed();
  }

  bool _intentCurrent(PlasmaCancelIntent intent) =>
      _accepts(intent.session) &&
      identical(_question, intent) &&
      identical(read?.ticket, intent.read.ticket) &&
      _selectionEpoch == intent.selectionEpoch &&
      intent.isCurrent();

  /// Each next hash needs a fresh exact owner proof and strict frontier check.
  /// An admitted original handle always settles, even after this owner closes.
  Future<PlasmaCancellationBatch?> cancel(PlasmaCancelIntent intent) async {
    if (_busy || !_intentCurrent(intent)) return null;
    final Object owner = Object();
    if (!sender.tryReserve(owner)) return null;
    _busy = true;
    final List<PlasmaCancellationOutcome> outcomes =
        <PlasmaCancellationOutcome>[];
    _changed();
    try {
      for (final PlasmaFusion entry in intent.entries) {
        if (!_intentCurrent(intent) || _held(entry.hash)) break;
        Object? requestId;
        bool admitted = false;
        try {
          final bool proven = await _proveEntry(intent, entry);
          if (!_intentCurrent(intent) || !proven) {
            throw StateError('Fusion ownership or expiration changed');
          }
          final AccountBlockTemplate block = AccountBlockTemplate.fromJson(
            intent.session.cancelBlock(entry.hash).toJson(),
          );
          final AccountBlockTemplate expected = AccountBlockTemplate.fromJson(
            block.toJson(),
          );
          if (!_intentCurrent(intent)) break;
          requestId = Object();
          final SendRequestHandle? handle = sender.trySubmitOwned(
            owner: owner,
            requestId: requestId,
            block: block,
            fromAddress: address,
            reasonForGeneratingPlasma: PlasmaPurpose.cancelPlasma.message,
            origin: SendTransactionOrigin.contract,
            canStart: () => _intentCurrent(intent),
            canPublish: () => _intentCurrent(intent),
          );
          if (handle == null) throw StateError('Sender refused cancellation');
          admitted = true;
          _outcomes[entry.hash] = PlasmaCancellationOutcome(
            entry: entry,
            requestId: requestId,
            status: PlasmaCancellationStatus.publishing,
            readTicket: intent.read.ticket,
          );
          _changed();
          final SendRequestResult result = await handle.result;
          final AccountBlockTemplate? accepted = result.block;
          final String? hash = accepted?.hash.toString();
          final bool exact =
              result.accepted &&
              accepted != null &&
              accepted.address.toString() == address &&
              accepted.chainIdentifier == chainId &&
              accepted.blockType == expected.blockType &&
              accepted.toAddress == expected.toAddress &&
              accepted.tokenStandard == expected.tokenStandard &&
              accepted.amount == expected.amount &&
              listEquals(accepted.data, expected.data) &&
              hash != null &&
              hash != emptyHash.toString();
          final PlasmaCancellationOutcome outcome = PlasmaCancellationOutcome(
            entry: entry,
            requestId: requestId,
            result: result,
            publicationHash: hash,
            status: exact
                ? PlasmaCancellationStatus.submitted
                : PlasmaCancellationStatus.unknown,
            error: result.error,
            readTicket: intent.read.ticket,
          );
          _outcomes[entry.hash] = outcome;
          outcomes.add(outcome);
          _selected.remove(entry.hash);
          _changed();
          if (!exact) break;
        } on Object catch (error) {
          final PlasmaCancellationOutcome outcome = PlasmaCancellationOutcome(
            entry: entry,
            requestId: requestId,
            status: admitted
                ? PlasmaCancellationStatus.unknown
                : PlasmaCancellationStatus.refused,
            error: error,
            readTicket: intent.read.ticket,
          );
          _outcomes[entry.hash] = outcome;
          outcomes.add(outcome);
          _selected.remove(entry.hash);
          break;
        }
      }
      final PlasmaCancellationBatch batch = PlasmaCancellationBatch(
        intent: intent,
        outcomes: outcomes,
      );
      _lastBatch = batch;
      _batches.add(batch);
      return batch;
    } finally {
      _busy = false;
      _question = null;
      sender.releaseReservation(owner);
      _changed();
    }
  }

  Future<bool> _proveEntry(
    PlasmaCancelIntent intent,
    PlasmaFusion entry,
  ) async {
    final Set<String> seen = <String>{};
    BigInt? total;
    int? count;
    for (int pageIndex = 0; ; pageIndex++) {
      if (!_intentCurrent(intent)) return false;
      final _PlasmaPage page = _PlasmaPage.copy(
        await intent.session.readEntries(pageIndex, pageSize),
        pageSize,
      );
      if (!_intentCurrent(intent)) return false;
      total ??= page.total;
      count ??= page.count;
      if (total != page.total || count != page.count) return false;
      PlasmaFusion? found;
      for (final PlasmaFusion candidate in page.entries) {
        if (!seen.add(candidate.hash)) return false;
        if (candidate.hash == entry.hash) found = candidate;
      }
      if (found != null) {
        final int frontier = await intent.session.readFrontier();
        return _intentCurrent(intent) &&
            entry.matches(found) &&
            entry.eligibleAt(frontier);
      }
      if (seen.length >= page.count || page.entries.length < pageSize) {
        return false;
      }
    }
  }

  void _changed() {
    if (_disposed) return;
    try {
      notifyListeners();
    } on Object {
      // A display observer cannot replace an original result or strand a hold.
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _epoch++;
    super.dispose();
  }
}

class _PlasmaPage {
  _PlasmaPage(this.total, this.count, this.entries);

  factory _PlasmaPage.copy(FusionEntryList response, int pageSize) {
    final BigInt total = response.qsrAmount;
    final int count = response.count;
    final List<PlasmaFusion> entries = response.list
        .map(PlasmaFusion.copy)
        .toList(growable: false);
    final Set<String> hashes = <String>{};
    final BigInt loaded = entries.fold<BigInt>(
      BigInt.zero,
      (BigInt sum, PlasmaFusion entry) => sum + entry.amount,
    );
    if (total < BigInt.zero ||
        count < entries.length ||
        entries.length > pageSize ||
        loaded > total ||
        (entries.length == count && loaded != total) ||
        entries.any(
          (PlasmaFusion entry) =>
              entry.hash == emptyHash.toString() ||
              entry.amount <= BigInt.zero ||
              entry.expirationHeight < 0 ||
              !hashes.add(entry.hash),
        ) ||
        (count == 0 && total != BigInt.zero) ||
        (count > 0 && (total == BigInt.zero || entries.isEmpty))) {
      throw const FormatException('Invalid owner fusion response');
    }
    return _PlasmaPage(total, count, entries);
  }

  final BigInt total;
  final int count;
  final List<PlasmaFusion> entries;
}
