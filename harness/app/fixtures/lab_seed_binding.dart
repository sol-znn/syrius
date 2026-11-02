import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/send/model/send_intent.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/token_balance/token_balance_snapshot.dart';
import 'package:zenon_syrius_wallet_flutter/utils/account_block_utils.dart';
import 'package:zenon_syrius_wallet_flutter/utils/global.dart';
import 'package:zenon_syrius_wallet_flutter/utils/original_publications.dart';
import 'package:zenon_syrius_wallet_flutter/utils/wallet_action_context.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

import 'seed_policy.dart';

/// Every wrapper and transport below is captured before the first await.
/// No fixture installs a client into the ordinary app's global SDK.
final class LabSeedBinding implements SeedSource {
  LabSeedBinding._({
    required this.environment,
    required this.home,
    required this._current,
    required this.walletOwner,
    required this.originalSdk,
    required this._ledger,
    required this._stake,
    required this._plasma,
    required this._token,
    required this._htlc,
    required this._accelerator,
    required this.counterparty,
  });

  /// Captures the isolated lab profile and its exact existing SDK transports.
  factory LabSeedBinding.capture({
    required String profile,
    required String ws,
    required String http,
    required bool booted,
    String? counterparty,
    void Function(String)? observePhase,
  }) {
    if (ws != seedWsOrigin || http != seedHttpOrigin) {
      throw const SeedRefused('explicit-lab-origins-required');
    }
    observePhase?.call('profile_owner');
    final String? owner = kSelectedAddress;
    final WalletActionContext? context = owner == null
        ? null
        : WalletActionContext.capture(owner);
    final Object? walletOwner = kWalletFile;
    if (context == null || walletOwner == null) {
      throw const SeedRefused('unlocked-wallet-required');
    }
    final Zenon sdk = context.client;
    observePhase?.call('profile_apis');
    final LedgerApi originalLedger = sdk.ledger;
    final StakeApi originalStake = sdk.embedded.stake;
    final PlasmaApi originalPlasma = sdk.embedded.plasma;
    final TokenApi originalToken = sdk.embedded.token;
    final HtlcApi originalHtlc = sdk.embedded.htlc;
    final AcceleratorApi originalAccelerator = sdk.embedded.accelerator;
    final List<Client> transports = <Client>[
      originalLedger.client,
      originalStake.client,
      originalPlasma.client,
      originalToken.client,
      originalHtlc.client,
      originalAccelerator.client,
    ];
    observePhase?.call('profile_transports');
    if (transports.any(
      (Client client) => client is! WsClient || client.url != seedWsOrigin,
    )) {
      throw const SeedRefused('exact-original-lab-transports-required');
    }
    final LedgerApi ledger = LedgerApi()..setClient(transports[0]);
    final StakeApi stake = StakeApi()..setClient(transports[1]);
    final PlasmaApi plasma = PlasmaApi()..setClient(transports[2]);
    final TokenApi token = TokenApi()..setClient(transports[3]);
    final HtlcApi htlc = HtlcApi()..setClient(transports[4]);
    final AcceleratorApi accelerator = AcceleratorApi()
      ..setClient(transports[5]);
    observePhase?.call('profile_paths');
    final Map<String, String> env = <String, String>{
      for (final MapEntry<String, String> entry in Platform.environment.entries)
        entry.key.toUpperCase(): entry.value,
    };
    final String? home = env['SYRIUS_HARNESS_HOME'];
    final String? wallet = kWalletPath;
    final List<String?> rawMembers = List<String?>.of(kDefaultAddressList);
    if (home == null || wallet == null) {
      throw const SeedRefused('owned-isolated-profile-required');
    }
    observePhase?.call('profile_members');
    if (rawMembers.any((String? value) => value == null)) {
      throw const SeedRefused('owned-isolated-profile-required');
    }
    observePhase?.call('profile_layout');
    if (!_isolated(profile, home, env)) {
      throw const SeedRefused('owned-isolated-profile-required');
    }
    observePhase?.call('profile_wallet');
    if (!path.isWithin(home, wallet)) {
      throw const SeedRefused('owned-isolated-profile-required');
    }
    observePhase?.call('profile_terms');
    final SeedEnvironment environment = SeedEnvironment(
      profile: profile,
      isolated: true,
      unlocked: true,
      initialized: kWalletInitCompleted,
      booted: booted,
      ws: kCurrentNode ?? '',
      http: http,
      nodeChain: kNodeChainId,
      signingChain: getChainIdentifier(),
      selectedIndex: rawMembers.indexOf(owner),
      owner: owner!,
      members: rawMembers.whereType<String>(),
    )..requireLab();
    final String? exactCounterparty = counterparty == null
        ? null
        : Address.parse(counterparty).toString();
    if (exactCounterparty != null &&
        (exactCounterparty != counterparty ||
            exactCounterparty == emptyAddress.toString() ||
            environment.members.contains(exactCounterparty))) {
      throw const SeedRefused('external-lab-counterparty-required');
    }
    bool current() =>
        context.isCurrent &&
        identical(walletOwner, kWalletFile) &&
        identical(originalLedger, sdk.ledger) &&
        identical(originalStake, sdk.embedded.stake) &&
        identical(originalPlasma, sdk.embedded.plasma) &&
        identical(originalToken, sdk.embedded.token) &&
        identical(originalHtlc, sdk.embedded.htlc) &&
        identical(originalAccelerator, sdk.embedded.accelerator) &&
        identical(transports[0], originalLedger.client) &&
        identical(transports[1], originalStake.client) &&
        identical(transports[2], originalPlasma.client) &&
        identical(transports[3], originalToken.client) &&
        identical(transports[4], originalHtlc.client) &&
        identical(transports[5], originalAccelerator.client) &&
        transports.every(
          (Client client) => client is WsClient && client.url == seedWsOrigin,
        ) &&
        _isolated(profile, home, env);
    return LabSeedBinding._(
      environment: environment,
      home: home,
      current: current,
      walletOwner: walletOwner,
      originalSdk: sdk,
      ledger: ledger,
      stake: stake,
      plasma: plasma,
      token: token,
      htlc: htlc,
      accelerator: accelerator,
      counterparty: exactCounterparty,
    );
  }

