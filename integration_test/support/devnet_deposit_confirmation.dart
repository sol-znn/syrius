import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zenon_syrius_wallet_flutter/main.dart' as app;
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/registration_success/registration_publisher.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/send/bloc/send_transaction/send_transaction_bloc.dart';
import 'package:zenon_syrius_wallet_flutter/utils/global.dart';
import 'package:zenon_syrius_wallet_flutter/utils/wallet_action_context.dart';
import 'package:zenon_syrius_wallet_flutter/utils/wallet_flight_registry.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/shell/strip/flight.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

import 'devnet_test_context.dart';

/// Fixed diagnostics never render the original SDK error or wallet state.
enum DevnetDepositFailureCode {
  /// The original test wallet or sender was unavailable before the tap.
  sourceUnavailable,

  /// An original wallet, chain or node observation left its captured identity.
  contextChanged,

  /// No original accepted publication was retained.
  originalMissing,

  /// More than one request or a foreign result entered the observation.
  originalAmbiguous,

  /// A returned block differs from the original deposit or its exact hash.
  originalMismatch,

  /// The existing deposit operation failed.
  depositFailed,

  /// The existing registration operation failed.
  registrationFailed,

  /// An original read failed without positive confirmation evidence.
  readFailed,

  /// A finite observation or original-read deadline expired.
  deadline,

  /// The original sender or its single observation attempt has closed.
  closed,
}

/// Keeps an original failure in memory without exposing it through diagnostics.
class DevnetDepositFailure implements Exception {
  /// Retains only a fixed reason in the rendered diagnostic.
  const DevnetDepositFailure(this.code, {this.originalError});

  /// The fixed public reason.
  final DevnetDepositFailureCode code;

  /// The original in-memory failure, never included in the rendered message.
  final Object? originalError;

  @override
  String toString() => 'Devnet deposit confirmation refused: ${code.name}';
}

/// Retains the two original Sentinel pre-deposit reads and their authority.
class DevnetSentinelPreflight {
  /// Captures the genuine selected wallet and node before mounting the host.
  DevnetSentinelPreflight.capture(String owner)
    : _authority = _DepositAuthority.capture(owner, sentinelAddress) {
    if (_authority.sentinel == null) {
      throw const DevnetDepositFailure(
        DevnetDepositFailureCode.sourceUnavailable,
      );
    }
  }

  final _DepositAuthority _authority;
  final List<_PrivateRead> _originalReads = <_PrivateRead>[];
  DevnetDepositFailure? _failure;
  bool _accountAttempted = false;
  bool _accountReady = false;
  bool _depositAttempted = false;
  bool _depositReady = false;

  DevnetDepositFailure _remember(DevnetDepositFailure original) =>
      _failure ??= original;

  /// Refuses permanently if the captured wallet or transport has changed.
  void requireCurrent() {
    final DevnetDepositFailure? failure = _failure;
    if (failure != null) throw failure;
    try {
      _authority.requireCurrent();
    } on DevnetDepositFailure catch (error) {
      throw _remember(error);
    }
  }

  /// Both original reads must finish before deposit, Next or Register.
  void requireReady() {
    requireCurrent();
    if (!_accountReady || !_depositReady) {
      throw _remember(
        const DevnetDepositFailure(DevnetDepositFailureCode.originalMissing),
      );
    }
  }

  /// Reads the captured owner's account once, without acquiring a signer.
  Future<AccountInfo> readAccountInfo(
    WidgetTester tester, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    requireCurrent();
    if (_accountAttempted) {
      throw _remember(
        const DevnetDepositFailure(DevnetDepositFailureCode.closed),
      );
    }
    _accountAttempted = true;
    final AccountInfo result = await _read(
      tester,
      () => _authority.ledger.getAccountInfoByAddress(
        Address.parse(_authority.owner),
      ),
      timeout,
    );
    requireCurrent();
    _accountReady = true;
    return result;
  }

