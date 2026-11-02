import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:zenon_syrius_wallet_flutter/services/contacts_store.dart';
import 'package:zenon_syrius_wallet_flutter/utils/address_utils.dart';
import 'package:zenon_syrius_wallet_flutter/utils/constants.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

/// Validated smallest-unit balances and a complete account height.
class AddressesAccount {
  /// Preserves exact smallest-unit balances without normalization or rounding.
  const AddressesAccount({
    required this.address,
    required this.height,
    required this.znn,
    required this.qsr,
  });

  /// The canonical account named by the response.
  final String address;

  /// The node's complete account-block count.
  final int height;

  /// ZNN in smallest units.
  final BigInt znn;

  /// QSR in smallest units.
  final BigInt qsr;
}

/// The fields needed to establish one complete captured account chain.
class AddressesChainBlock {
  /// Captures only the public provenance fields needed by this reader.
  const AddressesChainBlock({
    required this.address,
    required this.chain,
    required this.height,
    required this.hash,
    required this.previousHash,
    required this.type,
  });

  /// The canonical owner.
  final String address;

  /// The source chain identifier.
  final int chain;

  /// The exact account height.
  final int height;

  /// The original public account-block hash.
  final String hash;

  /// The account predecessor, including the empty genesis predecessor.
  final String previousHash;

  /// The SDK block type.
  final int type;
}

/// A closed count becomes detailed statistics only after every page matches.
class AddressesChainSnapshot {
  /// Freezes complete counts only after every captured page agrees.
  AddressesChainSnapshot({required this.height, required Map<int, int> counts})
    : counts = Map<int, int>.unmodifiable(counts);

  /// The verified complete account height.
  final int height;

  /// Counts indexed by the SDK block type.
  final Map<int, int> counts;
}

/// A typed refusal; raw backend text never becomes interface text.
class AddressesSettingsRefused implements Exception {
  /// A refusal carries no wallet or transport detail.
  const AddressesSettingsRefused();
}

/// Validation failures remain distinct from persistence failures.
enum AddressesLabelError {
  /// A label must contain a visible name.
  empty,

  /// The existing wallet label length is exceeded.
  tooLong,

  /// Another member already uses this exact label.
  taken,
}

/// A validation refusal which presentation maps to a localized field error.
class AddressesLabelException implements Exception {
  /// Retains the validation reason without retaining the entered text.
  const AddressesLabelException(this.error);

  /// The field error.
  final AddressesLabelError error;
}

/// The original write, including a successful commit with suppressed effects.
class AddressesWriteOutcome {
  /// Retains original operation identity independently of transient paint.
  const AddressesWriteOutcome({
    required this.key,
    required this.committed,
    this.write,
    this.result,
    this.error,
    this.stackTrace,
  });

  /// The original serial lane key.
  final String key;

  /// Positive persistence is independent of later application or display.
  final bool committed;

  /// The identical original operation Future.
  final Future<dynamic>? write;

  /// The original returned value, including a derivation's detailed receipt.
  final Object? result;

  /// The unchanged original error.
  final Object? error;

  /// The original failure trace.
  final StackTrace? stackTrace;
}

class _AddressesJournal extends ChangeNotifier {
  final Map<String, String> labels = <String, String>{};
  final Map<String, Object> labelOwners = <String, Object>{};
  final Map<String, Future<AddressesWriteOutcome>> pending =
      <String, Future<AddressesWriteOutcome>>{};
  final List<AddressesWriteOutcome> outcomes = <AddressesWriteOutcome>[];
  Future<void> tail = Future<void>.value();

  void changed() {
    try {
      notifyListeners();
    } on Object {
      /* Storage results stay original. */
    }
  }
}