  static bool _isolated(String profile, String home, Map<String, String> env) {
    if (profile == 'default' ||
        path.basename(home) != profile ||
        path.basename(path.dirname(home)) != '.harness' ||
        !path.isAbsolute(home)) {
      return false;
    }
    final Map<String, String> expected = <String, String>{
      'HOME': home,
      'USERPROFILE': home,
      'APPDATA': path.join(home, 'AppData', 'Roaming'),
      'LOCALAPPDATA': path.join(home, 'AppData', 'Local'),
      'TEMP': path.join(home, 'Temp'),
      'TMP': path.join(home, 'Temp'),
    };
    if (expected.entries.any(
      (MapEntry<String, String> entry) =>
          env[entry.key] == null ||
          !path.equals(
            path.normalize(env[entry.key]!),
            path.normalize(entry.value),
          ),
    )) {
      return false;
    }
    String cursor = path.normalize(home);
    for (int depth = 0; depth < 64; depth++) {
      if (FileSystemEntity.typeSync(cursor, followLinks: false) !=
          FileSystemEntityType.directory) {
        return false;
      }
      final String parent = path.dirname(cursor);
      if (parent == cursor) return true;
      cursor = parent;
    }
    return false;
  }

  @override
  final SeedEnvironment environment;
  final String home;
  final String? counterparty;
  final Object walletOwner;
  final Zenon originalSdk;
  final bool Function() _current;
  final LedgerApi _ledger;
  final StakeApi _stake;
  final PlasmaApi _plasma;
  final TokenApi _token;
  final HtlcApi _htlc;
  final AcceleratorApi _accelerator;
  bool _revoked = false;
  @override
  bool get isCurrent {
    if (_revoked) return false;
    try {
      return !(_revoked = !_current());
    } on Object {
      _revoked = true;
      return false;
    }
  }

