import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zenon_syrius_wallet_flutter/main.dart' as app;
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/registration_success/registration_publisher.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/send/bloc/send_transaction/send_transaction_bloc.dart';
import 'package:zenon_syrius_wallet_flutter/utils/global.dart';
import 'package:zenon_syrius_wallet_flutter/utils/node_transition.dart';
import 'package:zenon_syrius_wallet_flutter/utils/original_publications.dart';
import 'package:zenon_syrius_wallet_flutter/utils/wallet_action_context.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

import 'devnet_test_context.dart';

/// Finite fixture failures never expose original errors or wallet identities.
enum DevnetPillarFailureCode {
  sourceUnavailable,
  contextChanged,
  originalMissing,
  originalMismatch,
  originalAmbiguous,
  alreadyAttempted,
  closed,
  deadline,
  readFailed,
  observationMismatch,
  unresolved,
}

class DevnetPillarFailure implements Exception {
  const DevnetPillarFailure(
    this.code, {
    this.originalError,
    this.lookups = 0,
    this.pendingSeen = false,
    this.heightSeen = false,
    this.heightConflict = false,
    this.frontierAdvanced = false,
  });

  final DevnetPillarFailureCode code;
  final Object? originalError;
  final int lookups;
  final bool pendingSeen;
  final bool heightSeen;
  final bool heightConflict;
  final bool frontierAdvanced;

  @override
  String toString() => jsonEncode(<String, Object>{
    'code': code.name,
    'lookups': lookups,
    'pendingSeen': pendingSeen,
    'heightSeen': heightSeen,
    'heightConflict': heightConflict,
    'frontierAdvanced': frontierAdvanced,
  });
}

/// Private in-memory evidence retains the exact Future and any late outcome.
class DevnetPillarRead {
  DevnetPillarRead._(this.kind, this.original) {
    unawaited(
      original.then<void>(
        (Object? value) {
          _value = value;
          _completed = true;
        },
        onError: (Object error, StackTrace trace) {
          _error = error;
          _trace = trace;
          _completed = true;
        },
      ),
    );
  }

  final String kind;
  final Future<Object?> original;
  Object? _value;
  Object? _error;
  StackTrace? _trace;
  bool _completed = false;

  @visibleForTesting
  Object? get value => _value;

  @visibleForTesting
  Object? get error => _error;

  @visibleForTesting
  StackTrace? get stackTrace => _trace;

  @visibleForTesting
  bool get completed => _completed;
}

/// Observes one genuine registration without creating publication authority.
class DevnetPillarObservation {
  DevnetPillarObservation._(
    SendTransactionBloc sender,
    WalletActionContext action,
    Object file,
    AccountBlockTemplate expected,
  ) : _sender = sender,
      _action = action,
      _file = file,
      _expected = AccountBlockTemplate.fromJson(expected.toJson()),
      _node = action.client,
      _ledger = action.client.ledger,
      _stats = action.client.stats,
      _socket = action.client.wsClient,
      _transport = action.client.ledger.client,
      _embedded = action.client.embedded,
      _pillar = action.client.embedded.pillar,
      _url = action.client.wsClient.url,
      _beforeSender = RegistrationPublisher.originalResultsFor(sender),
      _beforeFile = OriginalPublications.snapshot(file),
      _beforeNode = OriginalPublications.snapshot(action.client);