/// All production resources are captured before any read or edit starts.
/// The injected constructor has no globals, files, plugins or network calls.
class AddressesSettingsBinding {
  /// Injects all resources; construction never discovers a replacement backend.
  AddressesSettingsBinding({
    required Object identity,
    required Iterable<String> members,
    required this.selected,
    required this.chainId,
    required this.contacts,
    required Map<String, String> Function() labels,
    required this._ownsResources,
    required this._readAccount,
    required this._readFrontier,
    required this._readBlocks,
    required this._writeLabel,
    required this._publishLabel,
    required this._writeSelection,
    required this._applySelection,
    required this._generation,
    this.requiresPersistentContacts = false,
    this._canSend,
  }) : members = List<String>.unmodifiable(members),
       _journal = _journals[identity] ??= _AddressesJournal() {
    final Map<String, String> initial = labels();
    for (final String member in this.members) {
      final String? label = initial[member];
      if (label != null) {
        _journal.labels.putIfAbsent(member, () => label);
        _journal.labelOwners.putIfAbsent(member, Object.new);
      }
    }
  }

  static final Expando<_AddressesJournal> _journals =
      Expando<_AddressesJournal>();

  /// The original immutable wallet membership.
  final List<String> members;

  /// The account selected when the source was captured.
  final String selected;

  /// The source chain shared by the original node and wallet.
  final int chainId;

  /// The original globally shared address book.
  final ContactsStore contacts;

  /// Production edits require an already-open persistent address book.
  final bool requiresPersistentContacts;
  final bool Function() _ownsResources;
  final bool Function()? _canSend;
  final Future<AddressesAccount> Function(String) _readAccount;
  final Future<AddressesChainBlock?> Function(String) _readFrontier;
  final Future<List<AddressesChainBlock>?> Function(String, int, int)
  _readBlocks;
  final Future<void> Function(String, String) _writeLabel;
  final void Function(String, String) _publishLabel;
  final Future<void> Function(String) _writeSelection;
  final void Function(String, bool Function()) _applySelection;
  final AddressGenerationBinding? Function(bool Function()) _generation;
  final _AddressesJournal _journal;
  bool _revoked = false;

  /// Returning to old scalar values cannot revive a revoked binding.
  bool get ownsResources {
    if (_revoked) return false;
    try {
      final bool lost = !_ownsResources();
      _revoked = _revoked || lost;
      return !_revoked;
    } on Object {
      _revoked = true;
      return false;
    }
  }

  /// Only positively committed labels are exposed, including after remounts.
  Map<String, String> get labels =>
      Map<String, String>.unmodifiable(_journal.labels);

  /// An opaque label generation prevents string-value ABA in an old editor.
  Object? labelOwner(String address) => _journal.labelOwners[address];

  /// Retained original writes and failures from this exact backend.
  List<AddressesWriteOutcome> get outcomes =>
      List<AddressesWriteOutcome>.unmodifiable(_journal.outcomes);

  /// A replacement view observes the same original pending operations.
  bool get busy => _journal.pending.isNotEmpty || contacts.hasPendingWrite;

  /// Malformed or unopened saved books cannot be described as empty.
  bool get contactsAvailable =>
      !contacts.readFailed &&
      contacts.contactsReadComplete &&
      (!requiresPersistentContacts || contacts.isPersistent);

  /// Recipient handoff needs the exact original sender attachment as well.
  bool get canSend => ownsResources && (_canSend?.call() ?? true);

  void _require() {
    if (!ownsResources) throw const AddressesSettingsRefused();
  }

  /// Every member must return an exact valid account before showing a total.
  Future<Map<String, AddressesAccount>> readBalances() async {
    _require();
    if (members.isEmpty ||
        members.toSet().length != members.length ||
        !members.contains(selected) ||
        chainId <= 0) {
      throw const FormatException('Invalid captured member set');
    }
    final Map<String, AddressesAccount> result = <String, AddressesAccount>{};
    for (final String member in members) {
      _require();
      final AddressesAccount account = await _readAccount(member);
      _require();
      if (account.address != member ||
          account.height < 0 ||
          account.znn < BigInt.zero ||
          account.qsr < BigInt.zero) {
        throw const FormatException(
          'Account does not match its captured member',
        );
      }
      result[member] = account;
    }
    return Map<String, AddressesAccount>.unmodifiable(result);
  }