  void _requireCurrent() {
    if (!isCurrent) throw const SeedRefused('original-context-changed');
  }

  @override
  Future<SeedFrontier> wsFrontier() async {
    _requireCurrent();
    final Momentum value = await _ledger.getFrontierMomentum();
    _requireCurrent();
    return SeedFrontier(
      chain: value.chainIdentifier,
      height: value.height,
      timestamp: value.timestamp,
      hash: value.hash.toString(),
    );
  }

  @override
  Future<SeedFrontier> httpFrontier() async {
    _requireCurrent();
    final HttpClient client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 2)
      ..findProxy = (_) => 'DIRECT';
    try {
      final HttpClientRequest request = await client
          .postUrl(Uri.parse(seedHttpOrigin))
          .timeout(const Duration(seconds: 2));
      request.followRedirects = false;
      request.headers.contentType = ContentType.json;
      request.write(
        jsonEncode(<String, Object>{
          'jsonrpc': '2.0',
          'id': 1,
          'method': 'ledger.getFrontierMomentum',
          'params': <Object>[],
        }),
      );
      final HttpClientResponse response = await request.close().timeout(
        const Duration(seconds: 2),
      );
      if (response.statusCode != 200) {
        throw const SeedRefused('lab-http-response-refused');
      }
      final List<int> bytes = await response
          .fold<List<int>>(<int>[], (List<int> bytes, List<int> chunk) {
            if (bytes.length + chunk.length > 262144) {
              throw const SeedRefused('lab-http-response-too-large');
            }
            bytes.addAll(chunk);
            return bytes;
          })
          .timeout(const Duration(seconds: 2));
      final Object? decoded = jsonDecode(utf8.decode(bytes));
      if (decoded is! Map<String, dynamic> ||
          decoded['jsonrpc'] != '2.0' ||
          decoded['id'] != 1 ||
          decoded['error'] != null ||
          decoded['result'] is! Map<String, dynamic>) {
        throw const SeedRefused('lab-http-rpc-refused');
      }
      final Map<String, dynamic> value =
          decoded['result'] as Map<String, dynamic>;
      if (value['chainIdentifier'] is! int ||
          value['height'] is! int ||
          value['timestamp'] is! int ||
          value['hash'] is! String) {
        throw const SeedRefused('lab-http-frontier-incomplete');
      }
      _requireCurrent();
      return SeedFrontier(
        chain: value['chainIdentifier'] as int,
        height: value['height'] as int,
        timestamp: value['timestamp'] as int,
        hash: value['hash'] as String,
      );
    } finally {
      client.close(force: true);
    }
  }

  @override
  Future<bool> sameMomentum(SeedFrontier http) async {
    _requireCurrent();
    final Momentum? ws = await _ledger.getMomentumByHash(Hash.parse(http.hash));
    _requireCurrent();
    return ws?.hash.toString() == http.hash &&
        ws?.height == http.height &&
        ws?.timestamp == http.timestamp &&
        ws?.chainIdentifier == 321;
  }

  @override
  Future<SeedFunding> funding() async {
    _requireCurrent();
    final AccountInfo account = await _ledger.getAccountInfoByAddress(
      Address.parse(environment.owner),
    );
    _requireCurrent();
    final TokenBalanceSnapshot balance = TokenBalanceSnapshot.fromAccount(
      account,
      environment.owner,
    );
    return SeedFunding(balance.unitsFor(znnZts), balance.unitsFor(qsrZts));
  }

  @override
  SeedFunding minimum(String recipe) => SeedFunding(
    switch (recipe) {
      'stake' => BigInt.from(300) * BigInt.from(100000000),
      'token' => tokenZtsIssueFeeInZnn,
      'project' => projectCreationFeeInZnn,
      'fund-address' => BigInt.from(10) * BigInt.from(100000000),
      _ => BigInt.from(100000000),
    },
    recipe == 'fuse' ? BigInt.from(100) * BigInt.from(100000000) : BigInt.zero,
  );

  @override
  List<SeedOriginal> originals() => OriginalPublications.snapshot(
    walletOwner,
  ).map(_Original.new).toList(growable: false);

  @override
  Future<SeedConfirmed?> confirmed(String recipe, String hash) async {
    _requireCurrent();
    final AccountBlock? block = await _ledger.getAccountBlockByHash(
      Hash.parse(hash),
    );
    _requireCurrent();
    if (block == null) return null;
    final (
      Address target,
      TokenStandard standard,
      BigInt amount,
      Abi? abi,
      String? method,
    ) = switch (recipe) {
      'stake' => (
        stakeAddress,
        znnZts,
        BigInt.from(30000000000),
        Definitions.stake,
        'Stake',
      ),
      'fuse' => (
        plasmaAddress,
        qsrZts,
        BigInt.from(10000000000),
        Definitions.plasma,
        'Fuse',
      ),
      'token' => (
        tokenAddress,
        znnZts,
        tokenZtsIssueFeeInZnn,
        Definitions.token,
        'IssueToken',
      ),
      'project' => (
        acceleratorAddress,
        znnZts,
        projectCreationFeeInZnn,
        Definitions.accelerator,
        'CreateProject',
      ),
      'deposit' => (
        htlcAddress,
        znnZts,
        BigInt.from(100000000),
        Definitions.htlc,
        'Create',
      ),
      'fund-address' when environment.members.length >= 3 => (
        Address.parse(environment.members[2]),
        znnZts,
        BigInt.from(1000000000),
        null,
        null,
      ),
      labSendRecipeId => (
        Address.parse(environment.members[0]),
        znnZts,
        BigInt.from(100000000),
        null,
        null,
      ),
      _ => throw const SeedRefused('recipe-prerequisite-missing'),
    };
    return SeedConfirmed(
      hash: block.hash.toString(),
      owner: block.address.toString(),
      chain: block.chainIdentifier,
      positiveConfirmation:
          block.confirmationDetail != null &&
          block.confirmationDetail!.numConfirmations > 0 &&
          block.confirmationDetail!.momentumTimestamp > 0,
      matchesRecipe:
          block.blockType == BlockTypeEnum.userSend.index &&
          block.toAddress == target &&
          block.tokenStandard == standard &&
          block.amount == amount &&
          (abi == null
              ? block.data.isEmpty
              : AccountBlockUtils.getDecodedBlockData(
                      abi,
                      block.data,
                    )?.function ==
                    method),
    );
  }

  @override
  Future<bool> effect(String recipe, String hash) async {
    _requireCurrent();
    final Address owner = Address.parse(environment.owner);
    if (recipe == 'stake') {
      final StakeList rows = await _stake.getEntriesByAddress(
        owner,
        pageSize: 64,
      );
      _requireCurrent();
      return rows.count == rows.list.length &&
          rows.count <= 64 &&
          rows.list
                  .where(
                    (StakeEntry row) =>
                        row.id.toString() == hash &&
                        row.address == owner &&
                        row.amount == BigInt.from(30000000000) &&
                        row.expirationTimestamp - row.startTimestamp ==
                            6 * stakeTimeUnitSec,
                  )
                  .length ==
              1;
    }
    if (recipe == 'fuse') {
      final FusionEntryList rows = await _plasma.getEntriesByAddress(
        owner,
        pageSize: 64,
      );
      _requireCurrent();
      return rows.count == rows.list.length &&
          rows.count <= 64 &&
          rows.list
                  .where(
                    (FusionEntry row) =>
                        row.id.toString() == hash &&
                        row.beneficiary == owner &&
                        row.qsrAmount == BigInt.from(10000000000),
                  )
                  .length ==
              1;
    }
    if (recipe == 'token') {
      final TokenStandard standard = TokenStandard.fromBytes(
        Crypto.digest(
          Hash.parse(hash).getBytes()!,
        ).sublist(0, TokenStandard.coreSize),
      );
      final Token? token = await _token.getByZts(standard);
      _requireCurrent();
      return token?.tokenStandard == standard &&
          token?.owner == owner &&
          token?.name == 'LabToken' &&
          token?.symbol == 'LAB';
    }
    if (recipe == 'project') {
      final Project project = await _accelerator.getProjectById(hash);
      _requireCurrent();
      return project.id.toString() == hash &&
          project.owner == owner &&
          project.name == 'Lab Project' &&
          project.znnFundsNeeded == BigInt.from(10000000000) &&
          project.qsrFundsNeeded == BigInt.from(10000000000);
    }
    if (recipe == 'deposit') {
      if (counterparty == null) {
        throw const SeedRefused('external-lab-counterparty-required');
      }
      final HtlcInfo value = await _htlc.getById(Hash.parse(hash));
      _requireCurrent();
      return value.id.toString() == hash &&
          value.timeLocked == owner &&
          value.hashLocked.toString() == counterparty &&
          value.tokenStandard == znnZts &&
          value.amount == BigInt.from(100000000);
    }
    if (recipe == 'fund-address' && environment.members.length >= 3) {
      final String recipient = environment.members[2];
      final AccountInfo account = await _ledger.getAccountInfoByAddress(
        Address.parse(recipient),
      );
      _requireCurrent();
      if (TokenBalanceSnapshot.fromAccount(
            account,
            recipient,
          ).unitsFor(znnZts) <
          BigInt.from(1000000000)) {
        return false;
      }
      final AccountBlockList receives = await _ledger.getAccountBlocksByPage(
        Address.parse(recipient),
        pageSize: 64,
      );
      _requireCurrent();
      final List<AccountBlock>? rows = receives.list;
      if (rows == null) return false;
      return rows
              .where(
                (AccountBlock row) =>
                    row.hash != emptyHash &&
                    row.chainIdentifier == 321 &&
                    row.address.toString() == recipient &&
                    row.blockType == BlockTypeEnum.userReceive.index &&
                    row.fromBlockHash.toString() == hash &&
                    row.confirmationDetail != null &&
                    row.confirmationDetail!.numConfirmations > 0,
              )
              .length ==
          1;
    }
    throw const SeedRefused('recipe-prerequisite-missing');
  }
}

