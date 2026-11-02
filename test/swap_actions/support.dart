import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:zenon_syrius_wallet_flutter/blocs/p2p_swap/htlc_swap/swap_action_origin.dart';
import 'package:zenon_syrius_wallet_flutter/blocs/p2p_swap/htlc_swap/swap_actions.dart';
import 'package:zenon_syrius_wallet_flutter/model/p2p_swap/htlc_swap.dart';
import 'package:zenon_syrius_wallet_flutter/model/p2p_swap/p2p_swap.dart';
import 'package:zenon_syrius_wallet_flutter/utils/constants.dart';
import 'package:zenon_syrius_wallet_flutter/utils/format_utils.dart';
import 'package:zenon_syrius_wallet_flutter/utils/zts_utils.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

String actionAddress(int byte) =>
    Address('z', <int>[0, ...List<int>.filled(19, byte)]).toString();
String actionHash(int number) => number.toRadixString(16).padLeft(64, '0');

class StoreReservation implements SwapPersistenceReservation {
  int writes = 0;
  int refusals = 0;
  int unknowns = 0;
  HtlcSwap? stored;
  Future<void>? reply;
  Object? error;
  Future<void>? original;
  @override
  Future<void> store(HtlcSwap swap) {
    writes++;
    stored = HtlcSwap.fromJson(swap.toJson());
    return original = error == null
        ? reply ?? Future<void>.value()
        : Future<void>.error(error!);
  }

  @override
  void refuse() {
    refusals++;
  }

  @override
  void retainUnknown(Object error, StackTrace trace) {
    unknowns++;
  }
}

class PublicationReservation implements SwapPublicationReservation {
  int preparations = 0;
  int acceptances = 0;
  int refusals = 0;
  int unknowns = 0;
  Map<String, dynamic>? recovery;
  String? acceptedHash;
  Future<void>? prepareReply;
  Future<void>? acceptedReply;
  Future<void>? refusalReply;
  Future<void>? prepareOriginal;
  Future<void>? acceptedOriginal;
  @override
  Future<void> prepare({Map<String, dynamic>? recovery}) {
    preparations++;
    this.recovery = recovery == null ? null : Map<String, dynamic>.of(recovery);
    return prepareOriginal = prepareReply ?? Future<void>.value();
  }

  @override
  Future<void> accepted(String exactHash) {
    acceptances++;
    acceptedHash = exactHash;
    return acceptedOriginal = acceptedReply ?? Future<void>.value();
  }

  @override
  Future<void> refuseBeforePublication() {
    refusals++;
    return refusalReply ?? prepareOriginal ?? Future<void>.value();
  }

  @override
  void retainUnknown(Object error, StackTrace trace) {
    unknowns++;
  }
}

/// Protocol-shaped values and pure ABI builders contain no wallet or signer.
class ActionFixture {
  ActionFixture() {
    tokens[token.tokenStandard.toString()] = token;
    tokens[receiving.tokenStandard.toString()] = receiving;
    addTearDown(close);
  }
  final Object identity = Object();
  final String owner = actionAddress(1);
  final String counterparty = actionAddress(2);
  final Token token = Token.fromJson(kZnnCoin.toJson());
  final Token receiving = Token.fromJson(kQsrCoin.toJson());
  final Map<String, Token?> tokens = <String, Token?>{};
  final Map<String, HtlcInfo> deposits = <String, HtlcInfo>{};
  final Map<String, AccountBlock?> creations = <String, AccountBlock?>{};
  final StoreReservation store = StoreReservation();
  final PublicationReservation marker = PublicationReservation();
  SwapPublicationReservation Function(String, String, String)? reserveMarker;
  final HtlcApi builder = HtlcApi();
  bool current = true;
  int chainId = 321;
  int revision = 0;
  List<String>? members;
  String? selected;
  int now = 1000;
  int storeReservations = 0;
  int markerReservations = 0;
  int senderCaptures = 0;
  int publications = 0;
  int rearmCalls = 0;
  int timeReads = 0;
  bool rearm = false;
  BigInt balance = BigInt.from(100000000000);
  Future<Token?>? tokenReply;
  Future<AccountInfo>? accountReply;
  Future<AccountBlockTemplate>? publicationReply;
  Future<AccountBlockTemplate>? publicationOriginal;
  Future<HtlcInfo> Function(String)? htlcRead;
  Future<AccountBlock?> Function(String)? creationRead;
  Future<int> Function()? timeRead;
  Future<Token?> Function(String)? tokenRead;
  Future<AccountInfo> Function(String)? accountRead;
  Future<List<AccountBlock>> Function(int)? contractRead;
  AccountBlockTemplate Function(
    Token,
    BigInt,
    Address,
    int,
    int,
    int,
    List<int>,
  )?
  createBlock;
  AccountBlockTemplate Function(Hash, List<int>)? unlockBlock;
  AccountBlockTemplate Function(Hash)? reclaimBlock;
  AccountBlockTemplate? sent;
  AccountBlock? confirmed;
  HtlcInfo? deposit;
  List<AccountBlock> contractBlocks = <AccountBlock>[];
  List<HtlcSwap> history = <HtlcSwap>[];
  void Function()? onToken;
  void Function()? onPublish;
  final List<String> events = <String>[];
  final List<String> htlcReads = <String>[];
  final List<String> creationReads = <String>[];
  final List<String> accountReads = <String>[];
  final List<int> contractReads = <int>[];
  final List<(String, String, String)> markerKeys =
      <(String, String, String)>[];
  final List<void Function()> _release = <void Function()>[];
  final List<Future<void>> _settled = <Future<void>>[];
  bool _closed = false;

