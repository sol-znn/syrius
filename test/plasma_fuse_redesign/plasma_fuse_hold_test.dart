import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/fuse_plasma/fuse_plasma.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/plasma_owner/plasma_fuse_publisher.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/plasma_owner/plasma_session.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/exceptions/exceptions.dart';
import 'package:zenon_syrius_wallet_flutter/utils/address_utils.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

import '../helpers/hydrated_bloc.dart';
import '../plasma_redesign/support.dart';
import 'support.dart';

class _Zenon extends Mock implements Zenon {}

class _Balances extends ZenonAddressUtils {
  @override
  void refreshBalance() {}
}

FusePlasmaBloc _bloc(FuseFixture fixture) => FusePlasmaBloc(
  accountBlockUtils: fixture.transport,
  zenon: _Zenon(),
  zenonAddressUtils: _Balances(),
  sender: fixture.sender,
);

PlasmaFusePublisher _publisher(
  FuseFixture fixture,
  PlasmaSession session, {
  BigInt? amount,
  String? beneficiary,
  PlasmaFuseDraft? draft,
}) => PlasmaFusePublisher(
  sender: fixture.sender,
  session: session,
  beneficiary: beneficiary ?? emptyAddress.toString(),
  amount: amount ?? BigInt.from(1000000001),
  isCurrent: () => fixture.visible,
  draft: draft,
);

Future<AccountBlockTemplate> _start(PlasmaFusePublisher publisher) {
  final AccountBlockTemplate block = publisher.session.fuseBlock(
    publisher.beneficiary,
    publisher.amount,
  );
  expect(
    block.chainIdentifier,
    publisher.session.chainId,
    reason: 'The offline builder must use its captured session chain',
  );
  return publisher.createAccountBlock(block, 'Fixture Fuse');
}

