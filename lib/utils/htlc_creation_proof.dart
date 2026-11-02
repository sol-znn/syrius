import 'package:zenon_syrius_wallet_flutter/model/block_data.dart';
import 'package:zenon_syrius_wallet_flutter/model/p2p_swap/htlc_swap.dart';
import 'package:zenon_syrius_wallet_flutter/model/p2p_swap/p2p_swap.dart';
import 'package:zenon_syrius_wallet_flutter/utils/account_block_utils.dart';
import 'package:zenon_syrius_wallet_flutter/utils/format_utils.dart';
import 'package:zenon_syrius_wallet_flutter/utils/htlc_owned_work.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

/// Accepts exact ABI integers within the lossless application integer bound.
int? htlcProofInteger(dynamic value) => value is int
    ? value
    : value is BigInt &&
          value >= BigInt.zero &&
          value <= BigInt.from(0x1fffffffffffff)
    ? value.toInt()
    : null;

/// Immutable confirmed Create facts supply proof for persisted history.
bool htlcCreationMatches(
  HtlcSwap swap,
  AccountBlock? block, {
  required bool initial,
}) {
  if (block == null ||
      block.hash.toString() !=
          (initial ? swap.initialHtlcId : swap.counterHtlcId) ||
      block.chainIdentifier != swap.chainId ||
      block.toAddress != htlcAddress ||
      block.blockType != BlockTypeEnum.userSend.index ||
      block.confirmationDetail == null ||
      block.confirmationDetail!.numConfirmations <= 0 ||
      block.confirmationDetail!.momentumTimestamp <= 0 ||
      block.token == null ||
      block.token!.tokenStandard != block.tokenStandard) {
    return false;
  }
  final BlockData? data = AccountBlockUtils.getDecodedBlockData(
    Definitions.htlc,
    block.data,
  );
  if (data == null ||
      data.function != 'Create' ||
      data.params['hashLock'] is! List<int>) {
    return false;
  }
  final bool sending = initial == (swap.direction == P2pSwapDirection.outgoing);
  final BigInt? amount = sending ? swap.fromAmount : swap.toAmount;
  final String? standard = sending
      ? swap.fromTokenStandard
      : swap.toTokenStandard;
  final int? keySize = htlcProofInteger(data.params['keyMaxSize']);
  return block.address.toString() ==
          (sending ? swap.selfAddress : swap.counterpartyAddress) &&
      data.params['hashLocked'].toString() ==
          (sending ? swap.counterpartyAddress : swap.selfAddress) &&
      amount != null &&
      amount > BigInt.zero &&
      block.amount == amount &&
      standard != null &&
      block.tokenStandard.toString() == standard &&
      FormatUtils.encodeHexString(data.params['hashLock'] as List<int>) ==
          swap.hashLock &&
      htlcProofInteger(data.params['hashType']) == swap.hashType &&
      htlcProofInteger(data.params['expirationTime']) ==
          (initial
              ? swap.initialHtlcExpirationTime
              : swap.counterHtlcExpirationTime) &&
      keySize != null &&
      keySize > 0 &&
      keySize <= htlcPreimageMaxLength;
}

/// Uses the existing SDK digests; no cryptographic implementation is added.
Future<bool> htlcPreimageMatches(
  int type,
  String expected,
  List<int> value,
) async {
  if (value.isEmpty) return false;
  if (type == htlcHashTypeSha3) {
    return Hash.digest(value).toString() == expected;
  }
  if (type == htlcHashTypeSha256) {
    return Hash.fromBytes(await Crypto.sha256Bytes(value)).toString() ==
        expected;
  }
  throw const HtlcOwnershipRefused('hash-type-unproven');
}
