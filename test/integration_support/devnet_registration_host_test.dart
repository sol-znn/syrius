import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:zenon_syrius_wallet_flutter/main.dart' as app;
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/multiple_balance/bloc/multiple_balance_bloc.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/registration_success/registration_confirmation.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/registration_success/registration_publisher.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/registration_success/registration_scope.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/send/bloc/send_transaction/send_transaction_bloc.dart';
import 'package:zenon_syrius_wallet_flutter/utils/account_block_utils.dart';
import 'package:zenon_syrius_wallet_flutter/utils/global.dart';
import 'package:zenon_syrius_wallet_flutter/utils/wallet_file.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

import '../../integration_test/support/devnet_registration_host.dart';
import '../helpers/hydrated_bloc.dart';

class _OfflineNode extends Mock implements Zenon {}

class _NoSignerFile extends Mock implements WalletFile {}

class _SharedBalances extends Mock implements MultipleBalanceBloc {}

class _ObservedSender extends SendTransactionBloc {
  int closeCalls = 0;
  Future<void>? closing;

  @override
  Future<void> close() {
    closeCalls++;
    return closing = super.close();
  }
}

Future<void> _finishOwnedClose(
  WidgetTester tester,
  Future<void> original,
) async {
  bool finished = false;
  Object? failure;
  StackTrace? failureStack;
  final Future<void> observed = original.then<void>(
    (_) {
      finished = true;
    },
    onError: (Object error, StackTrace stack) {
      failure = error;
      failureStack = stack;
      finished = true;
    },
  );
  for (int turn = 0; turn < 20 && !finished; turn++) {
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
  }
  expect(finished, isTrue, reason: 'The original close must actually finish');
  await observed;
  if (failure != null) {
    Error.throwWithStackTrace(failure!, failureStack!);
  }
}

void main() {
  initHydratedStorage();
  late Zenon? previousClient;
  late WalletFile? previousFile;
  late String? previousSelectedAddress;
  late _OfflineNode node;
  late _NoSignerFile file;
  late _SharedBalances balances;

  setUp(() {
    previousClient = app.zenon;
    previousFile = kWalletFile;
    previousSelectedAddress = kSelectedAddress;
    node = _OfflineNode();
    file = _NoSignerFile();
    balances = _SharedBalances();
    when(() => balances.stream).thenAnswer(
      (_) => const Stream<MultipleBalanceState>.empty(),
    );
    app.zenon = node;
    kWalletFile = file;
    kSelectedAddress = null;
  });

  tearDown(() {
    try {
      verifyNever(() => balances.close());
      verifyZeroInteractions(node);
      verifyZeroInteractions(file);
    } finally {
      app.zenon = previousClient;
      kWalletFile = previousFile;
      kSelectedAddress = previousSelectedAddress;
    }
  });

  testWidgets('default host provides a real sender above RegistrationScope', (
    WidgetTester tester,
  ) async {
    late SendTransactionBloc sender;
    late AccountBlockUtils publisher;
    try {
      await tester.pumpWidget(
        DevnetRegistrationHost(
          balances: balances,
          child: RegistrationScope(
            builder:
                (
                  RegistrationConfirmation confirmation,
                  AccountBlockUtils originalPublisher,
                ) => Builder(
                  builder: (BuildContext context) {
                    sender = context.read<SendTransactionBloc>();
                    publisher = originalPublisher;
                    expect(context.read<MultipleBalanceBloc>(), same(balances));
                    expect(confirmation.context, isNull);
                    return const SizedBox();
                  },
                ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(sender.runtimeType, SendTransactionBloc);
      expect(sender.isClosed, isFalse);
      expect(publisher, isA<RegistrationPublisher>());
      final BuildContext scopeContext = tester.element(
        find.byType(RegistrationScope),
      );
      expect(
        scopeContext.read<SendTransactionBloc>(),
        same(sender),
      );
    } finally {
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    }
    expect(sender.isClosed, isTrue);
  }, timeout: const Timeout(Duration(seconds: 60)));

  testWidgets('only host replacement or removal closes its original sender', (
    WidgetTester tester,
  ) async {
    final List<_ObservedSender> originals = <_ObservedSender>[];
    late SendTransactionBloc observedSender;
    late RegistrationConfirmation observedConfirmation;
    late AccountBlockUtils observedPublisher;

    Widget host({
      String owner = 'original',
      String scope = 'first',
      bool showScope = true,
    }) => DevnetRegistrationHost(
      key: ValueKey<String>(owner),
      balances: balances,
      createSender: () {
        final _ObservedSender sender = _ObservedSender();
        originals.add(sender);
        return sender;
      },
      child: showScope
          ? RegistrationScope(
              key: ValueKey<String>(scope),
              builder:
                  (
                    RegistrationConfirmation confirmation,
                    AccountBlockUtils publisher,
                  ) => Builder(
                    builder: (BuildContext context) {
                      observedSender = context.read<SendTransactionBloc>();
                      observedConfirmation = confirmation;
                      observedPublisher = publisher;
                      expect(
                        context.read<MultipleBalanceBloc>(),
                        same(balances),
                      );
                      return const SizedBox();
                    },
                  ),
            )
          : const SizedBox(),
    );

    try {
      await tester.pumpWidget(host());
      expect(originals, hasLength(1));
      final _ObservedSender original = originals.single;
      final RegistrationConfirmation confirmation = observedConfirmation;
      final AccountBlockUtils publisher = observedPublisher;
      final Object reservation = Object();
      expect(original.tryReserve(reservation), isTrue);

      await tester.pumpWidget(host());
      expect(originals, hasLength(1));
      expect(observedSender, same(original));
      expect(observedConfirmation, same(confirmation));
      expect(observedPublisher, same(publisher));
      expect(original.busy.value, isTrue);
      expect(original.closeCalls, 0);

      await tester.pumpWidget(host(scope: 'replacement'));
      expect(originals, hasLength(1));
      expect(observedSender, same(original));
      expect(observedConfirmation, isNot(same(confirmation)));
      expect(observedPublisher, isNot(same(publisher)));
      expect(original.busy.value, isTrue);
      expect(original.closeCalls, 0);

      await tester.pumpWidget(host(showScope: false));
      expect(originals, hasLength(1));
      expect(original.isClosed, isFalse);
      expect(original.closeCalls, 0);

      await tester.pumpWidget(host(owner: 'replacement'));
      await tester.pump();
      expect(originals, hasLength(2));
      expect(original.closeCalls, 1);
      expect(original.isClosed, isTrue);
      expect(original.closing, isNotNull);
      await _finishOwnedClose(tester, original.closing!);
      expect(observedSender, same(originals.last));
      expect(originals.last, isNot(same(original)));
      expect(originals.last.closeCalls, 0);
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    }

    expect(originals, hasLength(2));
    for (final _ObservedSender sender in originals) {
      expect(sender.closeCalls, 1);
      expect(sender.isClosed, isTrue);
      expect(sender.closing, isNotNull);
      await _finishOwnedClose(tester, sender.closing!);
    }
    await tester.pump();
    expect(
      originals.map((_ObservedSender sender) => sender.closeCalls),
      <int>[1, 1],
    );
  }, timeout: const Timeout(Duration(seconds: 60)));
}