  /// No truncated page, duplicate height or moving frontier becomes statistics.
  Future<AddressesChainSnapshot> readChain() async {
    _require();
    final AddressesAccount account = await _readAccount(selected);
    _require();
    final AddressesChainBlock? frontier = await _readFrontier(selected);
    _require();
    final int count = account.height;
    if (account.address != selected ||
        count < 0 ||
        count > 1000000 ||
        (count == 0 ? frontier != null : frontier == null) ||
        (frontier != null && !_blockMatches(frontier, count))) {
      throw const FormatException('Account frontier does not match its height');
    }
    final Map<int, int> counts = <int, int>{};
    String previous = '0' * 64;
    final Set<String> hashes = <String>{};
    for (int start = 1; start <= count;) {
      _require();
      final int remaining = count - start + 1;
      final int size = remaining > 100 ? 100 : remaining;
      final List<AddressesChainBlock>? page = await _readBlocks(
        selected,
        start,
        size,
      );
      _require();
      if (page == null || page.length != size) {
        throw const FormatException('Account-chain page is incomplete');
      }
      for (int index = 0; index < page.length; index++) {
        final AddressesChainBlock block = page[index];
        if (!_blockMatches(block, start + index) ||
            block.previousHash != previous ||
            !hashes.add(block.hash)) {
          throw const FormatException('Account-chain page does not match');
        }
        counts.update(block.type, (int value) => value + 1, ifAbsent: () => 1);
        previous = block.hash;
      }
      start += size;
    }
    if (count > 0 && previous != frontier!.hash) {
      throw const FormatException('Account chain does not reach its frontier');
    }
    final AddressesChainBlock? after = await _readFrontier(selected);
    _require();
    final AddressesAccount afterAccount = await _readAccount(selected);
    _require();
    if (afterAccount.address != selected ||
        afterAccount.height != count ||
        (count == 0 ? after != null : after == null) ||
        (after != null &&
            (!_blockMatches(after, count) || after.hash != frontier?.hash))) {
      throw const FormatException('Account chain changed during the read');
    }
    return AddressesChainSnapshot(height: count, counts: counts);
  }

  bool _blockMatches(AddressesChainBlock block, int height) =>
      block.address == selected &&
      block.chain == chainId &&
      block.height == height &&
      block.type > 0 &&
      block.type < BlockTypeEnum.values.length &&
      RegExp(r'^[0-9a-f]{64}$').hasMatch(block.hash) &&
      block.hash != '0' * 64 &&
      RegExp(r'^[0-9a-f]{64}$').hasMatch(block.previousHash);

  /// Captures an exact label value and commits to the original Box serial lane.
  Future<AddressesWriteOutcome> rename(
    String address,
    String label, {
    required bool Function() isCurrent,
    Object? expectedOwner,
  }) {
    final String? expected = labels[address];
    final Object? owner = expectedOwner ?? labelOwner(address);
    return _edit(
      'label:$address',
      isCurrent,
      () {
        final String trimmed = label.trim();
        if (!members.contains(address) ||
            labels[address] != expected ||
            !identical(labelOwner(address), owner)) {
          throw const AddressesSettingsRefused();
        }
        if (trimmed.isEmpty) {
          throw const AddressesLabelException(AddressesLabelError.empty);
        }
        if (trimmed.length > kAddressLabelMaxLength) {
          throw const AddressesLabelException(AddressesLabelError.tooLong);
        }
        if (labels.entries.any(
          (MapEntry<String, String> entry) =>
              entry.key != address && entry.value == trimmed,
        )) {
          throw const AddressesLabelException(AddressesLabelError.taken);
        }
        return _writeLabel(address, trimmed);
      },
      (Object? _) {
        _journal.labels[address] = label.trim();
        _journal.labelOwners[address] = Object();
        if (ownsResources) _publishLabel(address, label.trim());
      },
    );
  }

  /// Saves the selected member before invoking original provider effects.
  Future<AddressesWriteOutcome> select(
    String address, {
    required bool Function() isCurrent,
  }) => _edit(
    'selection',
    isCurrent,
    () {
      if (!members.contains(address)) throw const AddressesSettingsRefused();
      return _writeSelection(address);
    },
    (Object? _) {
      if (isCurrent() && ownsResources) _applySelection(address, isCurrent);
    },
  );

