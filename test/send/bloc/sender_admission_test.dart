import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:mocktail/mocktail.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/send/send.dart';
import 'package:zenon_syrius_wallet_flutter/utils/utils.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

import '../../helpers/hydrated_bloc.dart';

class _BlockUtils extends Mock implements AccountBlockUtils {}

class _AddressUtils extends Mock implements ZenonAddressUtils {}

class _AsyncAddressUtils extends Mock implements ZenonAddressUtils {
  final Completer<void> refresh = Completer<void>();

  @override
  Future<void> refreshBalance() => refresh.future;
}

class _Address extends Fake implements Address {}

@immutable
class _EqualIdentity {
  const _EqualIdentity(this.value);

  final int value;

  @override
  bool operator ==(Object other) =>
      other is _EqualIdentity && other.value == value;

  @override
  int get hashCode => value.hashCode;
}

class _SenderObserver extends BlocObserver {
  void Function()? eventAction;
  void Function(Change<dynamic>)? changeAction;
  void Function(Object)? errorAction;

  @override
  void onEvent(Bloc<dynamic, dynamic> bloc, Object? event) {
    super.onEvent(bloc, event);
    eventAction?.call();
  }

  @override
  void onChange(BlocBase<dynamic> bloc, Change<dynamic> change) {
    super.onChange(bloc, change);
    changeAction?.call(change);
  }

  @override
  void onError(BlocBase<dynamic> bloc, Object error, StackTrace stackTrace) {
    super.onError(bloc, error, stackTrace);
    errorAction?.call(error);
  }
}