  /// Reads the captured Sentinel deposit once after the account read.
  Future<BigInt> readDepositedQsr(
    WidgetTester tester, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    requireCurrent();
    if (!_accountReady || _depositAttempted) {
      throw _remember(
        DevnetDepositFailure(
          _depositAttempted
              ? DevnetDepositFailureCode.closed
              : DevnetDepositFailureCode.originalMissing,
        ),
      );
    }
    _depositAttempted = true;
    final BigInt result = await _read(
      tester,
      () => _authority.sentinel!.getDepositedQsr(
        Address.parse(_authority.owner),
      ),
      timeout,
    );
    requireCurrent();
    _depositReady = true;
    return result;
  }

  Future<T> _read<T>(
    WidgetTester tester,
    Future<T> Function() read,
    Duration timeout,
  ) async {
    try {
      requireCurrent();
      if (timeout <= Duration.zero || timeout > const Duration(seconds: 5)) {
        throw const DevnetDepositFailure(DevnetDepositFailureCode.deadline);
      }
      final _DepositBudget budget = _DepositBudget(tester, timeout);
      final Future<T> original = read();
      _originalReads.add(_PrivateReadOf<T>(original));
      return await _pumpOriginal(
        tester,
        () => original,
        budget,
        timeout,
        requireCurrent,
      );
    } on Object catch (error) {
      if (error is DevnetDepositFailure) throw _remember(error);
      throw _remember(
        DevnetDepositFailure(
          DevnetDepositFailureCode.readFailed,
          originalError: error,
        ),
      );
    }
  }
}

/// Observes one real host-sender request; it cannot submit or retry a request.
class DevnetDepositConfirmation {
  /// Captures source authority and attaches before the single deposit tap.
  DevnetDepositConfirmation.capture({
    required SendTransactionBloc sender,
    required String ownerAddress,
    required AccountBlockTemplate expectedDeposit,
    WalletFlightRegistry? registry,
  }) : _sender = sender,
       _authority = _DepositAuthority.capture(
         ownerAddress,
         expectedDeposit.toAddress,
       ),
       _expected = AccountBlockTemplate.fromJson(expectedDeposit.toJson()),
       _registry = registry ?? WalletFlightRegistry.instance,
       _before = RegistrationPublisher.originalResultsFor(sender) {
    if (sender.isClosed ||
        sender.busy.value ||
        _expected.chainIdentifier != DevnetTestContext.chainId ||
        _expected.blockType != BlockTypeEnum.userSend.index ||
        _expected.tokenStandard != qsrZts ||
        _expected.amount <= BigInt.zero ||
        !(_expected.toAddress == pillarAddress ||
            _expected.toAddress == sentinelAddress) ||
        !listEquals(
          _expected.data,
          (_expected.toAddress == pillarAddress
                  ? PillarApi().depositQsr(_expected.amount)
                  : SentinelApi().depositQsr(_expected.amount))
              .data,
        )) {
      throw const DevnetDepositFailure(
        DevnetDepositFailureCode.sourceUnavailable,
      );
    }
    // Attach an error observer before the tap can finish or fail.
    unawaited(
      _accepted.future.then<void>(
        (AccountBlockTemplate _) {},
        onError: (Object _, StackTrace _) {},
      ),
    );
    _subscription = sender.stream.listen(
      _observe,
      onError: (Object error, StackTrace _) {
        _reject(DevnetDepositFailureCode.depositFailed, error);
      },
      onDone: () {
        if (!_closed && _sender.isClosed) {
          _reject(DevnetDepositFailureCode.closed);
        }
      },
    );
  }

  final SendTransactionBloc _sender;
  final _DepositAuthority _authority;
  final AccountBlockTemplate _expected;
  final WalletFlightRegistry _registry;
  final List<SendRequestResult> _before;
  final List<_PrivateRead> _originalReads = <_PrivateRead>[];
  final Completer<AccountBlockTemplate> _accepted =
      Completer<AccountBlockTemplate>();
  late final StreamSubscription<SendTransactionState> _subscription;
  Object? _requestId;
  AccountBlockTemplate? _original;
  AccountBlockTemplate? _snapshot;
  DevnetDepositFailure? _failure;
  Future<void>? _cancellation;
  bool _attempted = false;
  bool _confirmed = false;
  bool _effectAttempted = false;
  bool _closed = false;