  /// Capture immediately before the one original Register tap.
  factory DevnetPillarObservation.capture({
    required Object scenario,
    required SendTransactionBloc sender,
    required String ownerAddress,
    required AccountBlockTemplate expectedRegistration,
  }) {
    if (_captures[scenario] != null) {
      throw const DevnetPillarFailure(
        DevnetPillarFailureCode.originalAmbiguous,
      );
    }
    final WalletActionContext? action = WalletActionContext.capture(
      ownerAddress,
    );
    final Object? file = kWalletFile;
    if (action == null ||
        file == null ||
        kWalletPath == null ||
        kWalletFile?.walletPath != kWalletPath ||
        sender.isClosed ||
        sender.busy.value ||
        !OriginalPublications.canChangeTransport(file) ||
        !OriginalPublications.canChangeTransport(action.client) ||
        expectedRegistration.chainIdentifier != DevnetTestContext.chainId ||
        expectedRegistration.blockType != BlockTypeEnum.userSend.index ||
        expectedRegistration.toAddress != pillarAddress ||
        expectedRegistration.tokenStandard != znnZts ||
        expectedRegistration.amount != pillarRegisterZnnAmount) {
      throw const DevnetPillarFailure(
        DevnetPillarFailureCode.sourceUnavailable,
      );
    }
    final DevnetPillarObservation observer = DevnetPillarObservation._(
      sender,
      action,
      file,
      expectedRegistration,
    )..requireCurrent();
    _captures[scenario] = observer;
    return observer;
  }

  static final Expando<DevnetPillarObservation> _captures =
      Expando<DevnetPillarObservation>();

  static DevnetPillarObservation forScenario(Object scenario) =>
      _captures[scenario] ??
      (throw const DevnetPillarFailure(
        DevnetPillarFailureCode.originalMissing,
      ));

  final SendTransactionBloc _sender;
  final WalletActionContext _action;
  final Object _file;
  final AccountBlockTemplate _expected;
  final Zenon _node;
  final LedgerApi _ledger;
  final StatsApi _stats;
  final WsClient _socket;
  final Client _transport;
  final EmbeddedApi _embedded;
  final PillarApi _pillar;
  final String? _url;
  final List<SendRequestResult> _beforeSender;
  final List<OriginalPublication<dynamic>> _beforeFile;
  final List<OriginalPublication<dynamic>> _beforeNode;
  final List<DevnetPillarRead> _reads = <DevnetPillarRead>[];
  AccountBlockTemplate? _original;
  OriginalPublication<dynamic>? _operation;
  String? _frozen;
  DevnetPillarFailure? _failure;
  _PillarBudget? _budget;
  Duration _requestTimeout = const Duration(seconds: 5);
  int _maxPolls = 90;
  bool _blockAttempted = false;
  bool _blockFound = false;
  bool _pillarAttempted = false;
  bool _pendingSeen = false;
  bool _heightSeen = false;
  bool _heightConflict = false;
  bool _frontierAdvanced = false;
  int? _frontierHeight;
  int? _frontierTime;
  int _lookups = 0;

  @visibleForTesting
  List<DevnetPillarRead> get originalReads =>
      List<DevnetPillarRead>.unmodifiable(_reads);

  /// These observations describe uncertainty and never authorize another send.
  Map<String, Object> get diagnostics => Map<String, Object>.unmodifiable(
    <String, Object>{
      'lookups': _lookups,
      'pendingSeen': _pendingSeen,
      'heightSeen': _heightSeen,
      'heightConflict': _heightConflict,
      'frontierAdvanced': _frontierAdvanced,
    },
  );

  DevnetPillarFailure _remember(DevnetPillarFailure failure) =>
      _failure ??= failure;

  DevnetPillarFailure _reject(
    DevnetPillarFailureCode code, [
    Object? originalError,
  ]) => _remember(
    DevnetPillarFailure(
      code,
      originalError: originalError,
      lookups: _lookups,
      pendingSeen: _pendingSeen,
      heightSeen: _heightSeen,
      heightConflict: _heightConflict,
      frontierAdvanced: _frontierAdvanced,
    ),
  );

  T _oneNew<T>(List<T> before, List<T> after) {
    if (after.length != before.length + 1) {
      throw _reject(DevnetPillarFailureCode.originalAmbiguous);
    }
    for (int index = 0; index < before.length; index++) {
      if (!identical(before[index], after[index])) {
        throw _reject(DevnetPillarFailureCode.originalAmbiguous);
      }
    }
    return after.last;
  }

  bool _intent(AccountBlockTemplate block) =>
      block.address.toString() == _action.ownerAddress &&
      block.chainIdentifier == DevnetTestContext.chainId &&
      block.blockType == _expected.blockType &&
      block.toAddress == _expected.toAddress &&
      block.tokenStandard == _expected.tokenStandard &&
      block.amount == _expected.amount &&
      listEquals(block.data, _expected.data);

