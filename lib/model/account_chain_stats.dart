import 'package:znn_sdk_dart/znn_sdk_dart.dart';

/// The selected account's ledger counts and the source of its first block.
class AccountChainStats {
  /// Creates statistics; legacy records can omit the unknown source chain.
  AccountChainStats({
    required this.firstHash,
    required this.blockCount,
    required this.blockTypeNumOfBlocksMap,
    this.chainIdentifier,
  });

  /// The exact first block in the account chain.
  final Hash firstHash;

  /// The number of account blocks reported by the node.
  final int blockCount;

  /// The observed count for each block type.
  final Map<BlockTypeEnum, int> blockTypeNumOfBlocksMap;

  /// The first block's chain, absent until a source block establishes it.
  final int? chainIdentifier;
}