  DevnetDepositFailure _reject(
    DevnetDepositFailureCode code, [
    Object? originalError,
  ]) {
    return _remember(
      DevnetDepositFailure(
        code,
        originalError: originalError,
      ),
    );
  }

  DevnetDepositFailure _remember(DevnetDepositFailure original) {
    final DevnetDepositFailure failure = _failure ??= original;
    if (!_accepted.isCompleted) _accepted.completeError(failure);
    return failure;
  }

  Future<T> _retainRead<T>(Future<T> Function() read) {
    final Future<T> original = read();
    _originalReads.add(_PrivateReadOf<T>(original));
    return original;
  }

  void _observe(SendTransactionState state) {
    if (_closed || _failure != null) return;
    try {
      _authority.requireCurrent();
      if (state.origin != SendTransactionOrigin.contract ||
          state.requestId == null) {
        throw _reject(DevnetDepositFailureCode.originalAmbiguous);
      }
      if (state.status == SendTransactionStatus.loading) {
        if (_requestId != null) {
          throw _reject(DevnetDepositFailureCode.originalAmbiguous);
        }
        _requestId = state.requestId;
        return;
      }
      if (_requestId == null || !identical(_requestId, state.requestId)) {
        throw _reject(DevnetDepositFailureCode.originalAmbiguous);
      }
      if (state.status == SendTransactionStatus.failure) {
        throw _reject(
          DevnetDepositFailureCode.depositFailed,
          state.error,
        );
      }
      final AccountBlockTemplate? block = state.data;
      if (state.status != SendTransactionStatus.success ||
          _original != null ||
          block == null ||
          state.error != null ||
          block.hash == emptyHash ||
          block.height <= 0 ||
          !_matchesIntent(block)) {
        throw _reject(DevnetDepositFailureCode.originalMismatch);
      }
      _original = block;
      _snapshot = AccountBlockTemplate.fromJson(block.toJson());
      _accepted.complete(block);
    } on Object catch (error) {
      if (error is DevnetDepositFailure) {
        _remember(error);
      } else {
        _reject(DevnetDepositFailureCode.originalMismatch, error);
      }
    }
  }

  bool _matchesIntent(AccountBlockTemplate block) =>
      block.address.toString() == _authority.owner &&
      block.chainIdentifier == _expected.chainIdentifier &&
      block.blockType == _expected.blockType &&
      block.toAddress == _expected.toAddress &&
      block.tokenStandard == _expected.tokenStandard &&
      block.amount == _expected.amount &&
      listEquals(block.data, _expected.data);

  void _requireOriginal() {
    if (_failure != null) throw _failure!;
    if (_sender.isClosed || (_closed && !_confirmed)) {
      throw _reject(DevnetDepositFailureCode.closed);
    }
    try {
      _authority.requireCurrent();
    } on DevnetDepositFailure catch (error) {
      throw _remember(error);
    }
    final AccountBlockTemplate? original = _original;
    final AccountBlockTemplate? snapshot = _snapshot;
    final List<SendRequestResult> results =
        RegistrationPublisher.originalResultsFor(_sender);
    if (original == null ||
        snapshot == null ||
        results.length != _before.length + 1 ||
        !results.last.accepted ||
        !identical(results.last.block, original) ||
        !_matchesIntent(original) ||
        original.hash != snapshot.hash ||
        original.height != snapshot.height) {
      throw _reject(DevnetDepositFailureCode.originalMismatch);
    }
    for (int index = 0; index < _before.length; index++) {
      if (!identical(results[index], _before[index])) {
        throw _reject(DevnetDepositFailureCode.originalAmbiguous);
      }
    }
  }

  /// A verified receipt remains context-bound after its listener is released.
  void requireCurrent() {
    if (!_confirmed) {
      throw _failure ??
          const DevnetDepositFailure(DevnetDepositFailureCode.originalMissing);
    }
    _requireOriginal();
  }

