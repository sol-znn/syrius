import 'dart:async';
import 'dart:math';

import 'package:collection/collection.dart';
import 'package:zenon_syrius_wallet_flutter/blocs/p2p_swap/htlc_swap/swap_action_origin.dart';
import 'package:zenon_syrius_wallet_flutter/model/block_data.dart';
import 'package:zenon_syrius_wallet_flutter/model/p2p_swap/htlc_swap.dart';
import 'package:zenon_syrius_wallet_flutter/model/p2p_swap/p2p_swap.dart';
import 'package:zenon_syrius_wallet_flutter/utils/account_block_utils.dart';
import 'package:zenon_syrius_wallet_flutter/utils/constants.dart';
import 'package:zenon_syrius_wallet_flutter/utils/format_utils.dart';
import 'package:zenon_syrius_wallet_flutter/utils/plasma_purpose.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

/// Publication acceptance and chain completion remain distinct facts.
enum SwapActionStatus {
  /// No publication was invoked and the original reservation settled safely.
  refused,

  /// Original sender accepted the block and required writes settled.
  submitted,

  /// Publication or persistence remains uncertain and its hold must survive.
  unknown,
}

/// One immutable original answer, retained independently of its view.
class SwapActionResult {
  /// Retains the exact original result, Futures and errors independently of UI.
  SwapActionResult({
    required this.status,
    this.block,
    this.swap,
    this.acceptedHash,
    this.publication,
    this.persistence,
    this.preparation,
    this.marker,
    this.error,
    this.stackTrace,
    this.reservationError,
  });

  /// Publication and persistence disposition; never a chain completion state.
  final SwapActionStatus status;

  /// Actual sender response, retained even when a later write fails.
  final AccountBlockTemplate? block;

  /// Exact response hash copied before any later asynchronous write.
  final String? acceptedHash;

  /// Recovery record constructed for the original accepted deposit or action.
  final HtlcSwap? swap;

  /// Identical original sender Future, absent before sender invocation.
  final Future<AccountBlockTemplate>? publication;

  /// Identical original recovery-record write Future, when admitted.
  final Future<void>? persistence;

  /// Original durable write-ahead preparation Future, including its failure.
  final Future<void>? preparation;

  /// Original accepted-hash marker write Future, when admitted.
  final Future<void>? marker;

  /// Unchanged action or backend failure; no raw diagnostic enters UI text.
  final Object? error;

  /// Original trace associated with [error].
  final StackTrace? stackTrace;

  /// Original reservation-settlement failure, separate from the action failure.
  final Object? reservationError;
}

class _SwapRun {
  final Completer<SwapActionResult> completion = Completer<SwapActionResult>();
  late final Future<SwapActionResult> future = completion.future;
  SwapActionResult? result;
}

typedef _ActionKey = (int, String, String, String);

typedef _PreparedPublisher =
    Future<String> Function(
      AccountBlockTemplate block,
      String purpose, {
      Map<String, dynamic>? recovery,
    });

/// Existing HTLC operations on exact original sources, with no automatic retry.
abstract final class SwapActions {
  static final Expando<Map<_ActionKey, _SwapRun>> _held =
      Expando<Map<_ActionKey, _SwapRun>>();
  static final Expando<List<SwapActionResult>> _outcomes =
      Expando<List<SwapActionResult>>();

  /// Returns retained outcomes for the exact original encrypted store identity.
  static List<SwapActionResult> outcomes(Object originalOwner) =>
      List<SwapActionResult>.unmodifiable(
        _outcomes[originalOwner] ?? <SwapActionResult>[],
      );