  /// The result must be shared by the sender and both actual operation lanes.
  void retain(AccountBlockTemplate returned) {
    requireCurrent();
    if (_original != null) {
      throw _reject(DevnetPillarFailureCode.alreadyAttempted);
    }
    final SendRequestResult result = _oneNew(
      _beforeSender,
      RegistrationPublisher.originalResultsFor(_sender),
    );
    final OriginalPublication<dynamic> operation = _oneNew(
      _beforeFile,
      OriginalPublications.snapshot(_file),
    );
    final OriginalPublication<dynamic> nodeOperation = _oneNew(
      _beforeNode,
      OriginalPublications.snapshot(_node),
    );
    if (!result.accepted ||
        !identical(result.block, returned) ||
        !identical(operation, nodeOperation) ||
        !operation.settled ||
        operation.future == null ||
        operation.error != null ||
        operation.releaseError != null ||
        !identical(operation.result, returned) ||
        operation.acceptedHash != returned.hash.toString() ||
        returned.hash == emptyHash ||
        returned.height <= 0 ||
        !_intent(returned)) {
      throw _reject(DevnetPillarFailureCode.originalMismatch);
    }
    _operation = operation;
    _original = returned;
    _frozen = jsonEncode(returned.toJson());
    requireCurrent();
  }

  /// Fresh wrappers cannot alter the retained hash, owner, chain or height.
  AccountBlockTemplate get originalBlock {
    requireCurrent();
    final String? frozen = _frozen;
    if (frozen == null) {
      throw _reject(DevnetPillarFailureCode.originalMissing);
    }
    return AccountBlockTemplate.fromJson(
      jsonDecode(frozen) as Map<String, dynamic>,
    );
  }

  void requireCurrent() {
    if (_failure != null) throw _failure!;
    if (_sender.isClosed) {
      throw _reject(DevnetPillarFailureCode.closed);
    }
    if (!_action.isCurrent ||
        NodeTransitions.pending ||
        !identical(app.zenon, _node) ||
        !identical(kWalletFile, _file) ||
        kWalletFile?.walletPath != kWalletPath ||
        !identical(_node.ledger, _ledger) ||
        !identical(_node.stats, _stats) ||
        !identical(_node.wsClient, _socket) ||
        !identical(_node.embedded, _embedded) ||
        !identical(_embedded.pillar, _pillar) ||
        !identical(_ledger.client, _transport) ||
        !identical(_stats.client, _transport) ||
        !identical(_pillar.client, _transport) ||
        !identical(_transport, _socket) ||
        _url == null ||
        _url != kCurrentNode ||
        _socket.url != _url ||
        _socket.isClosed() ||
        _socket.status() != WebsocketStatus.running ||
        getChainIdentifier() != DevnetTestContext.chainId ||
        kNodeChainId != DevnetTestContext.chainId) {
      throw _reject(DevnetPillarFailureCode.contextChanged);
    }
    final AccountBlockTemplate? original = _original;
    if (original == null) return;
    final SendRequestResult result = _oneNew(
      _beforeSender,
      RegistrationPublisher.originalResultsFor(_sender),
    );
    if (!identical(result.block, original) ||
        !result.accepted ||
        !identical(
          _oneNew(_beforeFile, OriginalPublications.snapshot(_file)),
          _operation,
        ) ||
        !identical(
          _oneNew(_beforeNode, OriginalPublications.snapshot(_node)),
          _operation,
        ) ||
        _operation?.releaseError != null ||
        _operation?.acceptedHash != original.hash.toString() ||
        jsonEncode(original.toJson()) != _frozen) {
      throw _reject(DevnetPillarFailureCode.originalMismatch);
    }
  }

  bool _sameOriginal(AccountBlock block, AccountBlockTemplate expected) =>
      block.hash == expected.hash &&
      block.height == expected.height &&
      block.previousHash == expected.previousHash &&
      _intent(block);