  /// Only read-only exact-hash observations can finish this one attempt.
  Future<void> confirm(
    WidgetTester tester, {
    AccountBlockTemplate? reportedBlock,
    Duration timeout = const Duration(seconds: 90),
    Duration requestTimeout = const Duration(seconds: 5),
    int maxPolls = 90,
  }) async {
    if (_attempted || _closed) {
      throw _reject(DevnetDepositFailureCode.closed);
    }
    _attempted = true;
    if (timeout <= Duration.zero ||
        timeout > const Duration(seconds: 90) ||
        requestTimeout <= Duration.zero ||
        requestTimeout > const Duration(seconds: 5) ||
        maxPolls <= 0 ||
        maxPolls > 90) {
      throw _reject(DevnetDepositFailureCode.deadline);
    }
    final _DepositBudget budget = _DepositBudget(tester, timeout);
    try {
      final AccountBlockTemplate original = await _pumpOriginal(
        tester,
        () => _accepted.future,
        budget,
        budget.remaining,
        _authority.requireCurrent,
      );
      _requireOriginal();
      if (reportedBlock != null && !identical(reportedBlock, original)) {
        throw _reject(DevnetDepositFailureCode.originalMismatch);
      }
      final AccountBlockTemplate snapshot = _snapshot!;
      final Hash hash = Hash.parse(snapshot.hash.toString());
      final InFlightBlocks flights = _registry.forWallet(
        snapshot.chainIdentifier,
        _authority.addresses,
      );
      if (!flights.hasConfirmed(hash) &&
          !flights.value.any((InFlightBlock block) => block.hash == hash)) {
        throw _reject(DevnetDepositFailureCode.originalMissing);
      }
      for (int poll = 0; poll < maxPolls; poll++) {
        _requireOriginal();
        final AccountBlock? block = await _pumpOriginal(
          tester,
          () => _retainRead(
            () => _authority.ledger.getAccountBlockByHash(hash),
          ),
          budget,
          requestTimeout,
          _requireOriginal,
        );
        _requireOriginal();
        if (block != null) {
          if (block.hash != hash ||
              block.height != snapshot.height ||
              !_matchesIntent(block)) {
            throw _reject(DevnetDepositFailureCode.originalMismatch);
          }
          final AccountBlockConfirmationDetail? detail =
              block.confirmationDetail;
          if (detail != null &&
              detail.numConfirmations > 0 &&
              detail.momentumHeight > 0 &&
              detail.momentumHash != emptyHash &&
              detail.momentumTimestamp > 0) {
            await _pumpOriginal<void>(
              tester,
              () => _retainRead(flights.check),
              budget,
              requestTimeout,
              _requireOriginal,
            );
            _requireOriginal();
            if (flights.hasConfirmed(hash)) {
              budget.requireCurrent();
              _confirmed = true;
              return;
            }
          }
        }
        budget.requireCurrent();
        final Duration pause = _minimum(
          const Duration(seconds: 1),
          budget.remaining,
        );
        if (pause <= Duration.zero) {
          throw _reject(DevnetDepositFailureCode.deadline);
        }
        await tester.pump(pause);
      }
      throw _reject(DevnetDepositFailureCode.deadline);
    } on Object catch (error) {
      if (error is DevnetDepositFailure) {
        _remember(error);
        rethrow;
      }
      throw _reject(
        error is TimeoutException
            ? DevnetDepositFailureCode.deadline
            : DevnetDepositFailureCode.readFailed,
        error,
      );
    }
  }