  static Future<SwapActionResult> _run(
    SwapActionOrigin origin,
    String action,
    String signer,
    String target,
    Future<HtlcSwap?> Function(_PreparedPublisher publish) operation, {
    bool persist = true,
  }) {
    final _ActionKey key = (origin.chainId, signer, action, target);
    final Map<_ActionKey, _SwapRun> held = _held[origin.identity] ??=
        <_ActionKey, _SwapRun>{};
    final _SwapRun? existing = held[key];
    if (existing != null) return existing.future;
    final _SwapRun run = _SwapRun();
    held[key] = run;
    unawaited(() async {
      SwapPersistenceReservation? reservation;
      SwapPublicationReservation? durable;
      Future<AccountBlockTemplate>? publication;
      Future<void>? persistence;
      Future<void>? preparation;
      Future<void>? marker;
      AccountBlockTemplate? accepted;
      String? acceptedHash;
      HtlcSwap? swap;
      bool invoked = false;
      SwapActionResult result;
      try {
        origin.requireCurrent();
        if (!origin.members.contains(signer)) {
          throw const SwapActionRefused('signer');
        }
        // Both are reserved before the first RPC. A later original result
        // must never resolve a new wallet, signer or encrypted backend.
        final SwapPublisher sender = origin.capturePublisher(signer);
        if (persist) reservation = origin.reserveStore();
        durable = origin.reservePublication(
          action,
          action == 'start' ? 'new' : target,
          signer,
        );
        swap = await operation((
          AccountBlockTemplate block,
          String purpose, {
          Map<String, dynamic>? recovery,
        }) async {
          origin.requireCurrent();
          preparation = durable!.prepare(recovery: recovery);
          await preparation;
          origin.requireCurrent();
          final Address recipient = block.toAddress;
          final BigInt amount = block.amount;
          final TokenStandard standard = block.tokenStandard;
          final List<int> data = List<int>.of(block.data);
          invoked = true;
          publication = sender(block, purpose);
          accepted = await publication!;
          final AccountBlockTemplate original = accepted!;
          acceptedHash = original.hash.toString();
          if (original.hash == emptyHash ||
              original.chainIdentifier != origin.chainId ||
              original.blockType != BlockTypeEnum.userSend.index ||
              original.address.toString() != signer ||
              original.toAddress != htlcAddress ||
              original.toAddress != recipient ||
              original.amount != amount ||
              original.tokenStandard != standard ||
              !const ListEquality<int>().equals(original.data, data)) {
            throw const SwapActionRefused('accepted-identity');
          }
          marker = durable!.accepted(acceptedHash!);
          await marker;
          return acceptedHash!;
        });
        if (!invoked || accepted == null) {
          throw const SwapActionRefused('not-published');
        }
        if (persist) {
          if (swap == null || reservation == null) {
            throw const SwapActionRefused('recovery-record');
          }
          persistence = reservation.store(swap);
          await persistence;
        }
        result = SwapActionResult(
          status: SwapActionStatus.submitted,
          block: accepted,
          acceptedHash: acceptedHash,
          swap: swap,
          publication: publication,
          persistence: persistence,
          preparation: preparation,
          marker: marker,
        );
      } on Object catch (error, trace) {
        Object? reservationError;
        bool unknown = invoked;
        try {
          if (invoked) {
            durable?.retainUnknown(error, trace);
          } else {
            // The original owner distinguishes a known pre-write refusal from
            // an uncertain preparation. Re-awaiting preparation here would
            // strand its separately reserved terminal receipt on failure.
            await durable?.refuseBeforePublication();
          }
        } on Object catch (secondary) {
          reservationError = secondary;
          unknown = true;
          try {
            durable?.retainUnknown(error, trace);
          } on Object {
            // Preserve the first original settlement failure in the result.
          }
        }
        try {
          if (persistence == null) {
            if (unknown) {
              reservation?.retainUnknown(error, trace);
            } else {
              reservation?.refuse();
            }
          }
        } on Object catch (secondary) {
          reservationError ??= secondary;
          unknown = true;
        }
        result = SwapActionResult(
          status: unknown ? SwapActionStatus.unknown : SwapActionStatus.refused,
          block: accepted,
          acceptedHash: acceptedHash,
          swap: swap,
          publication: publication,
          persistence: persistence,
          preparation: preparation,
          marker: marker,
          error: error,
          stackTrace: trace,
          reservationError: reservationError,
        );
      }
      run.result = result;
      (_outcomes[origin.identity] ??= <SwapActionResult>[]).add(result);
      // Only a known prepublication refusal can admit a later explicit click.
      if (result.status == SwapActionStatus.refused &&
          identical(held[key], run)) {
        held.remove(key);
      }
      run.completion.complete(result);
    }());
    return run.future;
  }

