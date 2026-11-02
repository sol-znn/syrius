import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:zenon_syrius_wallet_flutter/blocs/auto_receive_tx_worker.dart';
import 'package:zenon_syrius_wallet_flutter/utils/original_publications.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

import '../../harness/app/agent.dart';
import '../../harness/app/fixtures/lab_quiescence.dart';
import '../../harness/app/fixtures/seed_policy.dart';
import '../helpers/hydrated_bloc.dart';
import '../receive_cell/support.dart';

Address _address(int value) => Address('z', <int>[
  0, 0, value, ...List<int>.filled(17, 7),
]);

final class _Case {
  _Case({AutoReceiveTxWorker? receiving})
      : worker = receiving ?? AutoReceiveTxWorker(),
        ownsWorker = receiving == null;

  final Object file = Object();
  final Object sdk = Object();
  final AutoReceiveTxWorker worker;
  final bool ownsWorker;
  final AccountBlockTemplate sent = AccountBlockTemplate.send(
    _address(1), znnZts, BigInt.from(100000000),
  )..address = _address(2)..chainIdentifier = 321..hash = receiveHash(9);
  late OriginalPublication<AccountBlockTemplate> original;
  late LabQuiescence binding;
  bool current = true;
  bool journalValid = true;
  int journalChecks = 0;

  SeedEnvironment get environment => SeedEnvironment(
    profile: 'quiescence-fixture', isolated: true, unlocked: true,
    initialized: true, booted: true, ws: seedWsOrigin, http: seedHttpOrigin,
    nodeChain: 321, signingChain: 321, selectedIndex: 1,
    owner: _address(2).toString(),
    members: <String>[_address(1).toString(), _address(2).toString()],
  );

  void requireCurrent() {
    if (!current) throw StateError('synthetic owner changed');
  }

  void requireJournal() {
    journalChecks++;
    if (!journalValid) throw StateError('synthetic journal changed');
  }

  LabQuiescence capture(AccountBlockTemplate block) => LabQuiescence(
    walletOwner: file, sdkOwner: sdk, worker: worker, environment: environment,
    originalSend: block, confirmedHash: sent.hash.toString(),
    requireCurrent: requireCurrent, requireJournal: requireJournal,
  );

  Future<void> prepare() async {
    if (ownsWorker) addTearDown(worker.dispose);
    await OriginalPublications.run<void>(file, (_) async {});
    final AccountBlockTemplate result = await OriginalPublications
        .runForOwners<AccountBlockTemplate>(<Object>[file, sdk],
          (OriginalPublication<AccountBlockTemplate> operation) {
      original = operation;
      operation.retainPublicationHash(sent.hash.toString());
      return Future<AccountBlockTemplate>.value(sent);
    });
    expect(result, same(sent));
    binding = capture(sent);
  }

  Future<AccountBlockTemplate> track(AccountBlockTemplate block) =>
      OriginalPublications.runForOwners<AccountBlockTemplate>(
        <Object>[file, sdk],
        (OriginalPublication<AccountBlockTemplate> operation) {
          operation.retainPublicationHash(block.hash.toString());
          return Future<AccountBlockTemplate>.value(block);
        });

  Future<void> pending(Completer<void> gate) {
    addTearDown(() { if (!gate.isCompleted) gate.complete(); });
    return OriginalPublications.run<void>(file, (_) => gate.future);
  }
}

