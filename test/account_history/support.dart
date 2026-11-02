import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:zenon_syrius_wallet_flutter/utils/account_block_utils.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

const int historyChain = 321;
String historyHash(int value) => value.toRadixString(16).padLeft(64, '0');
Address historyAddress(int value) =>
    Address('z', <int>[0, ...List<int>.filled(19, value)]);

class HistoryReplies {
  final List<(String, List<dynamic>)> calls = <(String, List<dynamic>)>[];
  Future<dynamic> Function(String, List<dynamic>)? answer;
  Future<dynamic> dispatch(String method, dynamic parameters) {
    final List<dynamic> arguments = List<dynamic>.of(
      parameters as List<dynamic>,
    );
    calls.add((method, arguments));
    return answer?.call(method, arguments) ??
        Future<dynamic>.error(
          StateError('Unconfigured synthetic history reply'),
        );
  }
}

class HistoryClient extends Client {
  HistoryClient(this.replies);
  final HistoryReplies replies;
  @override
  Future<dynamic> sendRequest(String method, [dynamic parameters]) =>
      replies.dispatch(method, parameters);
}

/// This socket overrides dispatch and is never initialized or connected.
class HistorySocket extends WsClient {
  HistorySocket(this.replies);
  final HistoryReplies replies;
  @override
  Future<dynamic> sendRequest(String method, [dynamic parameters]) =>
      replies.dispatch(method, parameters);
}

/// Real LedgerApi JSON decoding over finite, fixture-owned transport answers.
class HistoryFixture {
  HistoryFixture({bool socket = false})
    : _previousChain = getChainIdentifier() {
    setChainIdentifier(chainIdentifier: historyChain);
    transport = socket
        ? (HistorySocket(replies)..url = 'ws://fixture.invalid/original')
        : HistoryClient(replies);
    ledger = LedgerApi()..setClient(transport);
    replies.answer = (String method, List<dynamic> parameters) {
      if (method == 'ledger.getAccountBlocksByPage') {
        final int page = parameters[1] as int;
        if (page >= pages.length) {
          return Future<dynamic>.error(StateError('Unexpected synthetic page'));
        }
        return Future<dynamic>.value(pages[page]);
      }
      if (method == 'ledger.getAccountBlocksByHeight') {
        return Future<dynamic>.value(heightReply);
      }
      return Future<dynamic>.error(
        StateError('Unexpected synthetic history method'),
      );
    };
    addTearDown(close);
  }
  final int _previousChain;
  final Address address = historyAddress(1);
  final HistoryReplies replies = HistoryReplies();
  late final Client transport;
  late final LedgerApi ledger;
  final List<Map<String, dynamic>> pages = <Map<String, dynamic>>[];
  Map<String, dynamic>? heightReply;
  bool current = true;
  bool _closed = false;
  final List<void Function()> _release = <void Function()>[];
  final List<Future<void>> _settled = <Future<void>>[];

  Completer<T> ownCompleter<T>() {
    final Completer<T> reply = Completer<T>();
    unawaited(
      reply.future.then<void>((T _) {}, onError: (Object _, StackTrace _) {}),
    );
    _release.add(() {
      if (!reply.isCompleted) {
        reply.completeError(
          StateError('Synthetic history fixture ended'),
          StackTrace.current,
        );
      }
    });
    return reply;
  }

  Future<T> observe<T>(Future<T> original) {
    _settled.add(
      original.then<void>((T _) {}, onError: (Object _, StackTrace _) {}),
    );
    return original;
  }

  Future<List<AccountBlock>> history({int after = 0, int maxPages = 4096}) =>
      observe(
        AccountBlockUtils.getAccountBlocksAfterTime(
          address,
          after,
          ledger: ledger,
          canRead: () => current,
          maxPages: maxPages,
        ),
      );

  Future<int?> timestamp({int height = 5}) => observe(
    AccountBlockUtils.getTimeForAccountBlockHeight(
      address,
      height,
      ledger: ledger,
      canRead: () => current,
    ),
  );

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    current = false;
    for (final void Function() release in _release) {
      release();
    }
    await Future.wait<void>(List<Future<void>>.of(_settled));
    setChainIdentifier(chainIdentifier: _previousChain);
    if (transport is HistorySocket) {
      await (transport as HistorySocket).restartedStreamController.close();
    }
  }
}

AccountBlock historyBlock(
  int height, {
  Address? address,
  int chain = historyChain,
  int? timestamp,
  int confirmations = 1,
}) {
  final AccountBlockTemplate block =
      AccountBlockTemplate(blockType: BlockTypeEnum.userSend.index)
        ..address = (address ?? historyAddress(1))
        ..chainIdentifier = chain
        ..height = height
        ..hash = Hash.parse(historyHash(height))
        ..previousHash = height > 1
            ? Hash.parse(historyHash(height - 1))
            : emptyHash;
  return AccountBlock.fromJson(<String, dynamic>{
    ...block.toJson(),
    'descendantBlocks': const <dynamic>[],
    'usedPlasma': 0,
    'basePlasma': 0,
    'changesHash': historyHash(9000),
    'token': null,
    'pairedAccountBlock': null,
    'confirmationDetail': <String, dynamic>{
      'numConfirmations': confirmations,
      'momentumHeight': height,
      'momentumHash': historyHash(9001),
      'momentumTimestamp': timestamp ?? 1000 + height,
    },
  });
}

List<AccountBlock> descendingHistory(int highest, int lowest) => <AccountBlock>[
  for (int height = highest; height >= lowest; height--) historyBlock(height),
];

Map<String, dynamic> historyPage(
  List<AccountBlock>? blocks, {
  int? count,
  bool? more,
}) => AccountBlockList(list: blocks, count: count, more: more).toJson();