  /// A separate explicit New deposit request may release only an exact
  /// accepted and positively confirmed original. It never publishes itself.
  static Future<bool> releaseConfirmedStart(
    SwapActionOrigin origin,
    String signer,
  ) async {
    origin.requireCurrent();
    final _ActionKey key = (origin.chainId, signer, 'start', '');
    final Map<_ActionKey, _SwapRun>? held = _held[origin.identity];
    final _SwapRun? run = held?[key];
    final SwapActionResult? result = run?.result;
    final String? hash = result?.acceptedHash;
    if (run == null ||
        result?.status != SwapActionStatus.submitted ||
        hash == null) {
      return false;
    }
    final AccountBlock? loaded = await origin.readBlock(hash);
    origin.requireCurrent();
    final AccountBlock? block = loaded == null
        ? null
        : AccountBlock.fromJson(loaded.toJson());
    if (block == null ||
        block.hash.toString() != hash ||
        block.chainIdentifier != origin.chainId ||
        block.address.toString() != signer ||
        block.toAddress != htlcAddress ||
        block.blockType != BlockTypeEnum.userSend.index ||
        block.confirmationDetail == null ||
        block.confirmationDetail!.numConfirmations <= 0 ||
        block.confirmationDetail!.momentumTimestamp <= 0 ||
        !identical(held?[key], run)) {
      return false;
    }
    if (!await origin.rearmStart(signer, block)) return false;
    origin.requireCurrent();
    if (!identical(held?[key], run)) return false;
    held!.remove(key);
    return true;
  }

  static Token _copyToken(Token token) => Token.fromJson(token.toJson());
  static HtlcInfo _copyHtlc(HtlcInfo htlc) => HtlcInfo.fromJson(htlc.toJson());

  static bool _sameHtlc(HtlcInfo first, HtlcInfo second) =>
      first.id == second.id &&
      first.timeLocked == second.timeLocked &&
      first.hashLocked == second.hashLocked &&
      first.tokenStandard == second.tokenStandard &&
      first.amount == second.amount &&
      first.expirationTime == second.expirationTime &&
      first.hashType == second.hashType &&
      first.keyMaxSize == second.keyMaxSize &&
      const ListEquality<int>().equals(first.hashLock, second.hashLock);

  static bool _confirmedAt(AccountBlock block, int now) {
    final AccountBlockConfirmationDetail? confirmation =
        block.confirmationDetail;
    return now > 0 &&
        confirmation != null &&
        confirmation.numConfirmations > 0 &&
        confirmation.momentumTimestamp > 0 &&
        confirmation.momentumTimestamp <= now;
  }

  /// A live deposit is bound to its exact confirmed original Create call.
  static Future<AccountBlock> _confirmedCreation(
    SwapActionOrigin origin,
    HtlcInfo deposit,
    int now,
  ) async {
    if (now <= 0 ||
        deposit.id == emptyHash ||
        deposit.amount <= BigInt.zero ||
        deposit.expirationTime <= 0 ||
        deposit.keyMaxSize <= 0 ||
        deposit.keyMaxSize > htlcPreimageMaxLength ||
        deposit.hashLock.length != 32 ||
        (deposit.hashType != htlcHashTypeSha3 &&
            deposit.hashType != htlcHashTypeSha256)) {
      throw const SwapActionRefused('creation-proof');
    }
    final AccountBlock? loaded = await origin.readBlock(deposit.id.toString());
    origin.requireCurrent();
    final AccountBlock? block = loaded == null
        ? null
        : AccountBlock.fromJson(loaded.toJson());
    final BlockData? data = block == null
        ? null
        : AccountBlockUtils.getDecodedBlockData(Definitions.htlc, block.data);
    if (block == null ||
        block.hash != deposit.id ||
        block.chainIdentifier != origin.chainId ||
        block.blockType != BlockTypeEnum.userSend.index ||
        block.toAddress != htlcAddress ||
        block.address != deposit.timeLocked ||
        block.amount != deposit.amount ||
        block.tokenStandard != deposit.tokenStandard ||
        !_confirmedAt(block, now) ||
        data?.function != 'Create' ||
        data!.params['hashLocked'] != deposit.hashLocked ||
        data.params['expirationTime'].toString() !=
            deposit.expirationTime.toString() ||
        data.params['hashType'].toString() != deposit.hashType.toString() ||
        data.params['keyMaxSize'].toString() != deposit.keyMaxSize.toString() ||
        data.params['hashLock'] is! List<int> ||
        !const ListEquality<int>().equals(
          data.params['hashLock'] as List<int>,
          deposit.hashLock,
        )) {
      throw const SwapActionRefused('creation-proof');
    }
    return block;
  }

