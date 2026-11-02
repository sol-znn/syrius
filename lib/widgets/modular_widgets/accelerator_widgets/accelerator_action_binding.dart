import 'package:flutter/foundation.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/token_balance/token_balance_snapshot.dart';
import 'package:zenon_syrius_wallet_flutter/utils/account_block_utils.dart';
import 'package:zenon_syrius_wallet_flutter/utils/global.dart';
import 'package:zenon_syrius_wallet_flutter/utils/input_validators.dart';
import 'package:zenon_syrius_wallet_flutter/utils/plasma_purpose.dart';
import 'package:zenon_syrius_wallet_flutter/utils/wallet_action_context.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/accelerator_widgets/accelerator_action_controller.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

/// Captures every action dependency before its first asynchronous read.
final class AcceleratorActionBinding implements AcceleratorActionSource {
  AcceleratorActionBinding._({
    required this.scopeKey,
    required this.ownerAddress,
    required this.maximumZnn,
    required this.maximumQsr,
    required this._current,
    required this._accelerator,
    required this._pillar,
    required this._ledger,
    required this._sender,
  }) : _address = Address.parse(ownerAddress);

  /// Binds explicit inert originals for tests of authority and error retention.
  /// No dependency is captured, looked up, read or published by construction.
  @visibleForTesting
  AcceleratorActionBinding.forTesting({
    required Object scopeKey,
    required String ownerAddress,
    required BigInt maximumZnn,
    required BigInt maximumQsr,
    required bool Function() current,
    required AcceleratorApi accelerator,
    required PillarApi pillar,
    required LedgerApi ledger,
    required Future<AccountBlockTemplate> Function(
      AccountBlockTemplate,
      String, {
      required bool Function() canPublish,
    })
    sender,
  }) : this._(
         scopeKey: scopeKey,
         ownerAddress: ownerAddress,
         maximumZnn: maximumZnn,
         maximumQsr: maximumQsr,
         current: current,
         accelerator: accelerator,
         pillar: pillar,
         ledger: ledger,
         sender: sender,
       );

  @override
  final Object scopeKey;
  @override
  final String ownerAddress;
  @override
  final BigInt maximumZnn;
  @override
  final BigInt maximumQsr;
  final bool Function() _current;
  final AcceleratorApi _accelerator;
  final PillarApi _pillar;
  final LedgerApi _ledger;
  final Address _address;
  final Future<AccountBlockTemplate> Function(
    AccountBlockTemplate,
    String, {
    required bool Function() canPublish,
  })
  _sender;
  bool _revoked = false;

  /// Captures the original signer, APIs, clients and URLs before any read.
  static AcceleratorActionBinding? capture() {
    final String? owner = kSelectedAddress;
    if (owner == null) return null;
    final WalletActionContext? context = WalletActionContext.capture(owner);
    if (context == null) return null;
    final Zenon sdk = context.client;
    final AcceleratorApi originalAccelerator = sdk.embedded.accelerator;
    final PillarApi originalPillar = sdk.embedded.pillar;
    final LedgerApi originalLedger = sdk.ledger;
    final Client acceleratorTransport = originalAccelerator.client;
    final Client pillarTransport = originalPillar.client;
    final Client ledgerTransport = originalLedger.client;
    final String? acceleratorUrl = acceleratorTransport is WsClient
        ? acceleratorTransport.url
        : null;
    final String? pillarUrl = pillarTransport is WsClient
        ? pillarTransport.url
        : null;
    final String? ledgerUrl = ledgerTransport is WsClient
        ? ledgerTransport.url
        : null;
    final AcceleratorApi accelerator = AcceleratorApi()
      ..setClient(acceleratorTransport);
    final PillarApi pillar = PillarApi()..setClient(pillarTransport);
    final LedgerApi ledger = LedgerApi()..setClient(ledgerTransport);
    bool current() =>
        context.isCurrent &&
        identical(originalAccelerator, sdk.embedded.accelerator) &&
        identical(originalPillar, sdk.embedded.pillar) &&
        identical(originalLedger, sdk.ledger) &&
        identical(originalAccelerator.client, acceleratorTransport) &&
        identical(originalPillar.client, pillarTransport) &&
        identical(originalLedger.client, ledgerTransport) &&
        (acceleratorTransport is! WsClient ||
            acceleratorTransport.url == acceleratorUrl) &&
        (pillarTransport is! WsClient || pillarTransport.url == pillarUrl) &&
        (ledgerTransport is! WsClient || ledgerTransport.url == ledgerUrl);
    final AccountBlockUtils sender = AccountBlockUtils.capture(
      address: Address.parse(owner),
      canPublish: current,
    );
    final Future<AccountBlockTemplate> Function(
      AccountBlockTemplate,
      String, {
      Address? address,
      bool waitForRequiredPlasma,
      bool Function()? canPublish,
    })
    original = sender.createAccountBlock;
    final Address originalOwner = Address.parse(owner);
    return AcceleratorActionBinding._(
      scopeKey: (kWalletPath ?? kWalletFile!, owner, getChainIdentifier()),
      ownerAddress: owner,
      maximumZnn: kZnnProjectMaximumFunds,
      maximumQsr: kQsrProjectMaximumFunds,
      accelerator: accelerator,
      pillar: pillar,
      ledger: ledger,
      sender:
          (
            AccountBlockTemplate template,
            String purpose, {
            required bool Function() canPublish,
          }) => original(
            template,
            purpose,
            address: originalOwner,
            canPublish: canPublish,
          ),
      current: current,
    );
  }

