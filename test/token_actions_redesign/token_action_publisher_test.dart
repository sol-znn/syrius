import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/send/bloc/send_transaction/send_transaction_bloc.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/tokens/actions/token_action_publisher.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

import '../helpers/hydrated_bloc.dart';
import 'support.dart';

void main() {
  initHydratedStorage();
  late ActionFixture fixture;
  setUp(() => fixture = ActionFixture());
  tearDown(() => fixture.close());

  test(
    'mint retains the native block and separate exact requested units',
    () async {
      final BigInt units = BigInt.parse('9007199254740993123456789');
      final TokenActionIntent intent = await fixture.intent(amount: units);
      late AccountBlockTemplate accepted;
      fixture.transport.reply = (ActionCall call) =>
          accepted = fixture.transport.accepted(call);
      final TokenActionOutcome outcome = await fixture.publisher.publish(
        intent,
      );
      expect(outcome.status, TokenActionStatus.submitted);
      expect(outcome.block, same(accepted));
      expect(outcome.result!.block, same(accepted));
      expect(accepted.amount, BigInt.zero);
      expect(outcome.requestedMintAmount, units);
      expect(fixture.mints.single.$2, units);
      expect(fixture.tokenReads, 2);
      expect(fixture.accountReads, 2);
    },
  );

  test(
    'fresh proof holds the shared sender and prevents competing admission',
    () async {
      final TokenActionIntent intent = await fixture.intent();
      final Completer<Token?> proof = Completer<Token?>();
      fixture.tokenRead = (_) => proof.future;
      final Future<TokenActionOutcome> pending = fixture.publisher.publish(
        intent,
      );
      await actionTurnsUntil(() => fixture.tokenReads == 2);
      expect(fixture.sender.busy.value, isTrue);
      expect(fixture.sender.tryReserve(Object()), isFalse);
      expect(fixture.transport.calls, isEmpty);
      proof.complete(fixture.token);
      expect((await pending).status, TokenActionStatus.submitted);
      expect(fixture.sender.busy.value, isFalse);
    },
  );

  test(
    'supply, max, owner and flags are freshly checked after confirmation',
    () async {
      final TokenActionIntent original = await fixture.intent(
        amount: fixture.token.maxSupply - fixture.token.totalSupply,
      );
      fixture.token = Token.fromJson(fixture.token.toJson())
        ..totalSupply += BigInt.one;
      final TokenActionOutcome refused = await fixture.publisher.publish(
        original,
      );
      expect(refused.status, TokenActionStatus.refused);
      expect(fixture.transport.calls, isEmpty);
      final TokenActionIntent fresh = await fixture.intent();
      fixture.token = actionToken(owner: tokenAddress);
      expect(
        (await fixture.publisher.publish(fresh)).status,
        TokenActionStatus.refused,
      );
      expect(fixture.transport.calls, isEmpty);
    },
  );

  test(
    'burn refuses a balance that changed below the frozen requested units',
    () async {
      final TokenActionIntent intent = await fixture.intent(
        mode: TokenActionMode.burn,
        amount: fixture.balance,
      );
      fixture.balance -= BigInt.one;
      expect(
        (await fixture.publisher.publish(intent)).status,
        TokenActionStatus.refused,
      );
      expect(fixture.burns, isEmpty);
      expect(fixture.transport.calls, isEmpty);
    },
  );

  test(
    'ownership transfer preserves the original freshly verified flags',
    () async {
      fixture.token = actionToken(burnable: false);
      final TokenActionIntent intent = await fixture.intent(
        mode: TokenActionMode.transfer,
        receiver: tokenAddress.toString(),
      );
      final TokenActionOutcome outcome = await fixture.publisher.publish(
        intent,
      );
      expect(outcome.status, TokenActionStatus.submitted);
      expect(fixture.transfers.single, (true, false, tokenAddress.toString()));
      final TokenActionIntent other = await fixture.intent(
        mode: TokenActionMode.transfer,
      );
      fixture.token = actionToken();
      expect(
        await fixture.publisher.publish(other),
        same(outcome),
      );
      expect(fixture.transfers, hasLength(1));
    },
  );

  test('Flags has no builder or publication path', () async {
    final TokenActionIntent intent = await fixture.intent(
      mode: TokenActionMode.flags,
      amount: BigInt.zero,
    );
    expect(
      (await fixture.publisher.publish(intent)).status,
      TokenActionStatus.refused,
    );
    expect(fixture.transport.calls, isEmpty);
    expect(fixture.transfers, isEmpty);
  });

  test(
    'preparation rechecks the captured presentation through canPublish',
    () async {
      final TokenActionIntent intent = await fixture.intent();
      final Completer<void> gate = Completer<void>();
      fixture.transport.preparation = gate;
      final Future<TokenActionOutcome> pending = fixture.publisher.publish(
        intent,
      );
      await actionTurnsUntil(() => fixture.transport.calls.isNotEmpty);
      fixture.visible = false;
      gate.complete();
      final TokenActionOutcome outcome = await pending;
      expect(outcome.status, TokenActionStatus.unknown);
      expect(outcome.error, same(outcome.result!.error));
      expect(fixture.transport.published, 0);
      fixture.visible = true;
      expect(intent.isCurrent, isFalse);
      expect(
        await fixture.publisher.publish(await fixture.intent()),
        same(outcome),
      );
    },
  );

  test(
    'a reentrant loading observer revokes canStart before transport',
    () async {
      final BlocObserver previous = Bloc.observer;
      late final ActionFixture observed;
      int revocations = 0;
      Bloc.observer = _LoadingObserver(() {
        revocations++;
        observed.visible = false;
      });
      try {
        // Bloc captures its observer at construction, before any loading emit.
        observed = ActionFixture();
        final TokenActionIntent intent = await observed.intent();
        final TokenActionOutcome outcome = await observed.publisher.publish(
          intent,
        );
        // canStart follows loading observers; the original error stays held.
        expect(outcome.status, TokenActionStatus.unknown);
        expect(revocations, 1);
        expect(observed.transport.calls, isEmpty);
        expect(observed.transport.published, 0);
        expect(outcome.error, isA<StateError>());
        expect(outcome.error, same(outcome.result!.error));
        expect(
          TokenActionPublisher.originalOutcomesFor(observed.sender).single,
          same(outcome),
        );
        observed.visible = true;
        expect(intent.isCurrent, isFalse);
        expect(
          await observed.publisher.publish(await observed.intent()),
          same(outcome),
        );
        expect(observed.transport.calls, isEmpty);
      } finally {
        Bloc.observer = previous;
        await observed.close();
      }
    },
  );

  test(
    'late accepted result survives disposal and duplicate concurrent callers',
    () async {
      fixture.transport.deferred = true;
      final TokenActionIntent intent = await fixture.intent();
      final Future<TokenActionOutcome> first = fixture.publisher.publish(
        intent,
      );
      final Future<TokenActionOutcome> duplicate = fixture.publisher.publish(
        intent,
      );
      await actionTurnsUntil(() => fixture.transport.pending.isNotEmpty);
      final AccountBlockTemplate accepted = fixture.transport.accepted(
        fixture.transport.calls.single,
      );
      fixture
        ..visible = false
        ..active = false;
      fixture.transport.complete(block: accepted);
      final TokenActionOutcome outcome = await first;
      expect(outcome.status, TokenActionStatus.submitted);
      expect(outcome.block, same(accepted));
      expect(await duplicate, same(outcome));
      expect(fixture.publisher.lastOutcome, same(outcome));
      expect(fixture.transport.calls, hasLength(1));
    },
  );

  test(
    'the original generic error is retained and uncertainty is never retried',
    () async {
      final StateError error = StateError('Synthetic original outcome');
      fixture.transport.error = error;
      final TokenActionOutcome outcome = await fixture.publisher.publish(
        await fixture.intent(),
      );
      expect(outcome.status, TokenActionStatus.unknown);
      expect(outcome.error, same(error));
      expect(outcome.result!.error, same(error));
      fixture.transport.error = null;
      final TokenActionPublisher reopened = TokenActionPublisher(
        sender: fixture.sender,
        session: fixture.session,
      );
      expect(await reopened.publish(await fixture.intent()), same(outcome));
      expect(fixture.transport.calls, hasLength(1));
    },
  );

  test(
    'only a successful fresh proof rearms a known pre-admission refusal',
    () async {
      final TokenActionIntent original = await fixture.intent();
      final Object competing = Object();
      expect(fixture.sender.tryReserve(competing), isTrue);
      final TokenActionOutcome refusal = await fixture.publisher.publish(
        original,
      );
      fixture.sender.releaseReservation(competing);
      expect(refusal.status, TokenActionStatus.refused);
      expect(await fixture.publisher.publish(original), same(refusal));
      expect(fixture.transport.calls, isEmpty);
      expect(
        (await fixture.publisher.publish(await fixture.intent())).status,
        TokenActionStatus.submitted,
      );
    },
  );

  test('uncertainty holds edits across publishers and modes', () async {
    final StateError original = StateError('Synthetic uncertain publication');
    fixture.transport.error = original;
    final TokenActionOutcome outcome = await fixture.publisher.publish(
      await fixture.intent(),
    );
    fixture.transport.error = null;
    final TokenActionPublisher reopened = fixture.reopenPublisher();
    for (final TokenActionMode mode in <TokenActionMode>[
      TokenActionMode.mint,
      TokenActionMode.burn,
      TokenActionMode.transfer,
    ]) {
      final TokenActionIntent edited = await fixture.intent(
        mode: mode,
        amount: mode == TokenActionMode.transfer ? BigInt.zero : BigInt.two,
        receiver: tokenAddress.toString(),
      );
      expect(await reopened.publish(edited), same(outcome));
      expect(outcome.belongsTo(edited), isFalse);
    }
    expect(reopened.canStartAnother(outcome), isFalse);
    expect(outcome.error, same(original));
    expect(fixture.transport.calls, hasLength(1));
    expect(
      TokenActionPublisher.originalOutcomesFor(fixture.sender),
      <TokenActionOutcome>[outcome],
    );
  });

  test('a held token does not block a different exact ZTS', () async {
    fixture.transport.error = StateError('Synthetic uncertain first token');
    final TokenActionOutcome original = await fixture.publisher.publish(
      await fixture.intent(),
    );
    fixture
      ..token = actionToken(id: 2)
      ..transport.error = null;
    final TokenActionOutcome other = await fixture.publisher.publish(
      await fixture.intent(),
    );
    expect(original.status, TokenActionStatus.unknown);
    expect(other.status, TokenActionStatus.submitted);
    expect(fixture.transport.calls, hasLength(2));
  });

  test('Another needs exact confirmation and a new proof', () async {
    final TokenActionIntent intent = await fixture.intent();
    final TokenActionIntent unused = await fixture.intent(amount: BigInt.two);
    final TokenActionOutcome original = await fixture.publisher.publish(intent);
    final TokenActionIntent heldRead = await fixture.intent(
      receiver: tokenAddress.toString(),
    );
    expect(fixture.publisher.canStartAnother(original), isFalse);
    expect(
      await fixture.publisher.another(original, isCurrent: () => true),
      isNull,
    );
    fixture.flights
      ..sent(hash: Hash.parse(actionHash(999)), amount: BigInt.one)
      ..settle(Hash.parse(actionHash(999)));
    expect(fixture.publisher.canStartAnother(original), isFalse);
    fixture.confirm(original);
    expect(fixture.publisher.canStartAnother(original), isTrue);
    fixture.flights.invalidateEvidence();
    expect(fixture.publisher.canStartAnother(original), isFalse);
    fixture.confirm(original);
    final TokenActionProof fresh = (await fixture.publisher.another(
      original,
      isCurrent: () => true,
    ))!;
    expect(identical(fresh.ticket, intent.proof.ticket), isFalse);
    expect(await fixture.publisher.publish(intent), same(original));
    expect(await fixture.publisher.publish(unused), same(original));
    expect(await fixture.publisher.publish(heldRead), same(original));
    final TokenActionIntent next = TokenActionIntent(
      proof: fresh,
      mode: TokenActionMode.mint,
      amount: BigInt.from(3),
      receiver: emptyAddress.toString(),
      isCurrent: () => true,
    );
    final TokenActionOutcome second = await fixture.publisher.publish(next);
    expect(second.status, TokenActionStatus.submitted);
    expect(second.belongsTo(next), isTrue);
    expect(fixture.transport.calls, hasLength(2));
    final List<TokenActionOutcome> journal =
        TokenActionPublisher.originalOutcomesFor(fixture.sender);
    expect(journal, <TokenActionOutcome>[original, second]);
    expect(journal.first.result, same(original.result));
  });

  test('an old pending read cannot consume a later Another rearm', () async {
    final TokenActionOutcome original = await fixture.publisher.publish(
      await fixture.intent(),
    );
    final Completer<Token?> delayed = Completer<Token?>();
    addTearDown(() {
      if (!delayed.isCompleted) delayed.complete(fixture.token);
    });
    fixture.tokenRead = (_) => delayed.future;
    final Future<TokenActionProof> oldRead = fixture.publisher.read(
      fixture.token.tokenStandard,
    );
    fixture
      ..tokenRead = null
      ..confirm(original);
    final TokenActionProof fresh = (await fixture.publisher.another(
      original,
      isCurrent: () => true,
    ))!;
    delayed.complete(fixture.token);
    final TokenActionProof old = await oldRead;
    final TokenActionIntent stale = TokenActionIntent(
      proof: old,
      mode: TokenActionMode.mint,
      amount: BigInt.two,
      receiver: tokenAddress.toString(),
      isCurrent: () => true,
    );
    expect(await fixture.publisher.publish(stale), same(original));
    final TokenActionIntent next = TokenActionIntent(
      proof: fresh,
      mode: TokenActionMode.burn,
      amount: BigInt.one,
      receiver: null,
      isCurrent: () => true,
    );
    expect(
      (await fixture.publisher.publish(next)).status,
      TokenActionStatus.submitted,
    );
    expect(fixture.transport.calls, hasLength(2));
  });

  test('confirmation cannot rearm another owner or signing chain', () async {
    final TokenActionOutcome original = await fixture.publisher.publish(
      await fixture.intent(),
    );
    fixture.confirm(original);
    final int reads = fixture.tokenReads;
    for (final (String, int) scope in <(String, int)>[
      (tokenAddress.toString(), fixture.session.chainId),
      (fixture.session.address, fixture.session.chainId + 1),
    ]) {
      final TokenActionSession session = TokenActionSession(
        address: scope.$1,
        chainId: scope.$2,
        isCurrent: () => true,
        readToken: fixture.session.readToken,
        readAccount: fixture.session.readAccount,
        mintBlock: fixture.session.mintBlock,
        burnBlock: fixture.session.burnBlock,
        transferBlock: fixture.session.transferBlock,
      );
      final TokenActionPublisher foreign = TokenActionPublisher(
        sender: fixture.sender,
        session: session,
        confirmationChanges: fixture.flights,
        hasConfirmedOriginal:
            ({
              required String hash,
              required String owner,
              required int chainId,
            }) => true,
      );
      expect(foreign.canStartAnother(original), isFalse);
      expect(
        await foreign.another(original, isCurrent: () => true),
        isNull,
      );
    }
    expect(fixture.tokenReads, reads);
    expect(fixture.transport.calls, hasLength(1));
  });

  test('Another keeps its hold when the fresh proof loses authority', () async {
    final TokenActionOutcome original = await fixture.publisher.publish(
      await fixture.intent(),
    );
    fixture.confirm(original);
    final Completer<Token?> delayed = Completer<Token?>();
    fixture.tokenRead = (_) => delayed.future;
    bool visible = true;
    final Future<TokenActionProof?> rearm = fixture.publisher.another(
      original,
      isCurrent: () => visible,
    );
    addTearDown(() async {
      if (!delayed.isCompleted) delayed.complete(fixture.token);
      await rearm;
    });
    expect(fixture.sender.busy.value, isTrue);
    expect(fixture.sender.tryReserve(Object()), isFalse);
    visible = false;
    delayed.complete(fixture.token);
    expect(await rearm, isNull);
    expect(
      fixture.publisher.heldFor(fixture.token.tokenStandard),
      same(original),
    );
    expect(fixture.sender.busy.value, isFalse);
    expect(fixture.transport.calls, hasLength(1));
  });

  test('failed fresh flags do not reach an ownership builder', () async {
    final TokenActionIntent intent = await fixture.intent(
      mode: TokenActionMode.transfer,
    );
    fixture.token = actionToken(burnable: false);
    expect(
      (await fixture.publisher.publish(intent)).status,
      TokenActionStatus.refused,
    );
    expect(fixture.transfers, isEmpty);
    expect(fixture.transport.calls, isEmpty);
  });

  for (final String mismatch in <String>['owner', 'hash', 'amount', 'data']) {
    test(
      'accepted $mismatch mismatch holds the identical unknown response',
      () async {
        late AccountBlockTemplate accepted;
        fixture.transport.reply = (ActionCall call) {
          accepted = fixture.transport.accepted(call);
          switch (mismatch) {
            case 'owner':
              accepted.address = tokenAddress;
            case 'hash':
              accepted.hash = emptyHash;
            case 'amount':
              accepted.amount = BigInt.one;
            case 'data':
              accepted.data[0] = 99;
          }
          return accepted;
        };
        final TokenActionOutcome outcome = await fixture.publisher.publish(
          await fixture.intent(),
        );
        expect(outcome.status, TokenActionStatus.unknown);
        expect(outcome.block, same(accepted));
        expect(outcome.result!.accepted, isTrue);
        expect(
          await fixture.publisher.publish(await fixture.intent()),
          same(outcome),
        );
        expect(fixture.transport.calls, hasLength(1));
      },
    );
  }
}

class _LoadingObserver extends BlocObserver {
  _LoadingObserver(this.revoke);
  final void Function() revoke;

  @override
  void onChange(BlocBase<dynamic> bloc, Change<dynamic> change) {
    final dynamic next = change.nextState;
    if (bloc is SendTransactionBloc &&
        next is SendTransactionState &&
        next.status == SendTransactionStatus.loading) {
      revoke();
    }
    super.onChange(bloc, change);
  }
}