  static Future<Token> _fundedToken(
    SwapActionOrigin origin,
    String signer,
    Token requested,
    BigInt amount,
  ) async {
    if (amount <= BigInt.zero ||
        requested.decimals < 0 ||
        requested.decimals > 255) {
      throw const SwapActionRefused('amount');
    }
    origin.requireCurrent();
    final Token? loaded = await origin.readToken(
      requested.tokenStandard.toString(),
    );
    origin.requireCurrent();
    if (loaded == null ||
        loaded.tokenStandard != requested.tokenStandard ||
        loaded.decimals != requested.decimals ||
        loaded.symbol != requested.symbol) {
      throw const SwapActionRefused('token');
    }
    final Token token = _copyToken(loaded);
    final AccountInfo account = await origin.readAccount(signer);
    origin.requireCurrent();
    final List<BalanceInfoListItem>? balances = account.balanceInfoList;
    if (account.address != signer ||
        account.blockCount == null ||
        account.blockCount! < 0 ||
        balances == null ||
        balances.any(
          (BalanceInfoListItem item) =>
              item.token == null ||
              item.balance == null ||
              item.balance! < BigInt.zero,
        ) ||
        balances
                .map(
                  (BalanceInfoListItem item) =>
                      item.token!.tokenStandard.toString(),
                )
                .toSet()
                .length !=
            balances.length ||
        account.getBalance(token.tokenStandard) < amount) {
      throw const SwapActionRefused('balance');
    }
    return token;
  }

  /// A live exact deposit and its positive original creation proof.
  static Future<HtlcInfo> initial(SwapActionOrigin origin, Hash id) async {
    origin.requireCurrent();
    if (id == emptyHash) throw const SwapActionRefused('deposit-id');
    final HtlcInfo htlc = _copyHtlc(await origin.readHtlc(id.toString()));
    origin.requireCurrent();
    final String hash = FormatUtils.encodeHexString(htlc.hashLock);
    if (htlc.id != id ||
        !origin.members.contains(htlc.hashLocked.toString()) ||
        origin.members.contains(htlc.timeLocked.toString()) ||
        htlc.amount <= BigInt.zero ||
        htlc.hashLock.length != 32 ||
        htlc.keyMaxSize < htlcPreimageDefaultLength ||
        (htlc.hashType != htlcHashTypeSha3 &&
            htlc.hashType != htlcHashTypeSha256)) {
      throw const SwapActionRefused('deposit');
    }
    final List<HtlcSwap> history = origin.readHistory();
    if (history.any(
      (HtlcSwap item) =>
          item.chainId != origin.chainId ||
          item.initialHtlcId == id.toString() ||
          item.counterHtlcId == id.toString() ||
          item.hashLock == hash,
    )) {
      throw const SwapActionRefused('deposit-used');
    }
    final int now = await origin.readChainTime();
    origin.requireCurrent();
    final int remaining = htlc.expirationTime - now;
    if (now <= 0 ||
        remaining <
            (kMinSafeTimeToFindPreimage + kCounterHtlcDuration).inSeconds ||
        remaining > kMaxAllowedInitialHtlcDuration.inSeconds) {
      throw const SwapActionRefused('deposit-time');
    }
    final AccountBlock created = await _confirmedCreation(origin, htlc, now);
    if (htlc.expirationTime - created.confirmationDetail!.momentumTimestamp >
        kMaxAllowedInitialHtlcDuration.inSeconds) {
      throw const SwapActionRefused('creation-proof');
    }
    final List<AccountBlock> blocks = await origin.readContractBlocks(
      max(0, htlc.expirationTime - kMaxAllowedInitialHtlcDuration.inSeconds),
    );
    origin.requireCurrent();
    final int historyTime = await origin.readChainTime();
    origin.requireCurrent();
    if (historyTime < now ||
        htlc.expirationTime - historyTime <
            (kMinSafeTimeToFindPreimage + kCounterHtlcDuration).inSeconds ||
        htlc.expirationTime - historyTime >
            kMaxAllowedInitialHtlcDuration.inSeconds) {
      throw const SwapActionRefused('deposit-time');
    }
    bool foundOriginal = false;
    for (final AccountBlock block in blocks) {
      if (block.chainIdentifier != origin.chainId ||
          block.address != htlcAddress ||
          block.hash == emptyHash ||
          !_confirmedAt(block, historyTime)) {
        throw const SwapActionRefused('contract-history');
      }
      if (block.blockType != BlockTypeEnum.contractReceive.index) continue;
      final AccountBlock? paired = block.pairedAccountBlock;
      if (paired == null ||
          paired.chainIdentifier != origin.chainId ||
          block.fromBlockHash != paired.hash) {
        throw const SwapActionRefused('paired-block');
      }
      final BlockData? call = AccountBlockUtils.getDecodedBlockData(
        Definitions.htlc,
        paired.data,
      );
      if (call?.function != 'Create' ||
          call!.params['hashLock'] is! List<int>) {
        continue;
      }
      if (const ListEquality<int>().equals(
        call.params['hashLock'] as List<int>,
        htlc.hashLock,
      )) {
        if (paired.hash != id) throw const SwapActionRefused('hash-used');
        if (paired.toAddress != htlcAddress ||
            paired.blockType != BlockTypeEnum.userSend.index ||
            paired.address != created.address ||
            paired.amount != created.amount ||
            paired.tokenStandard != created.tokenStandard ||
            !const ListEquality<int>().equals(paired.data, created.data)) {
          throw const SwapActionRefused('paired-creation-mismatch');
        }
        foundOriginal = true;
      }
    }
    if (!foundOriginal) throw const SwapActionRefused('creation-unconfirmed');
    return htlc;
  }

