import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mocktail/mocktail.dart';
import 'package:zenon_syrius_wallet_flutter/l10n/app_localizations.dart';
import 'package:zenon_syrius_wallet_flutter/main.dart' as app;
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/features.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/segment.dart';
import 'package:zenon_syrius_wallet_flutter/utils/utils.dart';
import 'package:zenon_syrius_wallet_flutter/utils/wallet_file.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/reusable_widgets/buttons/primary_pill.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

import '../../integration_test/support/devnet_stake_host.dart';
import '../helpers/hydrated_bloc.dart';

class _Balances extends MockBloc<MultipleBalanceEvent, MultipleBalanceState>
    implements MultipleBalanceBloc {}

class _OfflineNode extends Mock implements Zenon {}

class _NoSignerFile extends Mock implements WalletFile {}

class _Selection extends SelectedAddressNotifier {
  int disposeCalls = 0;

  @override
  void dispose() {
    disposeCalls++;
    super.dispose();
  }
}

class _Sender extends SendTransactionBloc {
  int events = 0;
  int closeCalls = 0;
  Future<void>? closing;

  @override
  void add(SendTransactionEvent event) {
    events++;
    super.add(event);
  }

  @override
  Future<void> close() {
    closeCalls++;
    return closing = super.close();
  }
}

Future<void> _finishClose(WidgetTester tester, Future<void> original) async {
  bool finished = false;
  Object? failure;
  StackTrace? trace;
  final Future<void> observed = original.then<void>(
    (_) {
      finished = true;
    },
    onError: (Object error, StackTrace stack) {
      failure = error;
      trace = stack;
      finished = true;
    },
  );
  for (int turn = 0; turn < 20 && !finished; turn++) {
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
  }
  expect(finished, isTrue, reason: 'The original sender close must finish');
  await observed;
  if (failure != null) Error.throwWithStackTrace(failure!, trace!);
}