  /// Reads only the original Sentinel API until its exact deposit is visible.
  Future<BigInt> waitForSentinelDeposit(
    WidgetTester tester, {
    Duration timeout = const Duration(seconds: 90),
    Duration requestTimeout = const Duration(seconds: 5),
    int maxPolls = 90,
  }) async {
    try {
      requireCurrent();
      if (_effectAttempted ||
          _expected.toAddress != sentinelAddress ||
          _authority.sentinel == null) {
        throw _reject(DevnetDepositFailureCode.closed);
      }
      _effectAttempted = true;
      if (timeout <= Duration.zero ||
          timeout > const Duration(seconds: 90) ||
          requestTimeout <= Duration.zero ||
          requestTimeout > const Duration(seconds: 5) ||
          maxPolls <= 0 ||
          maxPolls > 90) {
        throw _reject(DevnetDepositFailureCode.deadline);
      }
      final _DepositBudget budget = _DepositBudget(tester, timeout);
      final SentinelApi source = _authority.sentinel!;
      final Address owner = Address.parse(_authority.owner);
      for (int poll = 0; poll < maxPolls; poll++) {
        _requireOriginal();
        final BigInt amount = await _pumpOriginal(
          tester,
          () => _retainRead(() => source.getDepositedQsr(owner)),
          budget,
          requestTimeout,
          _requireOriginal,
        );
        _requireOriginal();
        if (amount == sentinelRegisterQsrAmount) return amount;
        budget.requireCurrent();
        final Duration pause = _minimum(
          const Duration(seconds: 1),
          budget.remaining,
        );
        if (pause <= Duration.zero) {
          throw _reject(DevnetDepositFailureCode.deadline);
        }
        await tester.pump(pause);
      }
      throw _reject(DevnetDepositFailureCode.deadline);
    } on Object catch (error) {
      if (error is DevnetDepositFailure) {
        _remember(error);
        rethrow;
      }
      throw _reject(
        error is TimeoutException
            ? DevnetDepositFailureCode.deadline
            : DevnetDepositFailureCode.readFailed,
        error,
      );
    }
  }

  /// Cancels only this observer, never the sender, SDK, wallet or registry.
  Future<void> close(WidgetTester tester) async {
    _closed = true;
    final Future<void> original = _cancellation ??= _subscription.cancel();
    await _pumpOriginal<void>(
      tester,
      () => original,
      _DepositBudget(tester, const Duration(seconds: 5)),
      const Duration(seconds: 5),
      () {},
    );
  }
}

Duration _minimum(Duration left, Duration right) => left < right ? left : right;

sealed class _PrivateRead {}

/// Retains the exact returned Future and any late outcome for its owner.
final class _PrivateReadOf<T> extends _PrivateRead {
  _PrivateReadOf(this.original) {
    unawaited(
      original.then<void>(
        (T value) {
          result = value;
          completed = true;
        },
        onError: (Object failure, StackTrace trace) {
          error = failure;
          stackTrace = trace;
          completed = true;
        },
      ),
    );
  }

  final Future<T> original;
  T? result;
  Object? error;
  StackTrace? stackTrace;
  bool completed = false;
}

class _DepositBudget {
  _DepositBudget(this.tester, this.limit)
    : end = tester.binding.clock.now().add(limit),
      watch = Stopwatch()..start();

  final WidgetTester tester;
  final Duration limit;
  final DateTime end;
  final Stopwatch watch;

  Duration get remaining => _minimum(
    end.difference(tester.binding.clock.now()),
    limit - watch.elapsed,
  );

  void requireCurrent() {
    if (remaining <= Duration.zero) {
      throw const DevnetDepositFailure(DevnetDepositFailureCode.deadline);
    }
  }
}

