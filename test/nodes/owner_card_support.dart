import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/single_child_widget.dart';
import 'package:zenon_syrius_wallet_flutter/l10n/l10n.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/node_owner/pillar_owner_card.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/pillars_by_owner/bloc/pillars_by_owner_bloc.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/send/bloc/send_transaction/send_transaction_bloc.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/blocs/fetch_bloc/fetch_bloc.dart';
import 'package:zenon_syrius_wallet_flutter/utils/account_block_utils.dart';
import 'package:zenon_syrius_wallet_flutter/utils/address_utils.dart';
import 'package:zenon_syrius_wallet_flutter/utils/app_theme.dart';
import 'package:zenon_syrius_wallet_flutter/utils/notifiers/balance_visibility.dart';
import 'package:zenon_syrius_wallet_flutter/utils/wallet_context_revision.dart';
import 'package:zenon_syrius_wallet_flutter/utils/zts_utils.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/reusable_widgets/app_lottie.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

import '../publication_session/support.dart';

class _Balances extends Mock implements ZenonAddressUtils {}

class _Embedded extends Fake implements EmbeddedApi {
  _Embedded(this.pillar);

  @override
  PillarApi pillar;
}

/// Holds each independent monetary read without using a node or ABI encoder.
class OwnerCardPillarApi extends Fake implements PillarApi {
  /// Starts with one actual copied owner record.
  OwnerCardPillarApi(this.rows);

  /// Subsequent reads may deliberately return an empty or foreign answer.
  List<PillarInfo> rows;

  /// Overrides one fresh ownership proof independently of the displayed read.
  Future<List<PillarInfo>> Function(Address)? lookupOwner;

  /// Exact accounts requested by the adapter and its fresh proof.
  final List<Address> ownerRequests = <Address>[];

  /// Exact accounts requested for QSR deposits.
  final List<Address> depositRequests = <Address>[];

  /// Each read belongs to the widget test's clock and must be completed.
  final List<Completer<BigInt>> deposits = <Completer<BigInt>>[];

  /// Cost has its own reply and cannot establish an account's deposit.
  final List<Completer<BigInt>> costs = <Completer<BigInt>>[];

  /// Exact smallest-unit amounts passed to the existing SDK action.
  final List<BigInt> depositActions = <BigInt>[];

  /// Counts only explicit withdrawals.
  int withdrawals = 0;

  /// Exact displayed names passed to the existing revocation action.
  final List<String> revokeActions = <String>[];

  @override
  Future<List<PillarInfo>> getByOwner(Address address) {
    ownerRequests.add(address);
    return lookupOwner?.call(address) ??
        Future<List<PillarInfo>>.value(List<PillarInfo>.of(rows));
  }

  @override
  Future<BigInt> getDepositedQsr(Address address) {
    depositRequests.add(address);
    final Completer<BigInt> reply = Completer<BigInt>();
    deposits.add(reply);
    return reply.future;
  }

  @override
  Future<BigInt> getQsrRegistrationCost() {
    final Completer<BigInt> reply = Completer<BigInt>();
    costs.add(reply);
    return reply.future;
  }

  @override
  AccountBlockTemplate depositQsr(BigInt amount) {
    depositActions.add(amount);
    return AccountBlockTemplate(
      blockType: BlockTypeEnum.userSend.index,
      amount: amount,
      tokenStandard: kQsrCoin.tokenStandard,
      data: const <int>[1, 2, 3, 4],
    );
  }

  @override
  AccountBlockTemplate withdrawQsr() {
    withdrawals++;
    return AccountBlockTemplate(
      blockType: BlockTypeEnum.userSend.index,
      tokenStandard: kQsrCoin.tokenStandard,
      data: const <int>[4, 3, 2, 1],
    );
  }

  @override
  AccountBlockTemplate revoke(String name) {
    revokeActions.add(name);
    return AccountBlockTemplate(
      blockType: BlockTypeEnum.userSend.index,
      tokenStandard: kZnnCoin.tokenStandard,
      data: const <int>[5, 6, 7, 8],
    );
  }