void main() {
  initHydratedStorage();
  const Key amountKey = Key('create_stake_amount_field');
  late _Balances balances;
  late StreamController<MultipleBalanceState> states;
  late Zenon? previousNode;
  late WalletFile? previousFile;
  late String? previousAddress;
  late _OfflineNode node;
  late _NoSignerFile file;
  final List<_Sender> senders = <_Sender>[];
  final List<_Selection> selections = <_Selection>[];

  setUp(() {
    previousNode = app.zenon;
    previousFile = kWalletFile;
    previousAddress = kSelectedAddress;
    node = _OfflineNode();
    file = _NoSignerFile();
    app.zenon = node;
    kWalletFile = file;
    kSelectedAddress = emptyAddress.toString();
    senders.clear();
    selections.clear();
    balances = _Balances();
    states = StreamController<MultipleBalanceState>.broadcast(sync: true);
    whenListen(
      balances,
      states.stream,
      initialState: MultipleBalanceState(
        status: MultipleBalanceStatus.success,
        data: <String, AccountInfo>{
          emptyAddress.toString(): AccountInfo(
            address: emptyAddress.toString(),
            blockCount: 1,
            balanceInfoList: <BalanceInfoListItem>[
              BalanceInfoListItem(
                token: kZnnCoin,
                balance:
                    BigInt.from(1000) * BigInt.from(10).pow(kZnnCoin.decimals),
              ),
            ],
          ),
        },
      ),
    );
  });

  tearDown(() async {
    try {
      verifyNever(() => balances.close());
      verifyZeroInteractions(node);
      verifyZeroInteractions(file);
    } finally {
      await states.close();
      app.zenon = previousNode;
      kWalletFile = previousFile;
      kSelectedAddress = previousAddress;
    }
  });

  Widget host({String owner = 'original', bool observeSelection = false}) =>
      MaterialApp(
        theme: AppTheme.darkTheme,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: DevnetStakeHost(
            key: ValueKey<String>(owner),
            balances: balances,
            createSelection: observeSelection
                ? () {
                    final _Selection selection = _Selection();
                    selections.add(selection);
                    return selection;
                  }
                : null,
            child: CreateStakeCard(
              createTransactionBloc: () {
                final _Sender sender = _Sender();
                senders.add(sender);
                return sender;
              },
              onStakeCreated: () {},
            ),
          ),
        ),
      );

  Future<void> mount(WidgetTester tester, Widget child) async {
    tester.view.physicalSize = const Size(1280, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(child);
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.takeException(), isNull);
    expect(find.byType(CreateStakeCard), findsOneWidget);
    expect(find.byKey(amountKey), findsOneWidget);
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    for (final _Sender sender in senders) {
      expect(sender.closeCalls, 1);
      expect(sender.closing, isNotNull);
      await _finishClose(tester, sender.closing!);
      expect(sender.isClosed, isTrue);
      expect(sender.events, 0);
    }
    for (final _Selection selection in selections) {
      expect(selection.disposeCalls, 1);
    }
    expect(tester.takeException(), isNull);
  }

  testWidgets('default stake host renders and selects the original control', (
    WidgetTester tester,
  ) async {
    try {
      await mount(tester, host());
      final BuildContext context = tester.element(find.byKey(amountKey));
      expect(context.read<MultipleBalanceBloc>(), same(balances));
      expect(
        context.read<SelectedAddressNotifier>().runtimeType,
        SelectedAddressNotifier,
      );
      expect(context.read<SendTransactionBloc>(), same(senders.single));
      await selectDevnetStakeDuration(tester, '6');
      await tester.enterText(find.byKey(amountKey), '300');
      await tester.pump();
      expect(
        tester.widget<Segment<int>>(find.byType(Segment<int>)).selected,
        6,
      );
      expect(
        tester
            .widget<PrimaryPill>(
              find.byKey(const Key('create_stake_submit_button')),
            )
            .onPressed,
        isNotNull,
      );
      expect(senders.single.events, 0);
    } finally {
      await unmount(tester);
    }
  }, timeout: const Timeout(Duration(seconds: 60)));

  testWidgets(
    'stake fixture rebuild retains owners '
    'and replacement disposes once',
    (WidgetTester tester) async {
      try {
        await mount(tester, host(observeSelection: true));
        final _Selection originalSelection = selections.single;
        final _Sender originalSender = senders.single;
        await selectDevnetStakeDuration(tester, '1');
        await tester.enterText(find.byKey(amountKey), '300');
        await tester.pump();
        final TextEditingController originalDraft = tester
            .widget<TextField>(find.byKey(amountKey))
            .controller!;
        await tester.pumpWidget(host(observeSelection: true));
        expect(selections, hasLength(1));
        expect(senders, hasLength(1));
        final BuildContext context = tester.element(find.byKey(amountKey));
        expect(
          context.read<SelectedAddressNotifier>(),
          same(originalSelection),
        );
        expect(context.read<SendTransactionBloc>(), same(originalSender));
        expect(
          tester.widget<TextField>(find.byKey(amountKey)).controller,
          same(originalDraft),
        );
        expect(originalDraft.text, '300');
        expect(
          tester.widget<Segment<int>>(find.byType(Segment<int>)).selected,
          1,
        );
        expect(originalSelection.disposeCalls, 0);
        expect(originalSender.closeCalls, 0);
        await tester.pumpWidget(
          host(owner: 'replacement', observeSelection: true),
        );
        await tester.pump();
        expect(selections, hasLength(2));
        expect(senders, hasLength(2));
        expect(originalSelection.disposeCalls, 1);
        expect(originalSender.closeCalls, 1);
        await _finishClose(tester, originalSender.closing!);
        expect(originalSender.isClosed, isTrue);
        verifyNever(() => balances.close());
      } finally {
        await unmount(tester);
      }
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );

  testWidgets('an unavailable month never selects or sends a stake', (
    WidgetTester tester,
  ) async {
    try {
      await mount(tester, host());
      await expectLater(
        selectDevnetStakeDuration(tester, '5'),
        throwsA(
          isA<StateError>().having(
            (StateError error) => error.message,
            'message',
            'The stake form does not offer the requested month',
          ),
        ),
      );
      expect(
        tester.widget<Segment<int>>(find.byType(Segment<int>)).selected,
        isNull,
      );
      expect(
        tester.widget<TextField>(find.byKey(amountKey)).controller!.text,
        isEmpty,
      );
      expect(senders.single.events, 0);
    } finally {
      await unmount(tester);
    }
  }, timeout: const Timeout(Duration(seconds: 60)));
}