  /// Creates one funded initial deposit after its private recovery material is
  /// durable. Repeated clicks share the original Future until known refusal.
  static Future<SwapActionResult> start(
    SwapActionOrigin origin, {
    required String selfAddress,
    required String counterparty,
    required Token fromToken,
    required BigInt amount,
    required int hashType,
    List<int> Function()? preimageSource,
  }) {
    final Token requested = _copyToken(fromToken);
    return _run(origin, 'start', selfAddress, '', (
      _PreparedPublisher publish,
    ) async {
      if (origin.members.contains(counterparty) ||
          Address.parse(counterparty).toString() != counterparty ||
          (hashType != htlcHashTypeSha3 && hashType != htlcHashTypeSha256)) {
        throw const SwapActionRefused('counterparty');
      }
      final Token token = await _fundedToken(
        origin,
        selfAddress,
        requested,
        amount,
      );
      final int now = await origin.readChainTime();
      origin.requireCurrent();
      if (now <= 0) throw const SwapActionRefused('chain-time');
      final List<int> preimage = List<int>.of(
        preimageSource?.call() ??
            List<int>.generate(
              htlcPreimageDefaultLength,
              (_) => Random.secure().nextInt(256),
            ),
      );
      if (preimage.length != htlcPreimageDefaultLength ||
          preimage.any((int byte) => byte < 0 || byte > 255)) {
        throw const SwapActionRefused('preimage');
      }
      final Hash hash = hashType == htlcHashTypeSha3
          ? Hash.digest(preimage)
          : Hash.fromBytes(await Crypto.sha256Bytes(preimage));
      origin.requireCurrent();
      final int expiry = now + kInitialHtlcDuration.inSeconds;
      final AccountBlockTemplate block = origin.create(
        token,
        amount,
        Address.parse(counterparty),
        expiry,
        hashType,
        htlcPreimageMaxLength,
        hash.getBytes()!,
      );
      final String accepted = await publish(
        block,
        PlasmaPurpose.startSwap.message,
        recovery: <String, dynamic>{
          'chainId': origin.chainId,
          'selfAddress': selfAddress,
          'recipient': counterparty,
          'amount': amount.toString(),
          'tokenStandard': token.tokenStandard.toString(),
          'fromDecimals': token.decimals,
          'fromSymbol': token.symbol,
          'startTime': now,
          'expirationTime': expiry,
          'hashLock': hash.toString(),
          'hashType': hashType,
          'keyMaxSize': htlcPreimageMaxLength,
          'preimage': FormatUtils.encodeHexString(preimage),
        },
      );
      return HtlcSwap(
        id: accepted,
        chainId: origin.chainId,
        type: P2pSwapType.native,
        direction: P2pSwapDirection.outgoing,
        selfAddress: selfAddress,
        counterpartyAddress: counterparty,
        state: P2pSwapState.pending,
        startTime: now,
        initialHtlcId: accepted,
        initialHtlcExpirationTime: expiry,
        fromAmount: amount,
        fromTokenStandard: token.tokenStandard.toString(),
        fromDecimals: token.decimals,
        fromSymbol: token.symbol,
        fromChain: P2pSwapChain.nom,
        toChain: P2pSwapChain.nom,
        hashLock: hash.toString(),
        preimage: FormatUtils.encodeHexString(preimage),
        hashType: hashType,
      );
    });
  }