  /// Settles unused replies before their fixture releases its globals.
  void finishFacts() {
    for (final Completer<BigInt> reply in <Completer<BigInt>>[
      ...deposits,
      ...costs,
    ]) {
      if (!reply.isCompleted) reply.complete(BigInt.zero);
    }
  }
}

/// Builds a real SDK model from canonical public test addresses.
PillarInfo ownerCardPillar({
  Address? owner,
  String name = 'fixture-pillar',
  bool revocable = false,
  int cooldown = 0,
}) => PillarInfo.fromJson(<String, dynamic>{
  'name': name,
  'rank': 1,
  'type': 0,
  'ownerAddress': (owner ?? emptyAddress).toString(),
  'producerAddress': kZnnCoin.owner.toString(),
  'withdrawAddress': emptyAddress.toString(),
  'isRevocable': revocable,
  'revokeCooldown': cooldown,
  'revokeTimestamp': 0,
  // Explicit synthetic epoch facts required by the SDK model.
  'currentStats': const <String, int>{
    'producedMomentums': 1760,
    'expectedMomentums': 1762,
  },
  'weight': '900719925474099300000009',
  'giveMomentumRewardPercentage': 7,
  'giveDelegateRewardPercentage': 83,
});

/// Uses the real reader, shared sender and publisher with fake SDK I/O.
class OwnerCardFixture {
  /// Must be constructed inside the widget test that owns its async work.
  OwnerCardFixture() {
    publication = PublicationFixture();
    rpc = OwnerCardPillarApi(<PillarInfo>[ownerCardPillar()]);
    when(() => publication.node.embedded).thenReturn(_Embedded(rpc));
    when(_balances.refreshBalance).thenAnswer((_) {});
    publication.sendReply = transport.future;
    reader = PillarsByOwnerBloc(zenon: publication.node);
    sender = SendTransactionBloc(
      accountBlockUtilsHelper: AccountBlockUtils(
        publicationObserver:
            (
              AccountBlockTemplate block,
              Iterable<String> addresses,
            ) {
              publication.registry.published(block, addresses);
            },
      ),
      zenonAddressUtils: _balances,
      recordRecipient: (_, _) async {},
    );
  }

  /// Captured before the publication fixture changes any process state.
  final PublicationGlobals globals = PublicationGlobals();

  /// SDK wallet and signing methods contain no key material or real file.
  late final PublicationFixture publication;

  /// Every owner RPC is in memory and explicitly observed.
  late final OwnerCardPillarApi rpc;

  /// Uses the production read-ticket admission path.
  late final PillarsByOwnerBloc reader;

  /// Uses the production sender's reservation and original-result ownership.
  late final SendTransactionBloc sender;

  /// Retains transport until the case has changed the originating view.
  final Completer<AccountBlockTemplate> transport =
      Completer<AccountBlockTemplate>();

  /// Advances expiry without rebuilding or replacing the original authority.
  DateTime now = DateTime.utc(2026, 1, 2, 3, 4, 5);

  final _Balances _balances = _Balances();

  /// Starts a fresh read for the selected public fixture account.
  void read() => reader.add(FetchRequestData(address: emptyAddress));

  /// Releases only the fixture's owned resources, on its widget clock.
  Future<void> dispose(WidgetTester tester) async {
    try {
      await tester.pumpWidget(const SizedBox.shrink());
      rpc.finishFacts();
      if (!transport.isCompleted) transport.complete(publication.response);
      await tester.pump();
      // AccountBlockUtils retains its documented frontier-processing delay.
      await tester.pump(const Duration(seconds: 1));
      await finishOwnerBoundary(tester, sender.close());
      await finishOwnerBoundary(tester, reader.close());
      await finishOwnerBoundary(tester, publication.dispose());
    } finally {
      globals.restore();
      WalletContextRevision.invalidate();
      AppLottie.debugClear();
      BalanceVisibility.debugReset();
    }
  }
}

class _Bundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async => ByteData.sublistView(
    Uint8List.fromList(
      utf8.encode(
        jsonEncode(<String, Object>{
          'v': '5.7.4',
          'fr': 60,
          'ip': 0,
          'op': 120,
          'w': 64,
          'h': 64,
          'nm': 'Owner adapter fixture',
          'ddd': 0,
          'assets': <Object>[],
          'layers': <Object>[],
        }),
      ),
    ),
  );
}