final class _Original implements SeedOriginal {
  const _Original(this.value);
  final OriginalPublication<dynamic> value;
  @override
  Object get identity => value;
  @override
  bool get settled => value.settled;
  @override
  bool get failed => value.error != null;
  @override
  bool get releaseFailed => value.releaseError != null;
  @override
  String? get acceptedHash => value.acceptedHash;
}

/// Three exclusive records at most per recipe; no duplicate binary payloads.
/// The isolated profile must remain under one process's sole ownership.
final class ProfileSeedJournal implements SeedJournal {
  ProfileSeedJournal(this.home) : _labSendReview = null;

  /// Records the identical fixed P09 review before the single ordinary accept.
  ProfileSeedJournal.forLabSend(
    this.home, {
    required SeedEnvironment environment,
    required SendIntent intent,
  }) : _labSendReview = _captureLabSendReview(environment, intent);

  final String home;
  final Map<String, Object>? _labSendReview;
  static const Set<String> _reviewKeys = <String>{
    'profile', 'from', 'to', 'recipientInput', 'amountInput',
    'token', 'amount', 'decimals', 'symbol', 'chain',
  };

  static Map<String, Object> _captureLabSendReview(
    SeedEnvironment environment,
    SendIntent intent,
  ) {
    environment.requireLab();
    if (intent.fromAddress != environment.owner ||
        intent.toAddress != environment.members[0]) {
      throw const SeedRefused('original-transfer-review-required');
    }
    final Map<String, Object> review = <String, Object>{
      'profile': environment.profile,
      'from': intent.fromAddress,
      'to': intent.toAddress,
      'recipientInput': intent.recipientInput,
      'amountInput': intent.amountInput,
      'token': intent.tokenStandard,
      'amount': intent.amount.toString(),
      'decimals': intent.decimals,
      'symbol': intent.symbol,
      'chain': 321,
    };
    if (!_validReview(review)) {
      throw const SeedRefused('original-transfer-review-required');
    }
    return Map<String, Object>.unmodifiable(review);
  }

