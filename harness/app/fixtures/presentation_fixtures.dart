import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/fused_plasma/view/fused_plasma_card.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/plasma_owner/plasma_owner_controller.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/plasma_owner/plasma_session.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/send/send.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/sentinels/bloc/sentinels_bloc.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/sentinels/view/sentinels_card.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/sentinels_by_owner/view/sentinel_strip.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/utils.dart';
import 'package:zenon_syrius_wallet_flutter/utils/account_block_utils.dart';
import 'package:zenon_syrius_wallet_flutter/utils/app_theme.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

import 'fixture_cleanup.dart';
import 'seed_policy.dart';

/// Only the harness imports this route. It supplies presentation data locally;
/// it does not claim a sentinel registration or age a real chain fusion.
class SeedPresentationFixture extends StatefulWidget {
  const SeedPresentationFixture({
    required this.kind,
    required this.owner,
    required this.originalSdk,
    required this.isCurrent,
    required this.cleanup,
    super.key,
  });
  final String kind;
  final String owner;
  final Zenon originalSdk;
  final bool Function() isCurrent;

  /// The original admission, retained after this route becomes inactive.
  final FixtureCleanup cleanup;
  @override
  State<SeedPresentationFixture> createState() =>
      _SeedPresentationFixtureState();
}

class _SeedPresentationFixtureState extends State<SeedPresentationFixture> {
  _FixtureSentinels? _sentinels;
  _FixtureSender? _sender;
  PlasmaOwnerController? _fusions;
  Timer? _scopeClock;
  bool _expired = false;
  late final FixtureCleanup _cleanup;
  late final SentinelInfo _sentinel;
  bool get _current => mounted && !_expired && widget.isCurrent();
  @override
  void initState() {
    super.initState();
    _cleanup = widget.cleanup;
    _cleanup.attach(this);
    _sentinel = SentinelInfo.fromJson(<String, dynamic>{
      'owner': widget.owner,
      'registrationTimestamp': 1625132800,
      'isRevocable': true,
      'revokeCooldown': 3600,
      'active': true,
    });
    if (widget.kind == 'sentinel') {
      _sentinels = _FixtureSentinels(
        sdk: widget.originalSdk,
        rows: <SentinelInfo>[_sentinel],
        current: () => _current,
      );
      _sentinels!.add(const InfiniteListRequested());
    } else if (widget.kind == 'aged-fuse') {
      _sender = _FixtureSender();
      _fusions = PlasmaOwnerController(
        sender: _sender!,
        address: widget.owner,
        chainId: 321,
      );
      final List<FusionEntry> rows = <FusionEntry>[
        for (int id = 1; id <= 2; id++)
          FusionEntry(
            beneficiary: Address.parse(widget.owner),
            expirationHeight: 3600 + id,
            id: Hash.parse(id.toRadixString(16).padLeft(64, '0')),
            qsrAmount: BigInt.from(100 + id) * BigInt.from(100000000),
          ),
      ];
      final PlasmaSession session = PlasmaSession(
        address: widget.owner,
        chainId: 321,
        isCurrent: () => _current,
        readEntries: (int page, int size) async =>
            FusionEntryList.fromJson(<String, dynamic>{
              'qsrAmount': rows
                  .fold<BigInt>(
                    BigInt.zero,
                    (BigInt total, FusionEntry row) => total + row.qsrAmount,
                  )
                  .toString(),
              'count': rows.length,
              'list': page == 0
                  ? rows.map((FusionEntry row) => row.toJson()).toList()
                  : <Object>[],
            }),
        readFrontier: () async => 7201,
        readAccount: () async => AccountInfo(
          address: widget.owner,
          blockCount: 1,
          balanceInfoList: const <BalanceInfoListItem>[],
        ),
        cancelBlock: (_) =>
            throw const SeedRefused('fixture-publication-refused'),
        fuseBlock: (_, _) =>
            throw const SeedRefused('fixture-publication-refused'),
      );
      unawaited(_fusions!.load(session));
    } else {
      _expired = true;
    }
    _scopeClock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && !_expired && !widget.isCurrent()) {
        setState(() => _expired = true);
      }
    });
  }

  @override
  void dispose() {
    _expired = true;
    final Timer? clock = _scopeClock;
    final PlasmaOwnerController? fusions = _fusions;
    final _FixtureSentinels? sentinels = _sentinels;
    final _FixtureSender? sender = _sender;
    _cleanup.dispose(
      owner: this,
      dispose: <void Function()>[
        if (clock != null) clock.cancel,
        if (fusions != null) fusions.dispose,
      ],
      close: <Future<void> Function()>[
        if (sentinels != null) sentinels.close,
        if (sender != null) sender.close,
      ],
      stateDisposed: () => super.dispose(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = AppTokens.of(context);
    return Scaffold(
      body: Column(
        children: <Widget>[
          Material(
            color: tokens.card2,
            child: Padding(
              padding: tokens.cardPadding,
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      'Harness fixture · ${widget.kind} · read only',
                      style: tokens.compactText,
                    ),
                  ),
                  IconButton(
                    key: const Key('seed_fixture_close'),
                    tooltip: 'Close fixture',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: !_current
                ? const Center(child: Text('Fixture expired'))
                : ExcludeFocus(
                    child: AbsorbPointer(
                      child: KeyedSubtree(
                        key: Key('seed_fixture_${widget.kind}'),
                        child: Padding(
                          padding: tokens.cardPadding,
                          child: widget.kind == 'sentinel'
                              ? Column(
                                  children: <Widget>[
                                    SentinelStrip(
                                      selectedAddress: widget.owner,
                                      ownerState:
                                          FetchPopulated<List<SentinelInfo>>(
                                            data: <SentinelInfo>[_sentinel],
                                          ),
                                      rewards: const Text('Unknown'),
                                      collectAction: const SizedBox.shrink(),
                                    ),
                                    SizedBox(height: tokens.panelGap),
                                    Expanded(
                                      child: SentinelsCard(
                                        bloc: _sentinels,
                                        selectedAddress: widget.owner,
                                      ),
                                    ),
                                  ],
                                )
                              : FusedPlasmaCard(
                                  owner: _fusions!,
                                  captureSession: () => null,
                                  isCurrent: () => false,
                                ),
                        ),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

/// No fixture state is hydrated into an ordinary page's cache.
class _FixtureSentinels extends SentinelsBloc {
  _FixtureSentinels({
    required Zenon sdk,
    required this.rows,
    required this.current,
  }) : super(zenon: sdk);
  final List<SentinelInfo> rows;
  final bool Function() current;
  @override
  Future<List<SentinelInfo>> paginationFetch({
    required int pageIndex,
    required int pageSize,
    Address? address,
  }) async {
    if (!current()) throw const SeedRefused('fixture-expired');
    return pageIndex == 0
        ? List<SentinelInfo>.unmodifiable(rows)
        : <SentinelInfo>[];
  }

  @override
  Map<String, dynamic>? toJson(InfiniteListState<SentinelInfo> state) => null;
  @override
  InfiniteListState<SentinelInfo>? fromJson(Map<String, dynamic> json) => null;
}

class _FixtureSender extends SendTransactionBloc {
  _FixtureSender()
    : super(
        accountBlockUtilsHelper: _RefusePublication(),
        recordRecipient: (_, _) async {},
      );
  @override
  Map<String, dynamic>? toJson(SendTransactionState state) => null;
  @override
  SendTransactionState? fromJson(Map<String, dynamic> json) => null;
}

class _RefusePublication extends AccountBlockUtils {
  @override
  Future<AccountBlockTemplate> createAccountBlock(
    AccountBlockTemplate template,
    String purpose, {
    Address? address,
    bool waitForRequiredPlasma = false,
    bool Function()? canPublish,
  }) async => throw const SeedRefused('fixture-publication-refused');
}