/// Keeps the navigator alive when the originating owner card leaves.
class OwnerCardHost extends StatefulWidget {
  /// Uses fixture-owned providers so widget disposal cannot close the sender.
  const OwnerCardHost({required this.fixture, super.key});

  /// The reader and sender survive hiding or removing just the card.
  final OwnerCardFixture fixture;

  @override
  State<OwnerCardHost> createState() => OwnerCardHostState();
}

/// Exposes only the lifecycle changes a shell can apply to its owner card.
class OwnerCardHostState extends State<OwnerCardHost> {
  /// Routes stay accessible after the card itself is removed.
  final GlobalKey<NavigatorState> navigator = GlobalKey<NavigatorState>();

  final _Bundle _bundle = _Bundle();
  bool _visible = true;
  bool _attached = true;

  /// Counts only the adapter's explicit close callback.
  int closes = 0;

  /// Applies the same ticker visibility boundary as a retained Nodes body.
  void hide() => setState(() => _visible = false);

  /// Removes the originating adapter while retaining its navigator and sender.
  void detach() => setState(() => _attached = false);

  /// Rebuilds after a synchronous wallet-context change.
  void rebuild() => setState(() {});

  /// Completes owned questions even when an assertion interrupts their case.
  Future<void> closeRoutes(WidgetTester tester) async {
    final List<TransitionRoute<dynamic>> leaving = <TransitionRoute<dynamic>>[];
    navigator.currentState?.popUntil((Route<dynamic> route) {
      if (route.isFirst) return true;
      if (route is TransitionRoute<dynamic>) leaving.add(route);
      return false;
    });
    await tester.pump();
    for (final TransitionRoute<dynamic> route in leaving) {
      await tester.pump(route.reverseTransitionDuration);
      await tester.pump(const Duration(microseconds: 1));
      await finishOwnerBoundary(tester, route.completed.then<void>((_) {}));
    }
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    navigatorKey: navigator,
    theme: AppTheme.darkTheme,
    localizationsDelegates: appLocalizationsDelegates,
    supportedLocales: const <Locale>[Locale('en')],
    home: MultiBlocProvider(
      providers: <SingleChildWidget>[
        BlocProvider<PillarsByOwnerBloc>.value(value: widget.fixture.reader),
        BlocProvider<SendTransactionBloc>.value(value: widget.fixture.sender),
      ],
      child: DefaultAssetBundle(
        bundle: _bundle,
        child: Scaffold(
          body: SingleChildScrollView(
            child: TickerMode(
              enabled: _visible,
              child: _attached
                  ? PillarOwnerCard(
                      onClose: () {
                        closes++;
                        detach();
                      },
                      onStepperNotificationSeeMorePressed: () {},
                      nowForTesting: () => widget.fixture.now,
                    )
                  : const Text('Owner panel closed'),
            ),
          ),
        ),
      ),
    ),
  );
}

/// Advances event queues until an observable owned boundary, with a hard cap.
Future<void> pumpUntilOwner(
  WidgetTester tester,
  bool Function() reached, {
  required String reason,
}) async {
  for (int turn = 0; turn < 30 && !reached(); turn++) {
    await tester.pump();
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
  }
  expect(reached(), isTrue, reason: reason);
  await tester.pump();
}

/// Observes owned completion before awaiting it across the widget event queues.
Future<void> finishOwnerBoundary(
  WidgetTester tester,
  Future<void> operation,
) async {
  bool finished = false;
  Object? failure;
  StackTrace? trace;
  final Future<void> observed = operation.then<void>(
    (_) => finished = true,
    onError: (Object error, StackTrace stack) {
      failure = error;
      trace = stack;
      finished = true;
    },
  );
  await pumpUntilOwner(
    tester,
    () => finished,
    reason: 'The fixture must settle its owned asynchronous boundary',
  );
  await observed;
  if (failure != null) Error.throwWithStackTrace(failure!, trace!);
}