void main() {
  initHydratedStorage();

  setUpAll(() {
    registerFallbackValue(AccountBlockTemplate(blockType: 1));
    registerFallbackValue(_Address());
  });

  late SendTransactionBloc sender;
  late _BlockUtils blocks;
  late _AddressUtils addresses;
  late _SenderObserver observer;
  late BlocObserver previousObserver;
  late FlutterExceptionHandler? previousFlutterError;
  late Future<AccountBlockTemplate> Function(AccountBlockTemplate) publish;
  late List<Completer<AccountBlockTemplate>> pending;
  late int publicationCount;

  setUp(() {
    previousObserver = Bloc.observer;
    previousFlutterError = FlutterError.onError;
    observer = _SenderObserver();
    Bloc.observer = observer;
    blocks = _BlockUtils();
    addresses = _AddressUtils();
    pending = <Completer<AccountBlockTemplate>>[];
    publicationCount = 0;
    publish = (AccountBlockTemplate block) async => block;
    when(
      () => blocks.createAccountBlock(
        any(),
        any(),
        address: any(named: 'address'),
        waitForRequiredPlasma: any(named: 'waitForRequiredPlasma'),
      ),
    ).thenAnswer((Invocation invocation) {
      publicationCount++;
      return publish(
        invocation.positionalArguments.first as AccountBlockTemplate,
      );
    });
    when(() => addresses.refreshBalance()).thenAnswer((_) {});
    sender = SendTransactionBloc(
      accountBlockUtilsHelper: blocks,
      zenonAddressUtils: addresses,
    );
  });

  tearDown(() async {
    observer
      ..eventAction = null
      ..changeAction = null
      ..errorAction = null;
    FlutterError.onError = previousFlutterError;
    for (final Completer<AccountBlockTemplate> operation in pending) {
      if (!operation.isCompleted) {
        operation.complete(AccountBlockTemplate(blockType: 1));
      }
    }
    try {
      await sender.close();
    } finally {
      Bloc.observer = previousObserver;
    }
  });

  SendTransactionEvent legacyEvent({required bool fromBlock}) => fromBlock
      ? SendTransactionInitiateFromBlock(
          block: AccountBlockTemplate(blockType: 1),
          fromAddress: emptyAddress.toString(),
          reasonForGeneratingPlasma: 'Collect',
        )
      : SendTransactionInitiate(
          fromAddress: emptyAddress.toString(),
          toAddress: emptyAddress.toString(),
          amount: BigInt.one,
          token: kZnnCoin,
        );

  SendRequestHandle? submit(
    Object owner, {
    Object? requestId,
    AccountBlockTemplate? block,
  }) => sender.trySubmitOwned(
    owner: owner,
    requestId: requestId ?? Object(),
    block: block ?? AccountBlockTemplate(blockType: 1),
    fromAddress: emptyAddress.toString(),
    reasonForGeneratingPlasma: 'Collect',
  );

  Completer<AccountBlockTemplate> defer(Completer<void> started) {
    final Completer<AccountBlockTemplate> operation =
        Completer<AccountBlockTemplate>();
    pending.add(operation);
    publish = (_) {
      if (!started.isCompleted) started.complete();
      return operation.future;
    };
    return operation;
  }

  Future<SendTransactionState> success() => sender.stream.firstWhere(
    (SendTransactionState state) =>
        state.status == SendTransactionStatus.success,
  );

  for (final bool fromBlock in <bool>[false, true]) {
    test('legacy $fromBlock admits synchronously and drops overlap', () async {
      final Completer<void> started = Completer<void>();
      final Completer<AccountBlockTemplate> operation = defer(started);
      final Future<SendTransactionState> completed = success();
      sender.add(legacyEvent(fromBlock: fromBlock));
      expect(sender.busy.value, isTrue);
      expect(sender.tryReserve(Object()), isFalse);
      sender.add(legacyEvent(fromBlock: !fromBlock));
      expect(submit(Object()), isNull);
      await started.future;
      expect(publicationCount, 1);
      final AccountBlockTemplate response = AccountBlockTemplate(blockType: 1);
      operation.complete(response);
      final SendTransactionState result = await completed;
      expect(result.data, same(response));
      expect(
        result.origin,
        fromBlock
            ? SendTransactionOrigin.contract
            : SendTransactionOrigin.transfer,
      );
      expect(sender.busy.value, isFalse);
      await Future<void>.delayed(Duration.zero);
      expect(publicationCount, 1);
      final Future<SendTransactionState> next = success();
      sender.add(legacyEvent(fromBlock: !fromBlock));
      await next;
      expect(publicationCount, 2);
    });
  }

  test(
    'exact owner holds both legacy types and gaps between requests',
    () async {
      final _EqualIdentity owner = _EqualIdentity(publicationCount);
      final _EqualIdentity impostor = _EqualIdentity(publicationCount);
      expect(owner, equals(impostor));
      expect(sender.tryReserve(owner), isTrue);
      expect(sender.tryReserve(owner), isFalse);
      expect(submit(impostor), isNull);
      sender.releaseReservation(impostor);
      expect(sender.busy.value, isTrue);
      sender
        ..add(legacyEvent(fromBlock: false))
        ..add(legacyEvent(fromBlock: true));
      final Object requestId = Object();
      final AccountBlockTemplate firstBlock = AccountBlockTemplate(
        blockType: 1,
      );
      final SendRequestHandle first = submit(
        owner,
        requestId: requestId,
        block: firstBlock,
      )!;
      final SendRequestResult firstResult = await first.result;
      expect(first.requestId, same(requestId));
      expect(firstResult.accepted, isTrue);
      expect(firstResult.block, same(firstBlock));
      expect(sender.state.requestId, same(requestId));
      expect(sender.state.origin, SendTransactionOrigin.collection);
      expect(sender.busy.value, isTrue);
      expect(sender.tryReserve(impostor), isFalse);
      sender
        ..add(legacyEvent(fromBlock: false))
        ..add(legacyEvent(fromBlock: true));
      final AccountBlockTemplate secondBlock = AccountBlockTemplate(
        blockType: 1,
      );
      final SendRequestHandle second = submit(
        owner,
        requestId: requestId,
        block: secondBlock,
      )!;
      final SendRequestResult secondResult = await second.result;
      expect(secondResult.block, same(secondBlock));
      expect(await first.result, same(firstResult));
      expect(firstResult.block, same(firstBlock));
      expect(publicationCount, 2);
      sender.releaseReservation(owner);
      expect(sender.busy.value, isFalse);
      final Future<SendTransactionState> completed = success();
      sender.add(legacyEvent(fromBlock: true));
      await completed;
      expect(publicationCount, 3);
    },
  );

  test('release during publication keeps the hold until its outcome', () async {
    final Object owner = Object();
    final Object nextOwner = Object();
    final Completer<void> started = Completer<void>();
    final Completer<AccountBlockTemplate> operation = defer(started);
    expect(sender.tryReserve(owner), isTrue);
    final SendRequestHandle handle = submit(owner)!;
    await started.future;
    sender.releaseReservation(owner);
    expect(sender.busy.value, isTrue);
    expect(submit(owner), isNull);
    expect(sender.tryReserve(nextOwner), isFalse);
    sender
      ..add(legacyEvent(fromBlock: false))
      ..add(legacyEvent(fromBlock: true));
    final AccountBlockTemplate response = AccountBlockTemplate(blockType: 1);
    operation.complete(response);
    expect((await handle.result).block, same(response));
    expect(publicationCount, 1);
    expect(sender.busy.value, isFalse);
    expect(sender.tryReserve(nextOwner), isTrue);
    sender.releaseReservation(owner);
    expect(sender.busy.value, isTrue);
    sender.releaseReservation(nextOwner);
    expect(sender.busy.value, isFalse);
  });

  test('close revokes an owned request before its handler starts', () async {
    final Object owner = Object();
    final Object requestId = Object();
    expect(sender.tryReserve(owner), isTrue);
    final SendRequestHandle handle = submit(owner, requestId: requestId)!;
    final Future<void> closing = sender.close();
    final SendRequestResult result = await handle.result;
    await closing;
    expect(handle.requestId, same(requestId));
    expect(result.accepted, isFalse);
    expect(result.block, isNull);
    expect(result.error, isA<StateError>());
    expect(publicationCount, 0);
    expect(sender.tryReserve(Object()), isFalse);
    expect(submit(owner), isNull);
  });

  test('a busy listener can close a queued legacy request safely', () async {
    Future<void>? closing;
    sender.busy.addListener(() {
      if (sender.busy.value) closing ??= sender.close();
    });
    expect(() => sender.add(legacyEvent(fromBlock: false)), returnsNormally);
    expect(closing, isNotNull);
    await closing!;
    expect(publicationCount, 0);
    expect(sender.isClosed, isTrue);
  });

  test('reservation reports refusal when its busy listener closes', () async {
    Future<void>? closing;
    sender.busy.addListener(() {
      if (sender.busy.value) closing ??= sender.close();
    });
    expect(sender.tryReserve(Object()), isFalse);
    await closing!;
    expect(publicationCount, 0);
  });

  test('close from an enqueue observer revokes without dispatch', () async {
    Future<void>? closing;
    observer.eventAction = () => closing ??= sender.close();
    final Object owner = Object();
    expect(sender.tryReserve(owner), isTrue);
    final SendRequestHandle handle = submit(owner)!;
    final SendRequestResult result = await handle.result;
    await closing!;
    expect(result.accepted, isFalse);
    expect(result.error, isA<StateError>());
    expect(publicationCount, 0);
  });

  test('enqueue observer failure settles only its owned handle', () async {
    final StateError failure = StateError('Enqueue observer failed');
    observer.eventAction = () => throw failure;
    final Object owner = Object();
    expect(sender.tryReserve(owner), isTrue);
    final SendRequestResult result = await submit(owner)!.result;
    expect(result.accepted, isFalse);
    expect(result.error, same(failure));
    expect(publicationCount, 0);
    expect(sender.busy.value, isTrue);
    sender.releaseReservation(owner);
    expect(sender.busy.value, isFalse);
    observer.eventAction = null;
    final Future<SendTransactionState> completed = success();
    sender.add(legacyEvent(fromBlock: false));
    await completed;
    expect(publicationCount, 1);
  });

  for (final bool fromBlock in <bool>[false, true]) {
    test('legacy $fromBlock rolls back an enqueue observer failure', () async {
      observer.eventAction = () => throw StateError('Enqueue observer failed');
      expect(
        () => sender.add(legacyEvent(fromBlock: fromBlock)),
        returnsNormally,
      );
      expect(sender.busy.value, isFalse);
      expect(publicationCount, 0);
      observer.eventAction = null;
      final Future<SendTransactionState> completed = success();
      sender.add(legacyEvent(fromBlock: fromBlock));
      await completed;
      expect(publicationCount, 1);
    });
  }

  test('close from a loading observer cannot start publication', () async {
    Future<void>? closing;
    observer.changeAction = (Change<dynamic> change) {
      final SendTransactionState next =
          change.nextState as SendTransactionState;
      if (next.status == SendTransactionStatus.loading) {
        closing ??= sender.close();
      }
    };
    final Object owner = Object();
    expect(sender.tryReserve(owner), isTrue);
    final SendRequestResult result = await submit(owner)!.result;
    await closing!;
    expect(result.accepted, isFalse);
    expect(result.error, isA<StateError>());
    expect(publicationCount, 0);
  });

  test('close waits for the exact accepted response of started work', () async {
    final Completer<void> started = Completer<void>();
    final Completer<AccountBlockTemplate> operation = defer(started);
    final Object owner = Object();
    expect(sender.tryReserve(owner), isTrue);
    final SendRequestHandle handle = submit(owner)!;
    await started.future;
    bool closed = false;
    final Future<void> closing = sender.close().then<void>((_) {
      closed = true;
    });
    expect(sender.close(), same(sender.close()));
    await Future<void>.delayed(Duration.zero);
    expect(closed, isFalse);
    expect(sender.busy.value, isTrue);
    final AccountBlockTemplate response = AccountBlockTemplate(blockType: 1);
    operation.complete(response);
    final SendRequestResult result = await handle.result;
    await closing;
    expect(closed, isTrue);
    expect(result.accepted, isTrue);
    expect(result.block, same(response));
    expect(result.error, isNull);
    expect(await handle.result, same(result));
    expect(publicationCount, 1);
  });

  test('close retains the exact original Error of started work', () async {
    final Completer<void> started = Completer<void>();
    final Completer<AccountBlockTemplate> operation = defer(started);
    final Object failure = StateError('Original publication failed');
    observer.errorAction = (_) =>
        throw StateError('Diagnostic observer failed');
    final Object owner = Object();
    expect(sender.tryReserve(owner), isTrue);
    final SendRequestHandle handle = submit(owner)!;
    await started.future;
    bool closed = false;
    final Future<void> closing = sender.close().then<void>((_) {
      closed = true;
    });
    await Future<void>.delayed(Duration.zero);
    expect(closed, isFalse);
    operation.completeError(failure, StackTrace.current);
    final SendRequestResult result = await handle.result;
    await closing;
    expect(result.accepted, isFalse);
    expect(result.block, isNull);
    expect(result.error, same(failure));
    expect(await handle.result, same(result));
    expect(publicationCount, 1);
  });

  test('started legacy work also drains before close completes', () async {
    final Completer<void> started = Completer<void>();
    final Completer<AccountBlockTemplate> operation = defer(started);
    sender.add(legacyEvent(fromBlock: true));
    await started.future;
    bool closed = false;
    final Future<void> closing = sender.close().then<void>((_) {
      closed = true;
    });
    await Future<void>.delayed(Duration.zero);
    expect(closed, isFalse);
    operation.complete(AccountBlockTemplate(blockType: 1));
    await closing;
    expect(publicationCount, 1);
    expect(closed, isTrue);
  });

  test('refresh, display and diagnostic failures retain acceptance', () async {
    final StateError refreshFailure = StateError('Refresh failed');
    final StateError displayFailure = StateError('Display failed');
    final List<Object> reported = <Object>[];
    when(() => addresses.refreshBalance()).thenThrow(refreshFailure);
    observer
      ..changeAction = (Change<dynamic> change) {
        final SendTransactionState next =
            change.nextState as SendTransactionState;
        if (next.status == SendTransactionStatus.success) throw displayFailure;
      }
      ..errorAction = (Object error) {
        reported.add(error);
        throw StateError('Diagnostic observer failed');
      };
    final Object owner = Object();
    final AccountBlockTemplate response = AccountBlockTemplate(blockType: 1);
    expect(sender.tryReserve(owner), isTrue);
    final SendRequestResult result = await submit(
      owner,
      block: response,
    )!.result;
    await Future<void>.delayed(Duration.zero);
    expect(result.accepted, isTrue);
    expect(result.block, same(response));
    expect(result.error, isNull);
    expect(reported, contains(same(refreshFailure)));
    expect(reported, contains(same(displayFailure)));
    expect(publicationCount, 1);
  });

  test(
    'a later asynchronous refresh failure cannot replace acceptance',
    () async {
      await sender.close();
      final _AsyncAddressUtils asynchronous = _AsyncAddressUtils();
      addTearDown(() {
        if (!asynchronous.refresh.isCompleted) asynchronous.refresh.complete();
      });
      sender = SendTransactionBloc(
        accountBlockUtilsHelper: blocks,
        zenonAddressUtils: asynchronous,
      );
      final List<Object> reported = <Object>[];
      observer.errorAction = reported.add;
      final Object owner = Object();
      final AccountBlockTemplate response = AccountBlockTemplate(blockType: 1);
      expect(sender.tryReserve(owner), isTrue);
      final SendRequestHandle handle = submit(owner, block: response)!;
      final SendRequestResult result = await handle.result;
      expect(result.accepted, isTrue);
      final Object failure = StateError('Asynchronous refresh failed');
      asynchronous.refresh.completeError(failure, StackTrace.current);
      await Future<void>.delayed(Duration.zero);
      expect(reported, contains(same(failure)));
      expect(await handle.result, same(result));
      expect(result.block, same(response));
      expect(result.error, isNull);
      expect(publicationCount, 1);
    },
  );

  test('idle listener failures cannot strand a completed outcome', () async {
    final Object owner = Object();
    expect(sender.tryReserve(owner), isTrue);
    FlutterError.onError = (_) =>
        throw StateError('Framework diagnostic failed');
    observer.errorAction = (_) =>
        throw StateError('Diagnostic observer failed');
    int idleNotifications = 0;
    void idleListener() {
      if (!sender.busy.value) throw StateError('Idle observer failed');
    }

    void healthyListener() {
      if (!sender.busy.value) idleNotifications++;
    }

    sender.busy
      ..addListener(idleListener)
      ..addListener(healthyListener);
    addTearDown(() {
      sender.busy
        ..removeListener(idleListener)
        ..removeListener(healthyListener);
    });
    final Completer<void> started = Completer<void>();
    final Completer<AccountBlockTemplate> operation = defer(started);
    final SendRequestHandle handle = submit(owner)!;
    await started.future;
    sender.releaseReservation(owner);
    final AccountBlockTemplate response = AccountBlockTemplate(blockType: 1);
    operation.complete(response);
    final SendRequestResult result = await handle.result;
    expect(result.accepted, isTrue);
    expect(result.block, same(response));
    expect(sender.busy.value, isFalse);
    expect(idleNotifications, 1);
    expect(sender.tryReserve(Object()), isTrue);
    await sender.close();
    expect(sender.isClosed, isTrue);
    expect(idleNotifications, 2);
  });

  test('busy listeners preserve duplicate registration and removal', () {
    int notifications = 0;
    void listener() => notifications++;
    final Object owner = Object();
    sender.busy
      ..addListener(listener)
      ..addListener(listener);
    expect(sender.tryReserve(owner), isTrue);
    expect(notifications, 2);
    sender.busy.removeListener(listener);
    sender.releaseReservation(owner);
    expect(notifications, 3);
    sender.busy.removeListener(listener);
    expect(sender.tryReserve(owner), isTrue);
    sender.releaseReservation(owner);
    expect(notifications, 3);
  });

  test('a busy listener can remove itself without skipping another', () {
    final List<String> notifications = <String>[];
    void selfRemoving() {
      notifications.add('Self');
      sender.busy.removeListener(selfRemoving);
    }

    void following() => notifications.add('Following');
    sender.busy
      ..addListener(selfRemoving)
      ..addListener(following);
    final Object owner = Object();
    expect(sender.tryReserve(owner), isTrue);
    expect(notifications, <String>['Self', 'Following']);
    sender.releaseReservation(owner);
    expect(notifications, <String>['Self', 'Following', 'Following']);
    sender.busy.removeListener(following);
  });

  test('hydrated JSON excludes live identities and display ownership', () {
    const SendTransactionState live = SendTransactionState(
      status: SendTransactionStatus.loading,
      requestId: Object(),
      origin: SendTransactionOrigin.collection,
    );
    final Map<String, dynamic> json = sender.toJson(live)!;
    expect(json, isNot(contains('requestId')));
    expect(json, isNot(contains('origin')));
    expect(json, isNot(contains('owner')));
    expect(() => jsonEncode(json), returnsNormally);
    final SendTransactionState restored = sender.fromJson(json)!;
    expect(restored.requestId, isNull);
    expect(restored.origin, SendTransactionOrigin.transfer);
  });
}