  /// One shared deadline covers both original postcondition reads.
  Future<AccountBlock> readBlock(
    WidgetTester tester, {
    Duration timeout = const Duration(seconds: 90),
    Duration requestTimeout = const Duration(seconds: 5),
    int maxPolls = 90,
  }) async {
    requireCurrent();
    if (_blockAttempted) {
      throw _reject(DevnetPillarFailureCode.alreadyAttempted);
    }
    _blockAttempted = true;
    if (timeout <= Duration.zero ||
        timeout > const Duration(seconds: 90) ||
        requestTimeout <= Duration.zero ||
        requestTimeout > const Duration(seconds: 5) ||
        maxPolls <= 0 ||
        maxPolls > 90) {
      throw _reject(DevnetPillarFailureCode.deadline);
    }
    _budget = _PillarBudget(tester, timeout);
    _requestTimeout = requestTimeout;
    _maxPolls = maxPolls;
    final AccountBlockTemplate expected = originalBlock;
    for (int poll = 0; poll < maxPolls; poll++) {
      final AccountBlock? block = await _read(
        tester,
        'block',
        () => _ledger.getAccountBlockByHash(expected.hash),
      );
      if (block != null) {
        if (!_sameOriginal(block, expected)) {
          throw _reject(DevnetPillarFailureCode.observationMismatch);
        }
        final AccountBlockConfirmationDetail? detail = block.confirmationDetail;
        if (detail != null &&
            detail.numConfirmations > 0 &&
            detail.momentumHeight > 0 &&
            detail.momentumHash != emptyHash &&
            detail.momentumTimestamp > 0) {
          _blockFound = true;
          return block;
        }
      }
      await _diagnose(tester, expected);
      if (poll + 1 < maxPolls) await _pause(tester);
    }
    throw _reject(DevnetPillarFailureCode.unresolved);
  }

  Future<void> _diagnose(
    WidgetTester tester,
    AccountBlockTemplate expected,
  ) async {
    final AccountBlockList pending = await _read(
      tester,
      'pending',
      () => _ledger.getUnconfirmedBlocksByAddress(
        expected.address,
        pageSize: 100,
      ),
    );
    final List<AccountBlock>? pendingBlocks = pending.list;
    if (pendingBlocks == null || pendingBlocks.length > 100) {
      throw _reject(DevnetPillarFailureCode.observationMismatch);
    }
    for (final AccountBlock block in pendingBlocks) {
      _checkAccount(block, expected);
      if (block.hash == expected.hash) {
        if (!_sameOriginal(block, expected)) {
          throw _reject(DevnetPillarFailureCode.observationMismatch);
        }
        _pendingSeen = true;
      }
    }
    final AccountBlockList atHeight = await _read(
      tester,
      'height',
      () => _ledger.getAccountBlocksByHeight(
        expected.address,
        expected.height,
        1,
      ),
    );
    final List<AccountBlock>? heightBlocks = atHeight.list;
    if (heightBlocks == null || heightBlocks.length > 1) {
      throw _reject(DevnetPillarFailureCode.observationMismatch);
    }
    for (final AccountBlock block in heightBlocks) {
      _checkAccount(block, expected);
      if (block.height != expected.height) {
        throw _reject(DevnetPillarFailureCode.observationMismatch);
      }
      if (block.hash == expected.hash) {
        if (!_sameOriginal(block, expected)) {
          throw _reject(DevnetPillarFailureCode.observationMismatch);
        }
        _heightSeen = true;
      } else {
        _heightConflict = true;
      }
    }
    final Momentum frontier = await _read(
      tester,
      'frontier',
      _ledger.getFrontierMomentum,
    );
    if (frontier.chainIdentifier != DevnetTestContext.chainId ||
        frontier.height <= 0 ||
        frontier.hash == emptyHash ||
        frontier.timestamp <= 0) {
      throw _reject(DevnetPillarFailureCode.observationMismatch);
    }
    final int? oldHeight = _frontierHeight;
    final int? oldTime = _frontierTime;
    if (oldHeight != null && oldTime != null) {
      _frontierAdvanced =
          _frontierAdvanced ||
          (frontier.height > oldHeight && frontier.timestamp > oldTime);
    }
    _frontierHeight = frontier.height;
    _frontierTime = frontier.timestamp;
  }

