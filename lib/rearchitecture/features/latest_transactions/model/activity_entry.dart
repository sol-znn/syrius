import 'package:zenon_syrius_wallet_flutter/utils/zts_utils.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

/// The movement established by one account block, without invented receipts.
enum ActivityKind {
  /// An ordinary incoming transfer.
  received,

  /// An ordinary outgoing transfer.
  sent,

  /// A canonical delegation call to the Pillar contract.
  delegated,

  /// A canonical fuse call carrying QSR to the Plasma contract.
  fused,

  /// A canonical stake call carrying ZNN to the Stake contract.
  staked,

  /// An incoming reward explicitly identified by its contract payload.
  reward,

  /// Explicit isolated preview metadata, never inferred from live bytes.
  zap,

  /// An account-block type whose movement is not established.
  other,
}

/// Explicit Zap presentation for an existing block in an isolated preview.
///
/// This does not decode messages, create rows or implement Zap receipt. The
/// message control remains behind `Seam.zapReceive` even in that preview.
class ActivityZapPreview {
  /// Marks the preview's message-bearing block, or its companion transfer.
  const ActivityZapPreview({this.hasMessage = true});

  /// Whether this preview block has the drawn Message control.
  final bool hasMessage;
}

/// Pure presentation data retaining the original history block's identity.
class ActivityEntry {
  const ActivityEntry._({
    required this.hash,
    required this.owner,
    required this.kind,
    required this.incoming,
    required this.amount,
    required this.decimals,
    required this.symbol,
    required this.counterparty,
    required this.timestamp,
    required this.hasMessage,
    this.name,
    this.fuseBeneficiary,
    this.stakeMonths,
  });

  /// Interprets only the supplied block. No service or global session is read.
  factory ActivityEntry.fromBlock(
    AccountBlock block, {
    ActivityZapPreview? zapPreview,
  }) {
    final bool incoming = BlockUtils.isReceiveBlock(block.blockType);
    final bool outgoing = BlockUtils.isSendBlock(block.blockType);
    final AccountBlock? pair = block.pairedAccountBlock;
    // A receive's own amount is not the incoming send's amount. A missing or
    // unrelated pair must not become an apparently exact zero transfer.
    final bool validPair =
        incoming &&
        pair != null &&
        BlockUtils.isSendBlock(pair.blockType) &&
        pair.chainIdentifier == block.chainIdentifier &&
        pair.hash == block.fromBlockHash &&
        pair.toAddress == block.address;
    final AccountBlock? movement = incoming
        ? (validPair ? pair : null)
        : (outgoing ? block : null);
    final (int, String)? units = movement == null ? null : _units(movement);
    ActivityKind kind = incoming
        ? ActivityKind.received
        : outgoing
        ? ActivityKind.sent
        : ActivityKind.other;
    String? name;
    Address? beneficiary;
    int? months;

    if (movement != null && outgoing) {
      final List<dynamic>? delegate =
          movement.toAddress == pillarAddress &&
              movement.tokenStandard == kZnnCoin.tokenStandard &&
              movement.amount == BigInt.zero
          ? _decode(Definitions.pillar, 'Delegate', movement.data)
          : null;
      final List<dynamic>? fuse =
          movement.toAddress == plasmaAddress &&
              movement.tokenStandard == kQsrCoin.tokenStandard &&
              movement.amount > BigInt.zero
          ? _decode(Definitions.plasma, 'Fuse', movement.data)
          : null;
      final List<dynamic>? stake =
          movement.toAddress == stakeAddress &&
              movement.tokenStandard == kZnnCoin.tokenStandard &&
              movement.amount > BigInt.zero
          ? _decode(Definitions.stake, 'Stake', movement.data)
          : null;
      if (delegate case <dynamic>[
        final String pillarName,
      ] when pillarName.trim().isNotEmpty) {
        kind = ActivityKind.delegated;
        name = pillarName;
      } else if (fuse case <dynamic>[final Address address]) {
        kind = ActivityKind.fused;
        beneficiary = address;
      } else if (stake case <dynamic>[final Object value]) {
        final BigInt? duration = switch (value) {
          final BigInt value => value,
          final int value => BigInt.from(value),
          _ => null,
        };
        if (duration != null && duration > BigInt.zero) {
          kind = ActivityKind.staked;
          final BigInt unit = BigInt.from(stakeTimeUnitSec);
          if (duration % unit == BigInt.zero &&
              duration ~/ unit <= BigInt.from(12)) {
            months = (duration ~/ unit).toInt();
          }
        }
      }
    } else if (movement != null && incoming) {
      final bool rewardContract =
          movement.blockType == BlockTypeEnum.contractSend.index &&
          (movement.address == pillarAddress ||
              movement.address == stakeAddress ||
              movement.address == sentinelAddress);
      // Refunds share these senders. The sender alone cannot establish
      // a reward.
      if (rewardContract &&
          _decode(Definitions.common, 'CollectReward', movement.data) != null) {
        kind = ActivityKind.reward;
      }
    }
    final bool previewable =
        kind == ActivityKind.sent || kind == ActivityKind.received;
    if (zapPreview != null && previewable) kind = ActivityKind.zap;
    return ActivityEntry._(
      hash: block.hash.toString(),
      owner: block.address.toString(),
      kind: kind,
      incoming: incoming,
      amount:
          movement != null && movement.amount >= BigInt.zero && units != null
          ? movement.amount
          : null,
      decimals: units?.$1,
      symbol: units?.$2,
      counterparty: incoming ? movement?.address : movement?.toAddress,
      timestamp: block.confirmationDetail?.momentumTimestamp,
      hasMessage: kind == ActivityKind.zap && (zapPreview?.hasMessage ?? false),
      name: name,
      fuseBeneficiary: beneficiary,
      stakeMonths: months,
    );
  }