void main() {
  initHydratedStorage();

  test('one original future survives duplicate publishers '
      'and changed payloads', () async {
    final FuseFixture fixture = FuseFixture();
    addTearDown(fixture.close);
    final PlasmaSession session = fixture.confirmedSession();
    fixture.transport.deferred = true;
    final PlasmaFusePublisher first = _publisher(fixture, session);
    final Future<PlasmaTransportCall> started = fixture.transport.next;
    final Future<AccountBlockTemplate> original = _start(first);
    final Future<void> originalError = expectLater(
      original,
      throwsA(isA<StateError>()),
    );
    await started.timeout(const Duration(seconds: 1));
    final PlasmaFusePublisher reopened = _publisher(fixture, session);
    expect(_start(reopened), same(original));
    await expectLater(
      _start(_publisher(fixture, session, amount: BigInt.from(2000000001))),
      throwsA(isA<FailureException>()),
    );
    final StateError error = StateError('Synthetic original Fuse uncertainty');
    fixture.transport.completeNext(error: error);
    await originalError;
    await expectLater(_start(reopened), throwsA(same(error)));
    await expectLater(
      _start(
        _publisher(
          fixture,
          session,
          beneficiary: tokenAddress.toString(),
        ),
      ),
      throwsA(same(error)),
    );
    final PlasmaFuseOutcome outcome = PlasmaFusePublisher.outcomesFor(
      fixture.sender,
    ).single;
    expect(outcome.result.error, same(error));
    expect(outcome.accepted, isFalse);
    expect(fixture.transport.calls, hasLength(1));
    expect(
      PlasmaFusePublisher.another(
        sender: fixture.sender,
        session: session,
        isCurrent: () => true,
      ),
      isNull,
    );
  });

  test('known pre-admission failure needs a new publisher '
      'and fresh account proof', () async {
    final FuseFixture fixture = FuseFixture();
    addTearDown(fixture.close);
    final StateError unavailable = StateError('Synthetic fresh account read');
    fixture.accountRead = () async => throw unavailable;
    final PlasmaFusePublisher first = _publisher(
      fixture,
      fixture.confirmedSession(),
    );
    final Future<AccountBlockTemplate> refused = _start(first);
    await expectLater(refused, throwsA(same(unavailable)));
    expect(PlasmaFusePublisher.outcomesFor(fixture.sender), isEmpty);
    expect(fixture.sender.busy.value, isFalse);
    fixture.accountRead = null;
    final AccountBlockTemplate accepted = await _start(
      _publisher(fixture, fixture.confirmedSession()),
    );
    expect(_start(first), same(refused));
    await expectLater(_start(first), throwsA(same(unavailable)));
    expect(fixture.transport.calls, hasLength(1));
    expect(
      PlasmaFusePublisher.outcomesFor(fixture.sender).single.result.block,
      same(accepted),
    );
  });

  test('only exact confirmation and explicit Another grant '
      'a new draft', () async {
    final FuseFixture fixture = FuseFixture();
    addTearDown(fixture.close);
    final PlasmaSession session = fixture.confirmedSession();
    final PlasmaFuseDraft firstDraft = PlasmaFusePublisher.beginDraft(
      sender: fixture.sender,
      session: session,
      isCurrent: () => true,
    )!;
    final PlasmaFusePublisher first = _publisher(
      fixture,
      session,
      draft: firstDraft,
    );
    final Future<AccountBlockTemplate> original = _start(first);
    final AccountBlockTemplate accepted = await original;
    final PlasmaFuseOutcome outcome = first.outcome!;
    final String hash = outcome.publicationHash!;
    expect(
      fixture.registry.published(accepted, <String>[session.address]),
      isTrue,
    );
    expect(PlasmaFusePublisher.canRearm(fixture.sender, session), isFalse);
    await fixture.flight.check();
    expect(PlasmaFusePublisher.canRearm(fixture.sender, session), isFalse);
    final Hash unrelated = Hash.parse(plasmaTestHash(9000));
    fixture.flight
      ..sent(hash: unrelated, amount: BigInt.zero)
      ..settle(unrelated);
    expect(PlasmaFusePublisher.canRearm(fixture.sender, session), isFalse);
    fixture.confirmationError = StateError('Synthetic confirmation read');
    await fixture.flight.check();
    expect(PlasmaFusePublisher.canRearm(fixture.sender, session), isFalse);
    fixture.confirmationError = null;
    fixture.confirmedHashes.add(hash);
    fixture.confirmationChain = 1;
    await fixture.flight.check();
    expect(PlasmaFusePublisher.canRearm(fixture.sender, session), isFalse);
    fixture.confirmationChain = 321;
    await fixture.flight.check();
    expect(PlasmaFusePublisher.canRearm(fixture.sender, session), isTrue);
    expect(
      session.confirmsOriginal(hash, tokenAddress.toString(), 321),
      isFalse,
    );
    expect(session.confirmsOriginal(hash, session.address, 1), isFalse);
    // A positive fact alone never replaces the original hold or future.
    expect(_start(_publisher(fixture, session)), same(original));
    final PlasmaFuseDraft nextDraft = PlasmaFusePublisher.another(
      sender: fixture.sender,
      session: session,
      isCurrent: () => true,
    )!;
    final PlasmaFusePublisher next = _publisher(
      fixture,
      session,
      amount: BigInt.from(2000000001),
      draft: nextDraft,
    );
    final AccountBlockTemplate second = await _start(next);
    expect(second, isNot(same(accepted)));
    expect(fixture.transport.calls, hasLength(2));
    expect(_start(first), same(original));
    expect(
      _start(_publisher(fixture, session, draft: firstDraft)),
      same(original),
    );
    final List<PlasmaFuseOutcome> archive = PlasmaFusePublisher.outcomesFor(
      fixture.sender,
    );
    expect(archive, hasLength(2));
    expect(archive.first, same(outcome));
    expect(archive.first.result.block, same(accepted));
    expect(archive.last.result.block, same(second));
    expect(archive.clear, throwsUnsupportedError);
    accepted.hash = Hash.parse(plasmaTestHash(7777));
    expect(outcome.publicationHash, hash);
  });

  test('an observed rearm grant cannot survive a departed opening', () async {
    final FuseFixture fixture = FuseFixture();
    addTearDown(fixture.close);
    final PlasmaSession session = fixture.confirmedSession();
    final PlasmaFusePublisher first = _publisher(fixture, session);
    final Future<AccountBlockTemplate> original = _start(first);
    final AccountBlockTemplate accepted = await original;
    fixture.registry.published(accepted, <String>[session.address]);
    fixture.confirmedHashes.add(first.outcome!.publicationHash!);
    await fixture.flight.check();
    int epoch = 0;
    final int captured = epoch;
    final PlasmaFuseDraft next = PlasmaFusePublisher.another(
      sender: fixture.sender,
      session: session,
      isCurrent: () => captured == epoch,
    )!;
    epoch += 2;
    await expectLater(
      _start(
        _publisher(
          fixture,
          session,
          draft: next,
          amount: BigInt.from(2000000001),
        ),
      ),
      throwsA(isA<FailureException>()),
    );
    expect(_start(first), same(original));
    expect(fixture.transport.calls, hasLength(1));
  });

  test('a returned page cannot revive its original deferred proof', () async {
    final FuseFixture fixture = FuseFixture();
    addTearDown(fixture.close);
    final PlasmaSession session = fixture.confirmedSession();
    final Completer<AccountInfo> proof = Completer<AccountInfo>();
    fixture.accountRead = () => proof.future;
    int epoch = 0;
    final int opening = epoch;
    final PlasmaFusePublisher publisher = PlasmaFusePublisher(
      sender: fixture.sender,
      session: session,
      beneficiary: session.address,
      amount: BigInt.from(1000000001),
      isCurrent: () => opening == epoch,
    );
    final Future<void> refused = expectLater(
      _start(publisher),
      throwsA(isA<FailureException>()),
    );
    expect(fixture.sender.busy.value, isTrue);
    epoch += 2;
    fixture.accountRead = null;
    proof.complete(await session.readAccount());
    await refused;
    expect(fixture.transport.calls, isEmpty);
    expect(PlasmaFusePublisher.outcomesFor(fixture.sender), isEmpty);
    expect(fixture.sender.busy.value, isFalse);
    await _start(_publisher(fixture, session));
    expect(fixture.transport.calls, hasLength(1));
  });

  test('admitted error survives BLoC closure '
      'and a changed new event', () async {
    final FuseFixture fixture = FuseFixture();
    addTearDown(fixture.close);
    final FusePlasmaBloc first = _bloc(fixture);
    fixture.transport.deferred = true;
    final Future<PlasmaTransportCall> started = fixture.transport.next;
    final Future<PlasmaTransportCall> refused = first.stream
        .firstWhere((FusePlasmaState state) => state is FusePlasmaFailure)
        .then((FusePlasmaState state) {
          final FusePlasmaFailure failure = state as FusePlasmaFailure;
          Error.throwWithStackTrace(
            failure.error ?? failure.exception,
            StackTrace.current,
          );
        });
    first.add(
      FusePlasmaRequested(
        beneficiaryAddress: emptyAddress.toString(),
        amount: BigInt.from(1000000001),
        session: fixture.confirmedSession(),
      ),
    );
    await Future.any<PlasmaTransportCall>(<Future<PlasmaTransportCall>>[
      started,
      refused,
    ]).timeout(const Duration(seconds: 1));
    final Future<void> closed = first.close();
    final StateError error = StateError('Synthetic original SDK uncertainty');
    fixture.transport.completeNext(error: error);
    await closed.timeout(const Duration(seconds: 1));
    final PlasmaFuseOutcome original = first.lastOutcome!;
    expect(original.result.error, same(error));
    final FusePlasmaBloc reopened = _bloc(fixture);
    addTearDown(reopened.close);
    final Future<FusePlasmaState> terminal = reopened.stream.firstWhere(
      (FusePlasmaState state) => state is FusePlasmaFailure,
    );
    reopened.add(
      FusePlasmaRequested(
        beneficiaryAddress: tokenAddress.toString(),
        amount: BigInt.from(2000000001),
        session: fixture.confirmedSession(),
      ),
    );
    final FusePlasmaFailure failure =
        await terminal.timeout(const Duration(seconds: 1)) as FusePlasmaFailure;
    expect(failure.error, same(error));
    expect(failure.outcome, same(original));
    expect(reopened.lastOutcome, same(original));
    expect(PlasmaFusePublisher.outcomesFor(fixture.sender), <PlasmaFuseOutcome>[
      original,
    ]);
    expect(fixture.transport.calls, hasLength(1));
  });
}