  static bool _validReview(Object? value) {
    if (value is! Map<String, dynamic> || value.length != _reviewKeys.length ||
        !value.keys.toSet().containsAll(_reviewKeys) ||
        value['profile'] is! String || value['profile'] == 'default' ||
        !RegExp(r'^[A-Za-z0-9][A-Za-z0-9_-]{0,63}$')
            .hasMatch(value['profile'] as String) ||
        value['from'] is! String || value['to'] is! String ||
        value['from'] == value['to'] ||
        value['recipientInput'] != value['to'] ||
        value['amountInput'] != '1' || value['amount'] != '100000000' ||
        value['token'] != znnZts.toString() || value['decimals'] != 8 ||
        value['symbol'] != 'ZNN' || value['chain'] != 321) {
      return false;
    }
    try {
      return Address.parse(value['from'] as String).toString() ==
              value['from'] &&
          Address.parse(value['to'] as String).toString() == value['to'] &&
          value['from'] != emptyAddress.toString() &&
          value['to'] != emptyAddress.toString();
    } on Object {
      return false;
    }
  }

  static bool _sameReview(Object? left, Object? right) =>
      left is Map<String, dynamic> && right is Map<String, dynamic> &&
      _reviewKeys.every((String key) => left[key] == right[key]);

  File _file(String recipe, String state) =>
      File(path.join(home, 'seed-$recipe-$state.json'));
  Map<String, dynamic>? _read(String recipe, String state) {
    final File file = _file(recipe, state);
    final FileSystemEntityType type = FileSystemEntity.typeSync(
      file.path,
      followLinks: false,
    );
    if (type == FileSystemEntityType.notFound) return null;
    if (type != FileSystemEntityType.file || file.lengthSync() > 2048) {
      throw const SeedRefused('seed-journal-held');
    }
    final Object? value = jsonDecode(file.readAsStringSync());
    if (value is! Map<String, dynamic> ||
        value['recipe'] != recipe ||
        value['chain'] != 321 ||
        value['state'] != state ||
        state != 'attempt' &&
            (value['hash'] is! String || !seedHash(value['hash'] as String))) {
      throw const SeedRefused('seed-journal-held');
    }
    if (recipe == labSendRecipeId && !_validReview(value['review'])) {
      throw const SeedRefused('seed-journal-held');
    }
    return value;
  }