  /// Adds or renames one exact committed contact through the existing store.
  Future<AddressesWriteOutcome> saveContact({
    required String name,
    required String address,
    required bool Function() isCurrent,
    Contact? expected,
  }) => _edit('contacts', isCurrent, () {
    bool original() => isCurrent() && ownsResources && contactsAvailable;
    if (!original()) throw const AddressesSettingsRefused();
    if (expected != null) {
      return contacts.rename(
        expected.address,
        name,
        expected: expected,
        isCurrent: original,
      );
    }
    return contacts.add(name: name, address: address, isCurrent: original);
  }, (Object? _) {});

  /// A captured derivation owns its allowed committed membership extension.
  Future<AddressesWriteOutcome> generate({required bool Function() isCurrent}) {
    AddressGenerationBinding? original;
    return _edit(
      'generation',
      isCurrent,
      () {
        final AddressGenerationBinding? source = original;
        if (source == null) throw const AddressesSettingsRefused();
        return source.generate();
      },
      (Object? result) {
        if (result is AddressGenerationOutcome && result.error != null) {
          Error.throwWithStackTrace(
            result.error!,
            result.stackTrace ?? StackTrace.empty,
          );
        }
      },
      capture: () {
        if (isCurrent() && ownsResources) original = _generation(isCurrent);
      },
    );
  }

  Future<AddressesWriteOutcome> _edit(
    String key,
    bool Function() source,
    Future<dynamic> Function() start,
    void Function(Object?) apply, {
    void Function()? capture,
  }) {
    final Future<AddressesWriteOutcome>? pending = _journal.pending[key];
    if (pending != null) return pending;
    final Completer<AddressesWriteOutcome> completion =
        Completer<AddressesWriteOutcome>();
    final Future<void> previous = _journal.tail;
    final Completer<void> finished = Completer<void>();
    _journal.tail = finished.future;
    _journal.pending[key] = completion.future;
    bool revoked = false;
    bool current() => !revoked && !(revoked = !source());
    Object? captureError;
    StackTrace? captureTrace;
    try {
      // A queued derivation must retain its original file and services before
      // waiting behind another edit or notifying a reentrant observer.
      capture?.call();
    } on Object catch (error, trace) {
      captureError = error;
      captureTrace = trace;
    }
    _journal.changed();
    unawaited(() async {
      Future<dynamic>? write;
      Object? result;
      Object? error;
      StackTrace? trace;
      bool committed = false;
      try {
        await previous;
        if (captureError != null) {
          Error.throwWithStackTrace(captureError, captureTrace!);
        }
        if (!current() || !ownsResources) {
          throw const AddressesSettingsRefused();
        }
        write = start();
        result = await write;
        if (result is AddressGenerationOutcome) {
          committed = result.committed;
          if (result.error != null) {
            Error.throwWithStackTrace(
              result.error!,
              result.stackTrace ?? StackTrace.empty,
            );
          }
          if (result.releaseError != null) {
            Error.throwWithStackTrace(result.releaseError!, StackTrace.current);
          }
        } else {
          committed = true;
        }
        apply(result);
      } on Object catch (failure, stack) {
        error = failure;
        trace = stack;
      }
      final AddressesWriteOutcome outcome = AddressesWriteOutcome(
        key: key,
        committed: committed,
        write: write,
        result: result,
        error: error,
        stackTrace: trace,
      );
      _journal.outcomes.add(outcome);
      unawaited(_journal.pending.remove(key));
      completion.complete(outcome);
      finished.complete();
      _journal.changed();
    }());
    return completion.future;
  }
}

/// Paint from complete current reads; absence of facts never supplies a zero.
class AddressesSettingsState {
  /// Freezes the current read results and explicit loading/failure stages.
  AddressesSettingsState({
    this.available = false,
    this.loading = false,
    this.balancesFailed = false,
    this.chainLoading = false,
    this.chainFailed = false,
    Map<String, AddressesAccount> balances = const <String, AddressesAccount>{},
    this.chain,
  }) : balances = Map<String, AddressesAccount>.unmodifiable(balances);