  /// The history row's hash, including the receive hash for incoming rows.
  final String hash;

  /// The account whose history supplied this row.
  final String owner;

  /// The action supported by the supplied data.
  final ActivityKind kind;

  /// Whether this is a receive block, including one missing its send pair.
  final bool incoming;

  /// Exact smallest units, absent when movement or units are not established.
  final BigInt? amount;

  /// Verified token precision, absent when unavailable.
  final int? decimals;

  /// The token symbol corresponding to [decimals].
  final String? symbol;

  /// Sender for an incoming row and recipient for an outgoing row.
  final Address? counterparty;

  /// The row's confirmation time, never the paired send's earlier time.
  final int? timestamp;

  /// A preview's drawn, seamed Message control.
  final bool hasMessage;

  /// A delegated Pillar's name from the canonical ABI argument.
  final String? name;

  /// The beneficiary decoded from a fuse call.
  final Address? fuseBeneficiary;

  /// A stake's whole-month term when the ABI argument establishes one.
  final int? stakeMonths;

  static (int, String)? _units(AccountBlock block) {
    // Native precision is fixed by the protocol, rather than by RPC metadata.
    for (final Token native in <Token>[kZnnCoin, kQsrCoin]) {
      if (native.tokenStandard == block.tokenStandard) {
        return (native.decimals, native.symbol);
      }
    }
    final Token? token = block.token;
    if (token != null &&
        token.tokenStandard == block.tokenStandard &&
        token.decimals >= 0 &&
        token.decimals <= 255 &&
        token.symbol.trim().isNotEmpty) {
      return (token.decimals, token.symbol);
    }
    return null;
  }

  static List<dynamic>? _decode(Abi abi, String method, List<int> bytes) {
    if (bytes.length < AbiFunction.encodedSignLength ||
        bytes.any((int byte) => byte < 0 || byte > 255)) {
      return null;
    }
    try {
      for (final Entry entry in abi.entries) {
        if (entry.name != method) continue;
        final List<int> signature = AbiFunction.extractSignature(
          entry.encodeSignature(),
        );
        if (!_same(signature, AbiFunction.extractSignature(bytes))) continue;
        final List<dynamic> values = AbiFunction(
          entry.name!,
          entry.inputs!,
        ).decode(bytes);
        // Round-trip equality refuses trailing bytes and partial or ambiguous
        // encodings instead of attaching a confident operation label to them.
        return _same(abi.encodeFunction(method, values), bytes) ? values : null;
      }
    } on Object {
      return null;
    }
    return null;
  }

  static bool _same(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (int index = 0; index < a.length; index++) {
      if (a[index] != b[index]) return false;
    }
    return true;
  }
}