  void _write(String recipe, String state, {String? hash}) {
    if (!seedRecipeIds.contains(recipe) && recipe != labSendRecipeId) {
      throw const SeedRefused('unknown-recipe');
    }
    if (recipe == labSendRecipeId &&
        (_labSendReview == null || state != 'attempt' &&
            !_sameReview(
              _read(recipe, 'attempt')?['review'], _labSendReview,
            ))) {
      throw const SeedRefused('original-transfer-review-required');
    }
    _file(recipe, state)
      ..createSync(exclusive: true)
      ..writeAsStringSync(
        jsonEncode(<String, Object>{
          'recipe': recipe,
          'chain': 321,
          'state': state,
          'hash': ?hash,
          if (recipe == labSendRecipeId) 'review': _labSendReview!,
        }),
        flush: true,
      );
  }

  @override
  void requireAvailable(String recipe) {
    for (final String id in <String>{...seedRecipeIds, labSendRecipeId}) {
      final Map<String, dynamic>? attempt = _read(id, 'attempt');
      final Map<String, dynamic>? accepted = _read(id, 'accepted');
      final Map<String, dynamic>? confirmed = _read(id, 'confirmed');
      if (id == labSendRecipeId && attempt != null &&
          (accepted != null &&
                  !_sameReview(attempt['review'], accepted['review']) ||
              confirmed != null &&
                  !_sameReview(attempt['review'], confirmed['review']))) {
        throw const SeedRefused('seed-journal-held');
      }
      if (attempt == null && (accepted != null || confirmed != null) ||
          confirmed != null &&
              (accepted == null ||
                  confirmed['hash'] != accepted['hash'] ||
                  confirmed['hash'] is! String ||
                  !seedHash(confirmed['hash'] as String))) {
        throw const SeedRefused('seed-journal-held');
      }
      if (attempt != null && (id == recipe || confirmed == null)) {
        throw const SeedRefused('earlier-seed-attempt-held');
      }
    }
  }