Future<T> _pumpOriginal<T>(
  WidgetTester tester,
  Future<T> Function() operation,
  _DepositBudget budget,
  Duration limit,
  VoidCallback guard,
) async {
  budget.requireCurrent();
  guard();
  final Duration cap = _minimum(limit, budget.remaining);
  if (cap <= Duration.zero) {
    throw const DevnetDepositFailure(DevnetDepositFailureCode.deadline);
  }
  final Stopwatch watch = Stopwatch()..start();
  final DateTime end = tester.binding.clock.now().add(cap);
  bool late = false;
  final Duration step = _minimum(const Duration(milliseconds: 100), cap);
  final int turns =
      (cap.inMicroseconds + step.inMicroseconds - 1) ~/ step.inMicroseconds + 1;
  T? value;
  Object? failure;
  bool finished = false;
  unawaited(
    operation()
        .timeout(cap)
        .then<void>(
          (T result) {
            value = result;
            late =
                watch.elapsed >= cap ||
                !tester.binding.clock.now().isBefore(end);
            finished = true;
          },
          onError: (Object error, StackTrace _) {
            failure = error;
            late =
                watch.elapsed >= cap ||
                !tester.binding.clock.now().isBefore(end);
            finished = true;
          },
        ),
  );
  for (int turn = 0; turn < turns && !finished; turn++) {
    // Some original stream-cancellation futures complete on the real queue.
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump(step);
    budget.requireCurrent();
    guard();
  }
  budget.requireCurrent();
  guard();
  if (!finished || late) {
    throw const DevnetDepositFailure(DevnetDepositFailureCode.deadline);
  }
  final Object? originalFailure = failure;
  if (originalFailure != null) {
    if (originalFailure is DevnetDepositFailure) throw originalFailure;
    throw DevnetDepositFailure(
      originalFailure is TimeoutException
          ? DevnetDepositFailureCode.deadline
          : DevnetDepositFailureCode.readFailed,
      originalError: originalFailure,
    );
  }
  return value as T;
}

class _DepositAuthority {
  _DepositAuthority._(
    this.action,
    this.node,
    this.ledger,
    this.stats,
    this.socket,
    this.transport,
    this.url,
    this.addresses,
    this.embedded,
    this.sentinel,
  );

  factory _DepositAuthority.capture(String owner, Address contract) {
    final WalletActionContext? action = WalletActionContext.capture(owner);
    final Zenon? node = app.zenon;
    if (action == null ||
        node == null ||
        kWalletPath == null ||
        kWalletFile?.walletPath != kWalletPath ||
        getChainIdentifier() != DevnetTestContext.chainId ||
        kNodeChainId != DevnetTestContext.chainId) {
      throw const DevnetDepositFailure(
        DevnetDepositFailureCode.sourceUnavailable,
      );
    }
    final LedgerApi ledger = node.ledger;
    final StatsApi stats = node.stats;
    final WsClient socket = node.wsClient;
    final EmbeddedApi? embedded = contract == sentinelAddress
        ? node.embedded
        : null;
    final SentinelApi? sentinel = embedded?.sentinel;
    final _DepositAuthority authority = _DepositAuthority._(
      action,
      node,
      ledger,
      stats,
      socket,
      ledger.client,
      socket.url,
      List<String>.unmodifiable(kDefaultAddressList.whereType<String>()),
      embedded,
      sentinel,
    );
    return authority..requireCurrent();
  }

  final WalletActionContext action;
  final Zenon node;
  final LedgerApi ledger;
  final StatsApi stats;
  final WsClient socket;
  final Client transport;
  final String? url;
  final List<String> addresses;
  final EmbeddedApi? embedded;
  final SentinelApi? sentinel;
  bool revoked = false;

  String get owner => action.ownerAddress;

  void requireCurrent() {
    final EmbeddedApi? api = embedded;
    final SentinelApi? source = sentinel;
    final bool current =
        !revoked &&
        action.isCurrent &&
        identical(app.zenon, node) &&
        identical(node.ledger, ledger) &&
        identical(node.stats, stats) &&
        identical(node.wsClient, socket) &&
        identical(ledger.client, transport) &&
        identical(stats.client, transport) &&
        identical(transport, socket) &&
        (source == null ||
            (api != null &&
                identical(node.embedded, api) &&
                identical(api.sentinel, source) &&
                identical(source.client, transport))) &&
        url != null &&
        url == kCurrentNode &&
        socket.url == url &&
        !socket.isClosed() &&
        socket.status() == WebsocketStatus.running &&
        getChainIdentifier() == DevnetTestContext.chainId &&
        kNodeChainId == DevnetTestContext.chainId;
    if (!current) {
      revoked = true;
      throw const DevnetDepositFailure(DevnetDepositFailureCode.contextChanged);
    }
  }
}
