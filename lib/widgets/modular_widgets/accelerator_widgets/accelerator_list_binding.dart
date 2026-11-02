import 'package:zenon_syrius_wallet_flutter/utils/global.dart';
import 'package:zenon_syrius_wallet_flutter/utils/wallet_action_context.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

/// One original Accelerator read source, captured before its first await.
/// Test bindings supply finite in-memory reads and never open a wallet.
final class AcceleratorListBinding {
  /// Freezes read capabilities and wallet membership for one original source.
  AcceleratorListBinding({
    required this.ownerAddress,
    required Set<String> walletAddresses,
    required this._stillCurrent,
    required this.readProjects,
    required this.readPillars,
    required this.readFund,
    required this.readVotes,
    required this.readProject,
  }) : walletAddresses = Set<String>.unmodifiable(walletAddresses);

  /// Original selected account used for exact Pillar-owner lookup.
  final String ownerAddress;

  /// Original wallet membership used by the Mine filter.
  final Set<String> walletAddresses;
  final bool Function() _stillCurrent;

  /// Reads one page through the originally bound Accelerator API.
  final Future<ProjectList> Function(int page, int size) readProjects;

  /// Reads Pillars owned by [ownerAddress] through the original source.
  final Future<List<PillarInfo>> Function() readPillars;

  /// Reads the Accelerator account's exact native fund balances.
  final Future<AccountInfo> Function() readFund;

  /// Reads one positional vote entry per exact original target hash.
  final Future<List<PillarVote?>> Function(String name, List<String> ids)
  readVotes;

  /// Reads an exact project without adopting a later global API.
  final Future<Project> Function(String id) readProject;

  /// Ephemeral identity binding painted rows to this source generation.
  final Object authority = Object();
  bool _revoked = false;

  /// Captures each mutable SDK API, its transport, and the original URL.
  static AcceleratorListBinding? capture() {
    final String? owner = kSelectedAddress;
    if (owner == null) return null;
    final WalletActionContext? scope = WalletActionContext.capture(owner);
    if (scope == null) return null;
    final Zenon sdk = scope.client;
    final AcceleratorApi acceleratorSource = sdk.embedded.accelerator;
    final PillarApi pillarSource = sdk.embedded.pillar;
    final LedgerApi ledgerSource = sdk.ledger;
    final Client acceleratorClient = acceleratorSource.client;
    final Client pillarClient = pillarSource.client;
    final Client ledgerClient = ledgerSource.client;
    final String? acceleratorUrl = acceleratorClient is WsClient
        ? acceleratorClient.url
        : null;
    final String? pillarUrl = pillarClient is WsClient
        ? pillarClient.url
        : null;
    final String? ledgerUrl = ledgerClient is WsClient
        ? ledgerClient.url
        : null;
    final AcceleratorApi accelerator = AcceleratorApi()
      ..setClient(acceleratorClient);
    final PillarApi pillar = PillarApi()..setClient(pillarClient);
    final LedgerApi ledger = LedgerApi()..setClient(ledgerClient);
    return AcceleratorListBinding(
      ownerAddress: owner,
      walletAddresses: kDefaultAddressList.whereType<String>().toSet(),
      stillCurrent: () =>
          scope.isCurrent &&
          identical(acceleratorSource, sdk.embedded.accelerator) &&
          identical(pillarSource, sdk.embedded.pillar) &&
          identical(ledgerSource, sdk.ledger) &&
          identical(acceleratorClient, acceleratorSource.client) &&
          identical(pillarClient, pillarSource.client) &&
          identical(ledgerClient, ledgerSource.client) &&
          (acceleratorClient is! WsClient ||
              acceleratorClient.url == acceleratorUrl) &&
          (pillarClient is! WsClient || pillarClient.url == pillarUrl) &&
          (ledgerClient is! WsClient || ledgerClient.url == ledgerUrl),
      readProjects: (int page, int size) =>
          accelerator.getAll(pageIndex: page, pageSize: size),
      readPillars: () => pillar.getByOwner(Address.parse(owner)),
      readFund: () => ledger.getAccountInfoByAddress(acceleratorAddress),
      readVotes: accelerator.getPillarVotes,
      readProject: accelerator.getProjectById,
    );
  }

  /// A context that left cannot be revived by returning to its old values.
  bool get isCurrent => !_revoked && !(_revoked = !_stillCurrent());

  /// Refuses stale reads rather than looking up replacement capabilities.
  void requireCurrent() {
    if (!isCurrent) throw const AcceleratorListSuperseded();
  }
}

/// A superseded read does not authorize paint, navigation or publication.
final class AcceleratorListSuperseded implements Exception {
  /// Classifies source revocation without exposing backend diagnostics.
  const AcceleratorListSuperseded();
}