void main() {
  initHydratedStorage();

  test('a positive original and successful void work close all admissions',
      () async {
    final _Case fixture = _Case();
    await fixture.prepare();
    final Map<String, Object> receipt = await fixture.binding.drain();
    expect(receipt, <String, Object>{
      'schema': 1, 'scope': 'owned_lab_quiescence', 'chain': 321,
      'complete': true, 'admission_closed': true,
      'original_send_confirmed': true, 'originals_positive': true,
      'file_operations': 2, 'sdk_publications': 1,
      'receive_reads': 0, 'receive_publications': 0,
    });
    expect(fixture.journalChecks, 3);
    expect(fixture.worker.isPaused, isTrue);
    expect(fixture.original.result, same(fixture.sent));
    for (final Object owner in <Object>[fixture.file, fixture.sdk]) {
      expect(() => OriginalPublications.run<void>(owner, (_) async {}),
        throwsA(isA<OriginalPublicationRefused>()));
    }
    expect(receipt.clear, throwsUnsupportedError);
  });

  test('actual pending file work settles before a receipt can complete',
      () async {
    final _Case fixture = _Case();
    await fixture.prepare();
    final Completer<void> gate = Completer<void>();
    final Future<void> original = fixture.pending(gate);
    final Future<Map<String, Object>> drain = fixture.binding.drain();
    bool done = false;
    unawaited(drain.then<void>((_) => done = true));
    await Future<void>.value();
    expect(done, isFalse);
    expect(fixture.worker.isPaused, isTrue);
    expect(() => OriginalPublications.run<void>(fixture.sdk, (_) async {}),
      throwsA(isA<OriginalPublicationRefused>()));
    gate.complete();
    await original;
    expect((await drain)['file_operations'], 3);
  });

  test('a settled SDK error remains a refusal even after completed drains',
      () async {
    final _Case fixture = _Case();
    await fixture.prepare();
    final StateError failure = StateError('synthetic SDK outcome');
    final Future<AccountBlockTemplate> original = OriginalPublications
        .runForOwners<AccountBlockTemplate>(<Object>[fixture.file, fixture.sdk],
          (_) => Future<AccountBlockTemplate>.error(failure));
    await expectLater(original, throwsA(same(failure)));
    final OriginalPublication<dynamic> held =
        OriginalPublications.snapshot(fixture.sdk).last;
    expect((await OriginalPublications.pauseAndDrain(fixture.sdk)).completed,
      isTrue);
    await expectLater(fixture.binding.drain(),
      throwsA(isA<LabQuiescenceRefused>()));
    expect(held.future, same(original));
    expect(held.error, same(failure));
    expect(held.acceptedHash, isNull);
  });

  test('a settled file error cannot be hidden by the positive send', () async {
    final _Case fixture = _Case();
    await fixture.prepare();
    final StateError failure = StateError('synthetic counter outcome');
    final Future<void> original = OriginalPublications.run<void>(fixture.file,
      (_) => Future<void>.error(failure));
    await expectLater(original, throwsA(same(failure)));
    await expectLater(fixture.binding.drain(),
      throwsA(isA<LabQuiescenceRefused>()));
    expect(OriginalPublications.snapshot(fixture.file).last.error,
      same(failure));
  });

  test('release failure retains the identical accepted result and refuses',
      () async {
    final _Case fixture = _Case();
    await fixture.prepare();
    final StateError failure = StateError('synthetic release outcome');
    fixture.original.recordReleaseFailure(failure, StackTrace.current);
    await expectLater(fixture.binding.drain(),
      throwsA(isA<LabQuiescenceRefused>()));
    expect(fixture.original.result, same(fixture.sent));
    expect(fixture.original.acceptedHash, fixture.sent.hash.toString());
    expect(fixture.original.releaseError, same(failure));
  });

  test('owner loss while waiting cannot revive the original captured lane',
      () async {
    final _Case fixture = _Case();
    await fixture.prepare();
    final Completer<void> gate = Completer<void>();
    final Future<void> original = fixture.pending(gate);
    final Future<void> refused = expectLater(fixture.binding.drain(),
      throwsA(isA<LabQuiescenceRefused>()));
    fixture.current = false;
    gate.complete();
    await original;
    await refused;
    fixture.current = true;
    await expectLater(fixture.binding.drain(),
      throwsA(isA<LabQuiescenceRefused>()));
  });

  test('a changed confirmation journal after waiting prevents completion',
      () async {
    final _Case fixture = _Case();
    await fixture.prepare();
    final Completer<void> gate = Completer<void>();
    final Future<void> original = fixture.pending(gate);
    final Future<void> refused = expectLater(fixture.binding.drain(),
      throwsA(isA<LabQuiescenceRefused>()));
    fixture.journalValid = false;
    gate.complete();
    await original;
    await refused;
    expect(fixture.worker.isPaused, isTrue);
  });

  test('another direct SDK send cannot borrow the original confirmation',
      () async {
    final _Case fixture = _Case();
    await fixture.prepare();
    final AccountBlockTemplate other =
        AccountBlockTemplate.fromJson(fixture.sent.toJson())
          ..hash = receiveHash(10);
    await fixture.track(other);
    await expectLater(fixture.binding.drain(),
      throwsA(isA<LabQuiescenceRefused>()));
    expect(OriginalPublications.snapshot(fixture.sdk), hasLength(2));
  });

  test('an equal block copy cannot substitute for the original result object',
      () async {
    final _Case fixture = _Case();
    await fixture.prepare();
    final AccountBlockTemplate copy =
        AccountBlockTemplate.fromJson(fixture.sent.toJson());
    expect(() => fixture.capture(copy),
      throwsA(isA<LabQuiescenceRefused>()));
    expect(fixture.worker.isPaused, isFalse);
  });

  test('changed original send terms refuse without another publication',
      () async {
    final _Case fixture = _Case();
    await fixture.prepare();
    fixture.sent.amount = BigInt.one;
    await expectLater(fixture.binding.drain(),
      throwsA(isA<LabQuiescenceRefused>()));
    expect(OriginalPublications.snapshot(fixture.sdk), hasLength(1));
  });

  test('a completed pause cannot be requested again through the binding',
      () async {
    final _Case fixture = _Case();
    await fixture.prepare();
    await fixture.binding.drain();
    final int checks = fixture.journalChecks;
    await expectLater(fixture.binding.drain(),
      throwsA(isA<LabQuiescenceRefused>()));
    expect(fixture.journalChecks, checks);
  });

  test('a real worker retains its positive inbound hold and exact SDK result',
      () async {
    final ReceiveFixture receive = ReceiveFixture();
    addTearDown(receive.close);
    final _Case fixture = _Case(receiving: receive.worker);
    await fixture.prepare();
    receive
      ..addresses = fixture.environment.members
      ..selectedAddress = fixture.environment.owner
      ..readInbound = (Hash hash) async => receiveInbound(hash,
        destination: _address(2));
    final List<Future<AccountBlockTemplate>> originals =
        <Future<AccountBlockTemplate>>[];
    receive.transport.reply = (ReceiveCall call) {
      final AccountBlockTemplate block = receive.transport.accepted(call);
      originals.add(fixture.track(block));
      return block;
    };
    final Hash inbound = receiveHash(1);
    final AccountBlockTemplate? block =
        await receive.worker.autoReceiveTransactionHash(inbound);
    await Future.wait(originals);
    await receiveTurnsUntil(() => !receive.worker.running);
    expect(receive.worker.inFlight.value, <Hash>{inbound});
    final Map<String, Object> receipt = await fixture.binding.drain();
    expect(receipt['sdk_publications'], 2);
    expect(receipt['receive_publications'], 1);
    expect(receive.worker.originals.single.result!.block, same(block));
    expect(receive.worker.inFlight.value, <Hash>{inbound});
  });

  test('an original receive failure stays held through the real worker drain',
      () async {
    final ReceiveFixture receive = ReceiveFixture();
    addTearDown(receive.close);
    final _Case fixture = _Case(receiving: receive.worker);
    await fixture.prepare();
    receive
      ..addresses = fixture.environment.members
      ..selectedAddress = fixture.environment.owner
      ..readInbound = (Hash hash) async => receiveInbound(hash,
        destination: _address(2));
    final StateError failure = StateError('synthetic receive outcome');
    receive.transport.failure = failure;
    await expectLater(receive.worker.autoReceiveTransactionHash(receiveHash(1)),
      throwsA(same(failure)));
    await receiveTurnsUntil(() => !receive.worker.running);
    final ReceiveRecord original = receive.worker.originals.single;
    await expectLater(fixture.binding.drain(),
      throwsA(isA<LabQuiescenceRefused>()));
    expect(receive.worker.originals.single, same(original));
    expect(original.error, same(failure));
  });

  test('a pending real inbound read is awaited and its failure is retained',
      () async {
    final ReceiveFixture receive = ReceiveFixture();
    addTearDown(receive.close);
    final _Case fixture = _Case(receiving: receive.worker);
    await fixture.prepare();
    receive
      ..addresses = fixture.environment.members
      ..selectedAddress = fixture.environment.owner;
    final Completer<AccountBlock?> proof = Completer<AccountBlock?>();
    receive.readInbound = (_) => proof.future;
    final StateError failure = StateError('synthetic inbound outcome');
    final Future<void> original = expectLater(
      receive.worker.autoReceiveTransactionHash(receiveHash(1)),
      throwsA(same(failure)));
    await receiveTurnsUntil(() => receive.proofReads == 1);
    bool done = false;
    final Future<void> drain = expectLater(fixture.binding.drain(),
      throwsA(isA<LabQuiescenceRefused>()));
    unawaited(drain.then<void>((_) => done = true));
    await Future<void>.value();
    expect(done, isFalse);
    expect(receive.worker.isPaused, isTrue);
    proof.completeError(failure);
    await original;
    await drain;
    expect(receive.worker.originals, isEmpty);
    expect(receive.transport.calls, isEmpty);
  });

  test('an agent without the live confirmed owner refuses a quiescence command',
      () async {
    final HarnessAgent agent = HarnessAgent.forTest();
    await expectLater(agent.commandForTest(<String, dynamic>{
      'cmd': 'lab-quiesce', 'profile': 'quiescence-fixture',
    }), throwsA(isA<HarnessError>()));
  });
}
