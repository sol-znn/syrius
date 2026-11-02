import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/fuse_plasma/fuse_plasma.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/plasma_owner/plasma_fuse_publisher.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/plasma_owner/plasma_owner_controller.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/plasma_owner/plasma_session.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/exceptions/exceptions.dart';
import 'package:zenon_syrius_wallet_flutter/utils/address_utils.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

import '../helpers/hydrated_bloc.dart';
import 'support.dart';

class _Zenon extends Mock implements Zenon {}

class _Balances extends ZenonAddressUtils {
  @override
  void refreshBalance() {}
}

PlasmaFusePublisher _publisher(
  PlasmaFixture fixture,
  PlasmaSession session, {
  BigInt? amount,
}) => PlasmaFusePublisher(
  sender: fixture.sender,
  session: session,
  beneficiary: emptyAddress.toString(),
  amount: amount ?? BigInt.from(1000000000),
  isCurrent: () => fixture.visible,
);

Future<AccountBlockTemplate> _fuse(PlasmaFusePublisher publisher) {
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

  test(
    'fractional raw QSR is preserved exactly through fresh account proof',
    () async {
      final PlasmaFixture fixture = PlasmaFixture();
      addTearDown(fixture.close);
      final BigInt raw = BigInt.from(1000000001);
      final PlasmaFusePublisher publisher = _publisher(
        fixture,
        fixture.session(),
        amount: raw,
      );
      final AccountBlockTemplate result = await _fuse(publisher);
      expect(result.amount, raw);
      expect(fixture.transport.calls.single.block.amount, raw);
      expect(
        fixture.transport.calls.single.address.toString(),
        emptyAddress.toString(),
      );
      final PlasmaFuseOutcome outcome = PlasmaFusePublisher.outcomesFor(
        fixture.sender,
      ).single;
      expect(outcome.amount, raw);
      expect(outcome.accepted, isTrue);
      expect(outcome.publicationHash, plasmaTestHash(1000));
    },
  );

  test(
    'fresh available balance cannot be replaced by a stale form balance',
    () async {
      final PlasmaFixture fixture = PlasmaFixture();
      addTearDown(fixture.close);
      fixture.accountRead = () async => AccountInfo(
        address: emptyAddress.toString(),
        blockCount: 0,
        balanceInfoList: const <BalanceInfoListItem>[],
      );
      await expectLater(
        _fuse(_publisher(fixture, fixture.session())),
        throwsA(isA<FailureException>()),
      );
      expect(fixture.transport.calls, isEmpty);
      expect(fixture.sender.busy.value, isFalse);
    },
  );

  test(
    'Fuse and cancellation use one shell reservation in both directions',
    () async {
      final PlasmaFixture fixture = PlasmaFixture();
      addTearDown(fixture.close);
      await fixture.loadAll();
      final Completer<AccountInfo> account = Completer<AccountInfo>();
      fixture.accountRead = () => account.future;
      final PlasmaFusePublisher publisher = _publisher(
        fixture,
        fixture.session(),
      );
      final Future<AccountBlockTemplate> fuse = _fuse(publisher);
      expect(fixture.sender.busy.value, isTrue);
      expect(
        fixture.owner.beginCancellation(
          session: fixture.session(),
          hash: plasmaTestHash(1),
          isCurrent: () => true,
        ),
        isNull,
      );
      account.complete(
        AccountInfo(
          address: emptyAddress.toString(),
          blockCount: 0,
          balanceInfoList: const <BalanceInfoListItem>[],
        ),
      );
      await expectLater(fuse, throwsA(isA<FailureException>()));

      fixture.accountRead = null;
      fixture.transport.deferred = true;
      final PlasmaCancelIntent intent = fixture.intent(hash: plasmaTestHash(1));
      final Future<PlasmaTransportCall> started = fixture.transport.next;
      final Future<PlasmaCancellationBatch?> cancel = fixture.owner.cancel(
        intent,
      );
      await started.timeout(const Duration(seconds: 2));
      await expectLater(
        _fuse(_publisher(fixture, fixture.session())),
        throwsA(isA<FailureException>()),
      );
      expect(fixture.transport.calls.length, 1);
      fixture.transport.completeNext();
      expect((await cancel)!.submitted, 1);
    },
  );

  test(
    'duplicate callbacks and changed block arguments cannot send twice',
    () async {
      final PlasmaFixture fixture = PlasmaFixture();
      addTearDown(fixture.close);
      fixture.transport.deferred = true;
      final PlasmaFusePublisher publisher = _publisher(
        fixture,
        fixture.session(),
      );
      final Future<PlasmaTransportCall> started = fixture.transport.next;
      final Future<AccountBlockTemplate> operation = _fuse(publisher);
      await started.timeout(const Duration(seconds: 2));
      expect(_fuse(publisher), same(operation));
      fixture.transport.completeNext();
      await operation;
      expect(_fuse(publisher), same(operation));
      final PlasmaFusePublisher other = _publisher(fixture, fixture.session());
      final AccountBlockTemplate changed = other.session.fuseBlock(
        other.beneficiary,
        other.amount,
      )..amount += BigInt.one;
      await expectLater(
        other.createAccountBlock(changed, 'Fixture Fuse'),
        throwsA(isA<FailureException>()),
      );
      expect(fixture.transport.calls.length, 1);
    },
  );

  test(
    'Fuse preparation refuses context revocation without publishing',
    () async {
      final PlasmaFixture fixture = PlasmaFixture();
      addTearDown(fixture.close);
      fixture.transport.preparation = Completer<void>();
      final Future<PlasmaTransportCall> started = fixture.transport.next;
      final Future<AccountBlockTemplate> operation = _fuse(
        _publisher(fixture, fixture.session()),
      );
      final Future<void> checked = expectLater(
        operation,
        throwsA(same(fixture.transport.preparationError)),
      );
      await started.timeout(const Duration(seconds: 2));
      fixture.revision += 2;
      fixture.transport.preparation!.complete();
      await checked;
      expect(fixture.transport.published, 0);
      final PlasmaFuseOutcome original = PlasmaFusePublisher.outcomesFor(
        fixture.sender,
      ).single;
      expect(original.accepted, isFalse);
      expect(original.result.error, same(fixture.transport.preparationError));
    },
  );

  test(
    'accepted Fuse survives form disposal and retains its exact hash',
    () async {
      final PlasmaFixture fixture = PlasmaFixture();
      addTearDown(fixture.close);
      fixture.transport.deferred = true;
      final Future<PlasmaTransportCall> started = fixture.transport.next;
      final Future<AccountBlockTemplate> operation = _fuse(
        _publisher(fixture, fixture.session()),
      );
      final PlasmaTransportCall call = await started.timeout(
        const Duration(seconds: 2),
      );
      fixture.visible = false;
      fixture.revision++;
      final AccountBlockTemplate original = fixture.transport.accepted(call);
      fixture.transport.completeNext(response: original);
      expect(await operation, same(original));
      original.hash = Hash.parse(plasmaTestHash(9999));
      final PlasmaFuseOutcome outcome = PlasmaFusePublisher.outcomesFor(
        fixture.sender,
      ).single;
      expect(outcome.publicationHash, plasmaTestHash(1000));
      expect(outcome.accepted, isTrue);
      expect(outcome.result.block, same(original));
    },
  );

  test('an arbitrary Error produces a terminal Fuse BLoC failure', () async {
    final PlasmaFixture fixture = PlasmaFixture();
    addTearDown(fixture.close);
    fixture.accountRead = () async =>
        throw StateError('Fixture account failure');
    final FusePlasmaBloc bloc = FusePlasmaBloc(
      accountBlockUtils: fixture.transport,
      zenon: _Zenon(),
      zenonAddressUtils: _Balances(),
      sender: fixture.sender,
    );
    addTearDown(bloc.close);
    final Future<FusePlasmaState> terminal = bloc.stream.firstWhere(
      (FusePlasmaState state) => state is FusePlasmaFailure,
    );
    bloc.add(
      FusePlasmaRequested(
        beneficiaryAddress: emptyAddress.toString(),
        amount: BigInt.from(1000000000),
        session: fixture.session(),
      ),
    );
    expect(
      await terminal.timeout(const Duration(seconds: 2)),
      isA<FusePlasmaFailure>(),
    );
    expect(fixture.transport.calls, isEmpty);
    expect(fixture.sender.busy.value, isFalse);
  });
}