  @override
  void claim(String recipe) {
    requireAvailable(recipe);
    _write(recipe, 'attempt');
  }

  @override
  void accepted(String recipe, String hash) {
    final Map<String, dynamic>? existing = _read(recipe, 'accepted');
    if (existing == null) {
      _write(recipe, 'accepted', hash: hash);
    } else if (existing['hash'] != hash ||
        recipe == labSendRecipeId &&
            !_sameReview(existing['review'], _labSendReview)) {
      throw const SeedRefused('original-hash-changed');
    }
  }

  @override
  void confirmed(String recipe, String hash) {
    accepted(recipe, hash);
    _write(recipe, 'confirmed', hash: hash);
  }

  /// This original live review must already have its exact confirmation.
  /// Records alone never supply the in-memory sender or publication owner.
  void requireLabSendConfirmed(String hash) {
    if (_labSendReview == null || !seedHash(hash)) {
      throw const SeedRefused('original-transfer-review-required');
    }
    _requireConfirmedReview(_labSendReview, hash);
  }

  /// Reads copied records without constructing a publication or live review.
  /// The coordinator separately retains the original process and copy owner.
  void requireRestoredLabSend({
    required String originalProfile,
    required String owner,
    required String recipient,
    required String hash,
  }) {
    final Map<String, Object> review = <String, Object>{
      'profile': originalProfile, 'from': owner, 'to': recipient,
      'recipientInput': recipient, 'amountInput': '1',
      'token': znnZts.toString(), 'amount': '100000000',
      'decimals': 8, 'symbol': 'ZNN', 'chain': 321,
    };
    if (!_validReview(review) || !seedHash(hash)) {
      throw const SeedRefused('original-transfer-review-required');
    }
    _requireConfirmedReview(review, hash);
  }

  void _requireConfirmedReview(Map<String, Object> review, String hash) {
    for (final String state in <String>['attempt', 'accepted', 'confirmed']) {
      final Map<String, dynamic>? value = _read(labSendRecipeId, state);
      final Set<String> keys = <String>{
        'recipe', 'chain', 'state', 'review', if (state != 'attempt') 'hash',
      };
      if (value == null || value.length != keys.length ||
          !value.keys.toSet().containsAll(keys) ||
          !_sameReview(value['review'], review) ||
          state != 'attempt' && value['hash'] != hash) {
        throw const SeedRefused('seed-journal-held');
      }
    }
    for (final String recipe in seedRecipeIds) {
      for (final String state in <String>['attempt', 'accepted', 'confirmed']) {
        if (_read(recipe, state) != null) {
          throw const SeedRefused('earlier-seed-attempt-held');
        }
      }
    }
  }
}