  /// Original resources still belong to this source.
  final bool available;

  /// A complete member balance read is pending.
  final bool loading;

  /// The current balance read failed or was incomplete.
  final bool balancesFailed;

  /// All account-chain pages are being read.
  final bool chainLoading;

  /// The chain was incomplete, changed or failed to read.
  final bool chainFailed;

  /// A complete matching member map, or no displayed balances.
  final Map<String, AddressesAccount> balances;

  /// Full linked-chain statistics, never a partial page sum.
  final AddressesChainSnapshot? chain;
}

/// A disposable adapter; asynchronous edits remain owned by their journals.
class AddressesSettingsPresenter extends Cubit<AddressesSettingsState> {
  /// Observes one captured source without creating application resources.
  AddressesSettingsPresenter({required this.binding})
    : super(
        AddressesSettingsState(available: binding?.ownsResources ?? false),
      ) {
    binding?._journal.addListener(_changed);
    binding?.contacts.addListener(_changed);
  }

  /// Null means no qualified original source was available.
  final AddressesSettingsBinding? binding;
  Object? _read;
  Object? _chainRead;
  bool _visible = true;

  /// Outgoing or covered views discard paint authority; writes stay owned.
  void setVisible({required bool visible}) {
    if (isClosed || _visible == visible) return;
    _visible = visible;
    if (!visible) {
      _read = null;
      _chainRead = null;
      emit(AddressesSettingsState(available: binding?.ownsResources ?? false));
    }
  }

  void _changed() {
    if (!isClosed && _visible) {
      emit(
        AddressesSettingsState(
          available: binding?.ownsResources ?? false,
          loading: state.loading,
          balancesFailed: state.balancesFailed,
          balances: state.balances,
          chain: state.chain,
          chainLoading: state.chainLoading,
          chainFailed: state.chainFailed,
        ),
      );
    }
  }

  /// New admission revokes every older successful or failed balance reply.
  Future<void> refresh() async {
    final AddressesSettingsBinding? owner = binding;
    if (isClosed || !_visible || owner == null || !owner.ownsResources) return;
    final Object read = Object();
    _read = read;
    _chainRead = null;
    emit(AddressesSettingsState(available: true, loading: true));
    try {
      final Map<String, AddressesAccount> balances = await owner.readBalances();
      if (!isClosed && identical(_read, read) && owner.ownsResources) {
        emit(AddressesSettingsState(available: true, balances: balances));
      }
    } on Object {
      if (!isClosed && identical(_read, read) && owner.ownsResources) {
        emit(AddressesSettingsState(available: true, balancesFailed: true));
      }
    }
  }

  /// Reads complete chain details only when the original disclosure opens.
  Future<void> loadChain() async {
    final AddressesSettingsBinding? owner = binding;
    if (isClosed ||
        !_visible ||
        owner == null ||
        !owner.ownsResources ||
        state.chainLoading) {
      return;
    }
    final Object read = Object();
    _chainRead = read;
    emit(
      AddressesSettingsState(
        available: true,
        balances: state.balances,
        balancesFailed: state.balancesFailed,
        chainLoading: true,
      ),
    );
    try {
      final AddressesChainSnapshot chain = await owner.readChain();
      if (!isClosed && identical(_chainRead, read) && owner.ownsResources) {
        emit(
          AddressesSettingsState(
            available: true,
            balances: state.balances,
            balancesFailed: state.balancesFailed,
            chain: chain,
          ),
        );
      }
    } on Object {
      if (!isClosed && identical(_chainRead, read) && owner.ownsResources) {
        emit(
          AddressesSettingsState(
            available: true,
            balances: state.balances,
            balancesFailed: state.balancesFailed,
            chainFailed: true,
          ),
        );
      }
    }
  }

  @override
  Future<void> close() {
    _read = null;
    _chainRead = null;
    binding?._journal.removeListener(_changed);
    binding?.contacts.removeListener(_changed);
    return super.close();
  }
}