  Completer<T> ownCompleter<T>() {
    final Completer<T> reply = Completer<T>();
    unawaited(
      reply.future.then<void>((T _) {}, onError: (Object _, StackTrace _) {}),
    );
    _release.add(() {
      if (!reply.isCompleted) {
        reply.completeError(
          const SwapActionRefused('fixture-ended'),
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

  /// Ends fixture-owned inputs, then awaits their original actions.
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    current = false;
    for (final void Function() release in _release) {
      release();
    }
    await Future.wait<void>(List<Future<void>>.of(_settled));
  }

  SwapActionOrigin origin({bool Function()? sourceIsCurrent}) {
    final int originalRevision = revision;
    return SwapActionOrigin(
      identity: identity,
      chainId: chainId,
      ownerAddress: selected ?? owner,
      members: members ?? <String>[owner],
      isCurrent: () =>
          current &&
          revision == originalRevision &&
          (sourceIsCurrent?.call() ?? true),
      readHtlc: (String id) async {
        events.add('read-htlc');
        htlcReads.add(id);
        if (htlcRead != null) return htlcRead!(id);
        if (deposits.containsKey(id)) return deposits[id]!;
        if (deposit == null) {
          throw const SwapActionRefused('fixture-no-deposit');
        }
        return deposit!;
      },
      readBlock: (String id) {
        creationReads.add(id);
        return creationRead?.call(id) ??
            Future<AccountBlock?>.value(
              creations.containsKey(id) ? creations[id] : confirmed,
            );
      },
      readChainTime: () {
        timeReads++;
        return timeRead?.call() ?? Future<int>.value(now);
      },
      readAccount: (String address) {
        accountReads.add(address);
        return accountRead?.call(address) ??
            accountReply ??
            Future<AccountInfo>.value(
              AccountInfo(
                address: address,
                blockCount: 1,
                balanceInfoList: <BalanceInfoListItem>[
                  BalanceInfoListItem(token: token, balance: balance),
                ],
              ),
            );
      },
      readToken: (String standard) {
        events.add('read-token');
        onToken?.call();
        return tokenRead?.call(standard) ??
            tokenReply ??
            Future<Token?>.value(
              tokens[standard] == null
                  ? null
                  : Token.fromJson(tokens[standard]!.toJson()),
            );
      },
      readHistory: () => history,
      readContractBlocks: (int after) {
        contractReads.add(after);
        return contractRead?.call(after) ??
            Future<List<AccountBlock>>.value(contractBlocks);
      },
      reserveStore: () {
        storeReservations++;
        events.add('reserve-store');
        return store;
      },
      reservePublication: (String kind, String target, String owner) {
        markerKeys.add((kind, target, owner));
        markerReservations++;
        events.add('reserve-marker');
        return reserveMarker?.call(kind, target, owner) ?? marker;
      },
      rearmStart: (String owner, AccountBlock block) async {
        rearmCalls++;
        return rearm;
      },
      capturePublisher: (String address) {
        senderCaptures++;
        events.add('capture-sender');
        return (AccountBlockTemplate block, String purpose) {
          publications++;
          events.add('publish');
          sent = block
            ..address = Address.parse(address)
            ..chainIdentifier = chainId
            ..height = 1
            ..hash = Hash.parse(actionHash(publications));
          onPublish?.call();
          return publicationOriginal =
              publicationReply ?? Future<AccountBlockTemplate>.value(sent);
        };
      },
      create:
          (
            Token token,
            BigInt amount,
            Address to,
            int expiry,
            int hashType,
            int keySize,
            List<int> hash,
          ) =>
              createBlock?.call(
                token,
                amount,
                to,
                expiry,
                hashType,
                keySize,
                hash,
              ) ??
              builder.create(
                token,
                amount,
                to,
                expiry,
                hashType,
                keySize,
                hash,
              ),
      unlock: (Hash id, List<int> value) =>
          unlockBlock?.call(id, value) ?? builder.unlock(id, value),
      reclaim: (Hash id) => reclaimBlock?.call(id) ?? builder.reclaim(id),
    );
  }

  Future<SwapActionResult> start({SwapActionOrigin? source, BigInt? amount}) =>
      observe(
        SwapActions.start(
          source ?? origin(),
          selfAddress: owner,
          counterparty: counterparty,
          fromToken: token,
          amount: amount ?? BigInt.from(100),
          hashType: htlcHashTypeSha3,
          preimageSource: () => List<int>.filled(htlcPreimageDefaultLength, 7),
        ),
      );

  Future<HtlcInfo> initial(HtlcInfo live, {SwapActionOrigin? source}) =>
      observe(SwapActions.initial(source ?? origin(), live.id));
  Future<SwapActionResult> join(
    HtlcInfo live, {
    SwapActionOrigin? source,
    Token? sending,
    Token? receive,
    BigInt? amount,
  }) => observe(
    SwapActions.join(
      source ?? origin(),
      initialDeposit: live,
      fromToken: sending ?? token,
      toToken: receive ?? receiving,
      amount: amount ?? BigInt.from(100),
    ),
  );
  Future<SwapActionResult> complete(
    HtlcSwap swap, {
    SwapActionOrigin? source,
  }) => observe(SwapActions.complete(source ?? origin(), swap));
  Future<SwapActionResult> reclaim(
    Hash id, {
    String? signer,
    SwapActionOrigin? source,
  }) => observe(SwapActions.reclaim(source ?? origin(), id, signer ?? owner));

  HtlcInfo seedInitial({
    int id = 100,
    int? expires,
    int hashType = htlcHashTypeSha3,
    List<int>? lock,
  }) {
    final HtlcInfo value = HtlcInfo(
      id: Hash.parse(actionHash(id)),
      timeLocked: Address.parse(counterparty),
      hashLocked: Address.parse(owner),
      tokenStandard: receiving.tokenStandard,
      amount: BigInt.from(250),
      expirationTime: expires ?? now + kInitialHtlcDuration.inSeconds,
      hashType: hashType,
      keyMaxSize: htlcPreimageMaxLength,
      hashLock:
          lock ??
          Hash.digest(
            List<int>.filled(htlcPreimageDefaultLength, 7),
          ).getBytes()!,
    );
    seedDeposit(value, token: receiving, timestamp: now - 10);
    deposit = value;
    return value;
  }

  void seedDeposit(
    HtlcInfo value, {
    required Token token,
    required int timestamp,
  }) {
    deposits[value.id.toString()] = value;
    final AccountBlockTemplate creation =
        builder.create(
            token,
            value.amount,
            value.hashLocked,
            value.expirationTime,
            value.hashType,
            value.keyMaxSize,
            value.hashLock,
          )
          ..address = value.timeLocked
          ..hash = value.id
          ..height = 5
          ..chainIdentifier = chainId;
    final AccountBlock original = confirmedAction(
      creation,
      timestamp: timestamp,
      token: token,
    );
    creations[value.id.toString()] = original;
    final AccountBlockTemplate effect =
        AccountBlockTemplate(blockType: BlockTypeEnum.contractReceive.index)
          ..address = htlcAddress
          ..fromBlockHash = original.hash
          ..height = 20 + contractBlocks.length
          ..hash = Hash.parse(actionHash(1000 + contractBlocks.length))
          ..chainIdentifier = chainId;
    contractBlocks.add(
      confirmedAction(effect, paired: original, timestamp: timestamp + 1),
    );
  }

  HtlcSwap seedSwap({P2pSwapDirection direction = P2pSwapDirection.incoming}) {
    final bool incoming = direction == P2pSwapDirection.incoming;
    final HtlcInfo initial = seedInitial(
      expires:
          now +
          (incoming ? kInitialHtlcDuration : kCounterHtlcDuration).inSeconds,
    );
    final HtlcInfo own = HtlcInfo(
      id: Hash.parse(actionHash(101)),
      timeLocked: Address.parse(owner),
      hashLocked: Address.parse(counterparty),
      tokenStandard: token.tokenStandard,
      amount: BigInt.from(100),
      expirationTime:
          now +
          (incoming ? kCounterHtlcDuration : kInitialHtlcDuration).inSeconds,
      hashType: initial.hashType,
      keyMaxSize: initial.keyMaxSize,
      hashLock: List<int>.of(initial.hashLock),
    );
    seedDeposit(own, token: token, timestamp: now - 5);
    final HtlcSwap swap = HtlcSwap(
      id: incoming ? initial.id.toString() : own.id.toString(),
      chainId: chainId,
      type: P2pSwapType.native,
      direction: direction,
      selfAddress: owner,
      counterpartyAddress: counterparty,
      fromAmount: own.amount,
      fromTokenStandard: token.tokenStandard.toString(),
      fromSymbol: token.symbol,
      fromDecimals: token.decimals,
      fromChain: P2pSwapChain.nom,
      toChain: P2pSwapChain.nom,
      toAmount: initial.amount,
      toTokenStandard: receiving.tokenStandard.toString(),
      toDecimals: receiving.decimals,
      toSymbol: receiving.symbol,
      state: P2pSwapState.active,
      startTime: now - 20,
      initialHtlcId: incoming ? initial.id.toString() : own.id.toString(),
      initialHtlcExpirationTime: incoming
          ? initial.expirationTime
          : own.expirationTime,
      counterHtlcId: incoming ? own.id.toString() : initial.id.toString(),
      counterHtlcExpirationTime: incoming
          ? own.expirationTime
          : initial.expirationTime,
      hashLock: FormatUtils.encodeHexString(initial.hashLock),
      hashType: initial.hashType,
      preimage: FormatUtils.encodeHexString(
        List<int>.filled(htlcPreimageDefaultLength, 7),
      ),
    );
    history = <HtlcSwap>[HtlcSwap.fromJson(swap.toJson())];
    return swap;
  }
}

AccountBlock confirmedAction(
  AccountBlockTemplate template, {
  AccountBlock? paired,
  int timestamp = 1000,
  int confirmations = 1,
  Token? token,
  List<AccountBlock> descendants = const <AccountBlock>[],
}) => AccountBlock.fromJson(<String, dynamic>{
  ...template.toJson(),
  'descendantBlocks': descendants
      .map((AccountBlock value) => value.toJson())
      .toList(),
  'basePlasma': 0,
  'usedPlasma': 0,
  'changesHash': actionHash(10),
  'token': token?.toJson(),
  'pairedAccountBlock': paired?.toJson(),
  'confirmationDetail': <String, dynamic>{
    'numConfirmations': confirmations,
    'momentumHeight': 10,
    'momentumHash': actionHash(11),
    'momentumTimestamp': timestamp,
  },
});

HtlcInfo copyActionDeposit(
  HtlcInfo original, {
  Hash? id,
  Address? sender,
  Address? recipient,
  TokenStandard? standard,
  BigInt? amount,
  int? expires,
  int? hashType,
  int? keySize,
  List<int>? lock,
}) => HtlcInfo(
  id: id ?? original.id,
  timeLocked: sender ?? original.timeLocked,
  hashLocked: recipient ?? original.hashLocked,
  tokenStandard: standard ?? original.tokenStandard,
  amount: amount ?? original.amount,
  expirationTime: expires ?? original.expirationTime,
  hashType: hashType ?? original.hashType,
  keyMaxSize: keySize ?? original.keyMaxSize,
  hashLock: lock ?? List<int>.of(original.hashLock),
);

Future<void> microtasksUntil(bool Function() ready) async {
  for (int i = 0; i < 80 && !ready(); i++) {
    await Future<void>.value();
  }
  expect(
    ready(),
    isTrue,
    reason: 'The finite fixture reached its explicit boundary.',
  );
}