  void _checkAccount(AccountBlock block, AccountBlockTemplate expected) {
    if (block.chainIdentifier != expected.chainIdentifier ||
        block.address != expected.address ||
        block.hash == emptyHash ||
        block.height <= 0) {
      throw _reject(DevnetPillarFailureCode.observationMismatch);
    }
  }

  Future<PillarInfo> readPillar(WidgetTester tester) async {
    requireCurrent();
    if (!_blockFound || _pillarAttempted) {
      throw _reject(DevnetPillarFailureCode.alreadyAttempted);
    }
    _pillarAttempted = true;
    for (int poll = 0; poll < _maxPolls; poll++) {
      final PillarInfo? value = await _read(
        tester,
        'pillar',
        () => _pillar.getByName(DevnetTestContext.testPillarName),
      );
      if (value != null) return value;
      if (poll + 1 < _maxPolls) await _pause(tester);
    }
    throw _reject(DevnetPillarFailureCode.unresolved);
  }

  Future<void> _pause(WidgetTester tester) async {
    final Duration remaining = _remaining();
    final Duration step = _minimum(const Duration(seconds: 1), remaining);
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump(step);
    _remaining();
    requireCurrent();
  }

  Duration _remaining() {
    final _PillarBudget? budget = _budget;
    final Duration remaining = budget?.remaining ?? Duration.zero;
    if (remaining <= Duration.zero) {
      throw _reject(DevnetPillarFailureCode.deadline);
    }
    return remaining;
  }

  Future<T> _read<T>(
    WidgetTester tester,
    String kind,
    Future<T> Function() fetch,
  ) async {
    requireCurrent();
    final Duration cap = _minimum(_requestTimeout, _remaining());
    if (cap <= Duration.zero || _reads.length >= 450) {
      throw _reject(DevnetPillarFailureCode.deadline);
    }
    if (kind == 'block') _lookups++;
    final Future<T> original;
    try {
      original = fetch();
    } on Object catch (error) {
      if (error is DevnetPillarFailure) throw _remember(error);
      throw _reject(DevnetPillarFailureCode.readFailed, error);
    }
    _reads.add(DevnetPillarRead._(kind, original));
    final DateTime end = tester.binding.clock.now().add(cap);
    final Stopwatch watch = Stopwatch()..start();
    final Duration step = _minimum(const Duration(milliseconds: 100), cap);
    final int turns =
        (cap.inMicroseconds + step.inMicroseconds - 1) ~/ step.inMicroseconds +
        1;
    T? value;
    Object? error;
    bool finished = false;
    bool late = false;
    unawaited(
      original
          .timeout(cap)
          .then<void>(
            (T result) {
              value = result;
              late =
                  watch.elapsed >= cap ||
                  !tester.binding.clock.now().isBefore(end);
              finished = true;
            },
            onError: (Object failure, StackTrace _) {
              error = failure;
              late =
                  watch.elapsed >= cap ||
                  !tester.binding.clock.now().isBefore(end);
              finished = true;
            },
          ),
    );
    for (int turn = 0; turn < turns && !finished; turn++) {
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump(step);
      _remaining();
      requireCurrent();
    }
    _remaining();
    requireCurrent();
    if (!finished || late) {
      throw _reject(DevnetPillarFailureCode.deadline);
    }
    final Object? originalError = error;
    if (originalError != null) {
      if (originalError is DevnetPillarFailure) {
        throw _remember(originalError);
      }
      throw _reject(
        originalError is TimeoutException
            ? DevnetPillarFailureCode.deadline
            : DevnetPillarFailureCode.readFailed,
        originalError,
      );
    }
    return value as T;
  }
}

Duration _minimum(Duration left, Duration right) => left < right ? left : right;

class _PillarBudget {
  _PillarBudget(this.tester, this.limit)
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
}