  @override
  bool get isCurrent {
    if (_revoked) {
      return false;
    }
    final bool lost = !_current();
    _revoked = _revoked || lost;
    return !_revoked;
  }

  void _requireCurrent() {
    if (!isCurrent) throw const AcceleratorActionRefused();
  }

  @override
  bool validMetadata(AcceleratorActionRequest request) =>
      Validations.projectName(request.name) == null &&
      Validations.projectDescription(request.description) == null &&
      InputValidators.checkUrl(request.url) == null;

  @override
  List<AccountBlockTemplate> build(AcceleratorActionRequest request) {
    _requireCurrent();
    return switch (request.kind) {
      AcceleratorActionKind.createProject => <AccountBlockTemplate>[
        _accelerator.createProject(
          request.name,
          request.description,
          request.url,
          request.znn,
          request.qsr,
        ),
      ],
      AcceleratorActionKind.createPhase => <AccountBlockTemplate>[
        _accelerator.addPhase(
          Hash.parse(request.projectId!),
          request.name,
          request.description,
          request.url,
          request.znn,
          request.qsr,
        ),
      ],
      AcceleratorActionKind.updatePhase => <AccountBlockTemplate>[
        _accelerator.updatePhase(
          Hash.parse(request.projectId!),
          request.name,
          request.description,
          request.url,
          request.znn,
          request.qsr,
        ),
      ],
      AcceleratorActionKind.vote => <AccountBlockTemplate>[
        _accelerator.voteByName(
          Hash.parse(request.targetId!),
          request.pillarName!,
          request.vote!.index,
        ),
      ],
      AcceleratorActionKind.donate => <AccountBlockTemplate>[
        if (request.znn > BigInt.zero) _accelerator.donate(request.znn, znnZts),
        if (request.qsr > BigInt.zero) _accelerator.donate(request.qsr, qsrZts),
      ],
    };
  }

  @override
  Future<Project> readProject(String id) {
    _requireCurrent();
    return _accelerator.getProjectById(id);
  }

  @override
  Future<List<PillarInfo>> readPillars() {
    _requireCurrent();
    return _pillar.getByOwner(_address);
  }

  @override
  Future<List<PillarVote?>> readVotes(String name, List<String> ids) {
    _requireCurrent();
    return _accelerator.getPillarVotes(name, List<String>.unmodifiable(ids));
  }

  @override
  Future<AcceleratorActionBalance> readBalance() async {
    _requireCurrent();
    final AccountInfo account = await _ledger.getAccountInfoByAddress(_address);
    _requireCurrent();
    final TokenBalanceSnapshot exact = TokenBalanceSnapshot.fromAccount(
      account,
      ownerAddress,
    );
    return AcceleratorActionBalance(
      exact.unitsFor(znnZts),
      exact.unitsFor(qsrZts),
    );
  }

  @override
  Future<bool> readConfirmed(String hash) async {
    _requireCurrent();
    final AccountBlock? block = await _ledger.getAccountBlockByHash(
      Hash.parse(hash),
    );
    _requireCurrent();
    return block?.hash.toString() == hash && block?.confirmationDetail != null;
  }

  @override
  Future<AccountBlockTemplate> publish(
    AccountBlockTemplate template,
    AcceleratorActionKind kind, {
    required bool Function() canPublish,
  }) {
    _requireCurrent();
    final String purpose = switch (kind) {
      AcceleratorActionKind.createProject =>
        PlasmaPurpose.createProject.message,
      AcceleratorActionKind.createPhase => PlasmaPurpose.createPhase.message,
      AcceleratorActionKind.updatePhase => PlasmaPurpose.updatePhase.message,
      AcceleratorActionKind.donate => PlasmaPurpose.donateToAccelerator.message,
      AcceleratorActionKind.vote => PlasmaPurpose.voteForProject.message,
    };
    return _sender(
      template,
      purpose,
      canPublish: () => isCurrent && canPublish(),
    );
  }
}
