import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:mocktail/mocktail.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/send/send.dart';
import 'package:zenon_syrius_wallet_flutter/utils/utils.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

import '../../helpers/hydrated_bloc.dart';

class _Blocks extends Mock implements AccountBlockUtils {}

class _Balances extends Mock implements ZenonAddressUtils {}

class _Address extends Fake implements Address {}

class _Observer extends BlocObserver {
  final List<Object> errors = <Object>[];
  bool throwOnError = false;
  void Function()? onLoading;

  @override
  void onChange(BlocBase<dynamic> bloc, Change<dynamic> change) {
    super.onChange(bloc, change);
    final dynamic next = change.nextState;
    if (next is SendTransactionState &&
        next.status == SendTransactionStatus.loading) {
      onLoading?.call();
    }
  }

  @override
  void onError(BlocBase<dynamic> bloc, Object error, StackTrace stackTrace) {
    super.onError(bloc, error, stackTrace);
    errors.add(error);
    if (throwOnError) throw StateError('Diagnostic observer failed');
  }
}

void main() {
  initHydratedStorage();
  setUpAll(() {
    registerFallbackValue(AccountBlockTemplate(blockType: 1));
    registerFallbackValue(_Address());
  });

  final String from = Address(
    'z',
    <int>[0, 1, ...List<int>.filled(18, 7)],
  ).toString();
  final String to = Address(
    'z',
    <int>[0, 2, ...List<int>.filled(18, 9)],
  ).toString();
  late SendTransactionBloc sender;
  late Completer<void> started;
  late Completer<AccountBlockTemplate> publication;
  late Future<void> Function(String, String) record;
  late List<(String, String)> recipients;
  late _Observer observer;
  late BlocObserver previousObserver;

  setUp(() {
    previousObserver = Bloc.observer;
    observer = _Observer();
    Bloc.observer = observer;
    started = Completer<void>();
    publication = Completer<AccountBlockTemplate>();
    recipients = <(String, String)>[];
    record = (String sender, String recipient) async {
      recipients.add((sender, recipient));
    };
    final _Blocks blocks = _Blocks();
    final _Balances balances = _Balances();
    when(
      () => blocks.createAccountBlock(
        any(),
        any(),
        address: any(named: 'address'),
        waitForRequiredPlasma: any(named: 'waitForRequiredPlasma'),
      ),
    ).thenAnswer((_) {
      started.complete();
      return publication.future;
    });
    when(balances.refreshBalance).thenAnswer((_) {});
    sender = SendTransactionBloc(
      accountBlockUtilsHelper: blocks,
      zenonAddressUtils: balances,
      recordRecipient: (String from, String to) => record(from, to),
    );
  });

  tearDown(() async {
    if (!publication.isCompleted) {
      publication.complete(AccountBlockTemplate(blockType: 1));
    }
    try {
      await sender.close();
    } finally {
      Bloc.observer = previousObserver;
    }
  });

  SendTransactionInitiate transfer({Object? requestId}) =>
      SendTransactionInitiate(
        fromAddress: from,
        toAddress: to,
        amount: BigInt.parse('9007199254740993'),
        token: kZnnCoin,
        requestId: requestId,
      );

  Future<SendTransactionState> terminal() => sender.stream.firstWhere(
    (SendTransactionState state) =>
        state.status == SendTransactionStatus.success ||
        state.status == SendTransactionStatus.failure,
  );

  for (final String boundary in <String>['queued', 'busy', 'loading']) {
    test('$boundary revocation settles without starting transport', () async {
      bool current = true;
      void revokeOnBusy() {
        if (sender.busy.value) current = false;
      }

      if (boundary == 'busy') sender.busy.addListener(revokeOnBusy);
      if (boundary == 'loading') observer.onLoading = () => current = false;
      final SendRequestHandle handle = sender.trySubmitTransfer(
        transfer(requestId: Object()),
        canStart: () => current,
      )!;
      if (boundary == 'queued') current = false;
      final SendRequestResult result = await handle.result;
      expect(result.accepted, isFalse);
      expect(result.error, isA<StateError>());
      expect(started.isCompleted, isFalse);
      expect(recipients, isEmpty);
      expect(sender.busy.value, isFalse);
      sender.busy.removeListener(revokeOnBusy);
    });
  }

  test(
    'a throwing admission predicate settles the exact original error',
    () async {
      final StateError failure = StateError('Captured owner unavailable');
      final SendRequestHandle handle = sender.trySubmitTransfer(
        transfer(requestId: Object()),
        canStart: () => throw failure,
      )!;
      final SendRequestResult result = await handle.result;
      expect(result.error, same(failure));
      expect(started.isCompleted, isFalse);
      expect(sender.busy.value, isFalse);
    },
  );

  test('a closing predicate cannot start transport', () async {
    Future<void>? closing;
    final SendRequestHandle handle = sender.trySubmitTransfer(
      transfer(requestId: Object()),
      canStart: () {
        closing = sender.close();
        return true;
      },
    )!;
    final SendRequestResult result = await handle.result;
    await closing!;
    expect(result.accepted, isFalse);
    expect(result.error, isA<StateError>());
    expect(started.isCompleted, isFalse);
    expect(recipients, isEmpty);
  });

  test(
    'a typed transfer handle retains exact acceptance through close',
    () async {
      final Object identity = Object();
      expect(sender.trySubmitTransfer(transfer()), isNull);
      final SendRequestHandle handle = sender.trySubmitTransfer(
        transfer(requestId: identity),
      )!;
      expect(handle.requestId, same(identity));
      expect(sender.trySubmitTransfer(transfer(requestId: Object())), isNull);
      await started.future;
      final Future<void> closing = sender.close();
      final AccountBlockTemplate accepted = AccountBlockTemplate(blockType: 1);
      publication.complete(accepted);
      final SendRequestResult result = await handle.result;
      expect(result.accepted, isTrue);
      expect(result.block, same(accepted));
      await closing;
      expect(recipients, <(String, String)>[(from, to)]);
      expect(sender.trySubmitTransfer(transfer(requestId: Object())), isNull);
    },
  );

  test('records only after the original transfer is accepted', () async {
    final Future<SendTransactionState> result = terminal();
    sender.add(transfer());
    await started.future;
    expect(recipients, isEmpty);
    // Overlap is refused and cannot replace the admitted recipient.
    sender.add(
      SendTransactionInitiate(
        fromAddress: to,
        toAddress: from,
        amount: BigInt.one,
        token: kQsrCoin,
      ),
    );
    final AccountBlockTemplate accepted = AccountBlockTemplate(blockType: 1);
    publication.complete(accepted);
    expect((await result).data, same(accepted));
    expect(recipients, <(String, String)>[(from, to)]);
    expect(sender.busy.value, isFalse);
  });

  test('an uncertain failed publication never marks its recipient', () async {
    final Future<SendTransactionState> result = terminal();
    sender.add(transfer());
    await started.future;
    final StateError failure = StateError('Publication outcome unknown');
    publication.completeError(failure);
    expect((await result).status, SendTransactionStatus.failure);
    expect(recipients, isEmpty);
    expect(observer.errors, contains(same(failure)));
  });

  for (final SendTransactionOrigin origin in <SendTransactionOrigin>[
    SendTransactionOrigin.contract,
    SendTransactionOrigin.collection,
  ]) {
    test('$origin acceptance does not create a recent transfer', () async {
      final Future<SendTransactionState> result = terminal();
      sender.add(
        SendTransactionInitiateFromBlock(
          block: AccountBlockTemplate(blockType: 1),
          fromAddress: from,
          reasonForGeneratingPlasma: 'Collect',
          origin: origin,
        ),
      );
      await started.future;
      publication.complete(AccountBlockTemplate(blockType: 1));
      expect((await result).status, SendTransactionStatus.success);
      expect(recipients, isEmpty);
    });
  }

  test('original acceptance still records while close drains', () async {
    sender.add(transfer());
    await started.future;
    final Future<void> closing = sender.close();
    publication.complete(AccountBlockTemplate(blockType: 1));
    await closing;
    expect(recipients, <(String, String)>[(from, to)]);
  });

  test('a slow storage observer cannot hold an accepted send busy', () async {
    final Completer<void> storage = Completer<void>();
    record = (String sender, String recipient) {
      recipients.add((sender, recipient));
      return storage.future;
    };
    final Future<SendTransactionState> result = terminal();
    sender.add(transfer());
    await started.future;
    final AccountBlockTemplate accepted = AccountBlockTemplate(blockType: 1);
    publication.complete(accepted);
    try {
      expect((await result).data, same(accepted));
      expect(sender.busy.value, isFalse);
      await sender.close();
      expect(recipients, <(String, String)>[(from, to)]);
      expect(storage.isCompleted, isFalse);
    } finally {
      storage.complete();
    }
  });

  for (final bool asynchronous in <bool>[false, true]) {
    test(
      'storage and diagnostic failures preserve acceptance $asynchronous',
      () async {
        final StateError failure = StateError('Storage unavailable');
        observer.throwOnError = true;
        record = (_, _) {
          if (asynchronous) return Future<void>.error(failure);
          throw failure;
        };
        final Future<SendTransactionState> result = terminal();
        sender.add(transfer());
        await started.future;
        final AccountBlockTemplate accepted = AccountBlockTemplate(
          blockType: 1,
        );
        publication.complete(accepted);
        expect((await result).data, same(accepted));
        await Future<void>.delayed(Duration.zero);
        expect(sender.state.status, SendTransactionStatus.success);
        expect(sender.state.data, same(accepted));
        expect(sender.busy.value, isFalse);
        expect(observer.errors, contains(same(failure)));
      },
    );
  }

  test('closing an unstarted request never records it', () async {
    sender.add(transfer());
    await sender.close();
    expect(started.isCompleted, isFalse);
    expect(recipients, isEmpty);
  });
}