  /// Reproves the exact drawn initial deposit and creates one funded native
  /// counterdeposit on the original wallet, chain and encrypted store.
  static Future<SwapActionResult> join(
    SwapActionOrigin origin, {
    required HtlcInfo initialDeposit,
    required Token fromToken,
    required Token toToken,
    required BigInt amount,
  }) {
    final HtlcInfo drawn = _copyHtlc(initialDeposit);
    final Token requested = _copyToken(fromToken);
    final Token receiving = _copyToken(toToken);
    return _run(
      origin,
      'join',
      drawn.hashLocked.toString(),
      drawn.id.toString(),
      (_PreparedPublisher publish) async {
        final HtlcInfo fresh = await initial(origin, drawn.id);
        if (!_sameHtlc(drawn, fresh) ||
            receiving.tokenStandard != fresh.tokenStandard) {
          throw const SwapActionRefused('deposit-changed');
        }
        final Token? receiveMetadata = await origin.readToken(
          fresh.tokenStandard.toString(),
        );
        origin.requireCurrent();
        if (receiveMetadata == null ||
            receiveMetadata.decimals != receiving.decimals ||
            receiveMetadata.tokenStandard != receiving.tokenStandard ||
            receiveMetadata.symbol != receiving.symbol) {
          throw const SwapActionRefused('receive-token');
        }
        final Token sending = await _fundedToken(
          origin,
          fresh.hashLocked.toString(),
          requested,
          amount,
        );
        final int now = await origin.readChainTime();
        origin.requireCurrent();
        if (now <= 0 ||
            fresh.expirationTime - now <
                (kMinSafeTimeToFindPreimage + kCounterHtlcDuration).inSeconds) {
          throw const SwapActionRefused('deposit-time');
        }
        final int expiry = now + kCounterHtlcDuration.inSeconds;
        final String accepted = await publish(
          origin.create(
            sending,
            amount,
            fresh.timeLocked,
            expiry,
            fresh.hashType,
            fresh.keyMaxSize,
            fresh.hashLock,
          ),
          PlasmaPurpose.joinSwap.message,
        );
        return HtlcSwap(
          id: fresh.id.toString(),
          chainId: origin.chainId,
          type: P2pSwapType.native,
          direction: P2pSwapDirection.incoming,
          selfAddress: fresh.hashLocked.toString(),
          counterpartyAddress: fresh.timeLocked.toString(),
          state: P2pSwapState.active,
          startTime: now,
          initialHtlcId: fresh.id.toString(),
          initialHtlcExpirationTime: fresh.expirationTime,
          counterHtlcId: accepted,
          counterHtlcExpirationTime: expiry,
          fromAmount: amount,
          fromTokenStandard: sending.tokenStandard.toString(),
          fromDecimals: sending.decimals,
          fromSymbol: sending.symbol,
          fromChain: P2pSwapChain.nom,
          toChain: P2pSwapChain.nom,
          toAmount: fresh.amount,
          toTokenStandard: receiving.tokenStandard.toString(),
          toDecimals: receiving.decimals,
          toSymbol: receiving.symbol,
          hashLock: FormatUtils.encodeHexString(fresh.hashLock),
          hashType: fresh.hashType,
        );
      },
    );
  }

