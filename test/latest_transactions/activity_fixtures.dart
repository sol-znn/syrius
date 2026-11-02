import 'dart:convert';

import 'package:zenon_syrius_wallet_flutter/utils/zts_utils.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

/// An isolated ledger block with explicit identity and optional send pairing.
AccountBlock activityBlock({
  BlockTypeEnum type = BlockTypeEnum.userSend,
  String? hash,
  Address? address,
  Address? to,
  BigInt? amount,
  Token? token,
  TokenStandard? standard,
  bool missingToken = false,
  int? timestamp = 1800000000,
  int chainId = 1,
  AccountBlock? paired,
  Hash? fromHash,
  List<int> data = const <int>[],
}) => AccountBlock.fromJson(<String, dynamic>{
  'version': 1,
  'chainIdentifier': chainId,
  'blockType': type.index,
  'hash': hash ?? ''.padLeft(64, 'a'),
  'previousHash': emptyHash.toString(),
  'height': 2,
  'momentumAcknowledged': <String, dynamic>{
    'hash': emptyHash.toString(),
    'height': 1,
  },
  'address': (address ?? emptyAddress).toString(),
  'toAddress': (to ?? pillarAddress).toString(),
  'amount': (amount ?? BigInt.from(1250000000)).toString(),
  'tokenStandard': (standard ?? token?.tokenStandard ?? kZnnCoin.tokenStandard)
      .toString(),
  'fromBlockHash': (fromHash ?? paired?.hash ?? emptyHash).toString(),
  'data': base64.encode(data),
  'fusedPlasma': 0,
  'difficulty': 0,
  'nonce': '',
  'publicKey': null,
  'signature': null,
  'token': missingToken ? null : (token ?? kZnnCoin).toJson(),
  'pairedAccountBlock': paired?.toJson(),
  'descendantBlocks': const <dynamic>[],
  'basePlasma': 21000,
  'usedPlasma': 21000,
  'changesHash': emptyHash.toString(),
  'confirmationDetail': timestamp == null
      ? null
      : <String, dynamic>{
          'numConfirmations': 2,
          'momentumHeight': 100,
          'momentumHash': emptyHash.toString(),
          'momentumTimestamp': timestamp,
        },
});

/// A receive whose pair and exact originating hash agree.
AccountBlock activityReceive({
  AccountBlock? send,
  int? timestamp = 1800000000,
}) {
  final AccountBlock paired = send ?? activityBlock(to: emptyAddress);
  return activityBlock(
    type: BlockTypeEnum.userReceive,
    hash: ''.padLeft(64, 'b'),
    address: paired.toAddress,
    amount: BigInt.zero,
    paired: paired,
    timestamp: timestamp,
  );
}