  /// Verifies the original receiving deposit and preimage before one Unlock;
  /// only a later confirmed contract effect can mark the swap completed.
  static Future<SwapActionResult> complete(
    SwapActionOrigin origin,
    HtlcSwap original,
  ) {
    final HtlcSwap swap = HtlcSwap.fromJson(original.toJson());
    final String? id = swap.direction == P2pSwapDirection.outgoing
        ? swap.counterHtlcId
        : swap.initialHtlcId;
    return _run(origin, 'complete', swap.selfAddress, id ?? '', (
      _PreparedPublisher publish,
    ) async {
      if (id == null ||
          swap.chainId != origin.chainId ||
          swap.preimage == null) {
        throw const SwapActionRefused('recovery');
      }
      final HtlcInfo deposit = _copyHtlc(await origin.readHtlc(id));
      origin.requireCurrent();
      final int now = await origin.readChainTime();
      origin.requireCurrent();
      if (now <= 0) throw const SwapActionRefused('chain-time');
      await _confirmedCreation(origin, deposit, now);
      final List<int> preimage = FormatUtils.decodeHexString(swap.preimage!);
      final Hash proof = deposit.hashType == htlcHashTypeSha3
          ? Hash.digest(preimage)
          : deposit.hashType == htlcHashTypeSha256
          ? Hash.fromBytes(await Crypto.sha256Bytes(preimage))
          : throw const SwapActionRefused('hash-type');
      origin.requireCurrent();
      if (deposit.id.toString() != id ||
          deposit.hashLocked.toString() != swap.selfAddress ||
          deposit.timeLocked.toString() != swap.counterpartyAddress ||
          deposit.amount <= BigInt.zero ||
          deposit.amount != swap.toAmount ||
          deposit.tokenStandard.toString() != swap.toTokenStandard ||
          deposit.hashType != swap.hashType ||
          deposit.expirationTime !=
              (swap.direction == P2pSwapDirection.outgoing
                  ? swap.counterHtlcExpirationTime
                  : swap.initialHtlcExpirationTime) ||
          deposit.expirationTime <=
              now + kMinSafeTimeToCompleteSwap.inSeconds ||
          preimage.length > deposit.keyMaxSize ||
          proof.toString() != swap.hashLock ||
          !const ListEquality<int>().equals(
            proof.getBytes(),
            deposit.hashLock,
          )) {
        throw const SwapActionRefused('unlock-proof');
      }
      final int publicationTime = await origin.readChainTime();
      origin.requireCurrent();
      if (publicationTime < now ||
          deposit.expirationTime <=
              publicationTime + kMinSafeTimeToCompleteSwap.inSeconds) {
        throw const SwapActionRefused('unlock-time');
      }
      await publish(
        origin.unlock(deposit.id, preimage),
        PlasmaPurpose.completeSwap.message,
      );
      // An accepted send is not a contract receive or a completed swap.
      return swap;
    });
  }

  /// Reclaims an exactly owned, proven expired deposit, retaining its original
  /// accepted hash or uncertainty rather than retrying.
  static Future<SwapActionResult> reclaim(
    SwapActionOrigin origin,
    Hash id,
    String signer,
  ) => _run(origin, 'reclaim', signer, id.toString(), (
    _PreparedPublisher publish,
  ) async {
    final HtlcInfo deposit = _copyHtlc(await origin.readHtlc(id.toString()));
    origin.requireCurrent();
    final int now = await origin.readChainTime();
    origin.requireCurrent();
    if (now <= 0 ||
        deposit.id != id ||
        deposit.timeLocked.toString() != signer ||
        deposit.expirationTime > now) {
      throw const SwapActionRefused('reclaim-proof');
    }
    await _confirmedCreation(origin, deposit, now);
    await publish(origin.reclaim(id), PlasmaPurpose.reclaimSwapFunds.message);
    return null;
  }, persist: false);
}
