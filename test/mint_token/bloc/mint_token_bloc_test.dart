import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/mint_token/bloc/mint_token_bloc.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/tokens/actions/token_action_publisher.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/exceptions/exceptions.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

import '../../helpers/hydrated_bloc.dart';
import '../../token_actions_redesign/support.dart';

void main() {
  initHydratedStorage();
  late ActionFixture fixture;
  late MintTokenBloc bloc;
  setUp(() {
    fixture = ActionFixture();
    bloc = MintTokenBloc(publisher: fixture.publisher);
  });
  tearDown(() async {
    fixture.transport.release();
    await bloc.close();
    await fixture.close();
  });

  MintTokenRequested request([BigInt? amount]) => MintTokenRequested(
    amount: amount ?? BigInt.one,
    beneficiaryAddress: emptyAddress,
    token: fixture.token,
  );

  ActionTerminalObserver<MintTokenState> terminalObserver() =>
      ActionTerminalObserver<MintTokenState>(
        target: (BlocBase<dynamic> candidate) => candidate is MintTokenBloc,
        terminal: (MintTokenState state) =>
            state is MintTokenDone || state is MintTokenFailure,
      );

  test(
    'initial state is correct',
    () => expect(bloc.state, const MintTokenInitial()),
  );

  test(
    'done preserves the original SDK response and its native amount',
    () async {
      final BigInt units = BigInt.parse('900719925474099312345');
      late AccountBlockTemplate accepted;
      fixture.transport.reply = (ActionCall call) =>
          accepted = fixture.transport.accepted(call);
      final Future<MintTokenState> done = bloc.stream
          .firstWhere((MintTokenState state) => state is MintTokenDone)
          .timeout(const Duration(seconds: 1));
      bloc.add(request(units));
      final MintTokenDone state = await done as MintTokenDone;
      expect(state.accountBlock, same(accepted));
      expect(accepted.amount, BigInt.zero);
      expect(state.requestedMintAmount, units);
      expect(state.outcome!.requestedMintAmount, units);
      expect(state.outcome!.result!.block, same(accepted));
      expect(fixture.mints.single.$2, units);
      expect(bloc.lastOutcome, same(state.outcome));
    },
  );

  for (final Object error in <Object>[
    FailureException(),
    StateError('Synthetic original mint'),
  ]) {
    test(
      'failure holds the original ${error.runtimeType} and unknown outcome',
      () async {
        fixture.transport.error = error;
        final Future<MintTokenState> failed = bloc.stream
            .firstWhere((MintTokenState state) => state is MintTokenFailure)
            .timeout(const Duration(seconds: 1));
        bloc.add(request());
        final MintTokenFailure state = await failed as MintTokenFailure;
        expect(state.error, same(error));
        expect(state.outcome!.status, TokenActionStatus.unknown);
        expect(state.outcome!.result!.error, same(error));
        expect(state.exception, isA<SyriusException>());
      },
    );
  }

  for (final bool acceptedResult in <bool>[true, false]) {
    test(
      'terminal observer errors preserve mint '
      '${acceptedResult ? 'acceptance' : 'uncertainty'}',
      () async {
        final StateError originalError = StateError('Synthetic mint outcome');
        late AccountBlockTemplate accepted;
        fixture.transport
          ..error = acceptedResult ? null : originalError
          ..reply = (ActionCall call) =>
              accepted = fixture.transport.accepted(call);
        final ActionTerminalObserver<MintTokenState> observer =
            terminalObserver();
        final BlocObserver previous = Bloc.observer;
        Bloc.observer = observer;
        final MintTokenBloc observed = MintTokenBloc(
          publisher: fixture.publisher,
        );
        final Future<MintTokenState> delivery = observed.stream
            .firstWhere(observer.terminal)
            .timeout(const Duration(seconds: 1));
        try {
          observed.add(request());
          final MintTokenState delivered = await delivery;
          final TokenActionOutcome original = observed.lastOutcome!;
          expect(observer.attempted, hasLength(1));
          expect(delivered, same(observer.attempted.single));
          expect(observed.state, same(delivered));
          expect(observer.reported, contains(same(observer.displayError)));
          if (acceptedResult) {
            final MintTokenDone terminal =
                observer.attempted.single as MintTokenDone;
            expect(terminal.accountBlock, same(accepted));
            expect(terminal.requestedMintAmount, BigInt.one);
            expect(terminal.outcome, same(original));
            expect(original.status, TokenActionStatus.submitted);
            expect(original.result!.block, same(accepted));
            expect(accepted.amount, BigInt.zero);
          } else {
            final MintTokenFailure terminal =
                observer.attempted.single as MintTokenFailure;
            expect(terminal.error, same(originalError));
            expect(terminal.outcome, same(original));
            expect(original.status, TokenActionStatus.unknown);
            expect(original.error, same(originalError));
            expect(original.result!.error, same(originalError));
          }
          expect(
            TokenActionPublisher.originalOutcomesFor(fixture.sender).single,
            same(original),
          );
          expect(
            await fixture.publisher.publish(await fixture.intent()),
            same(original),
          );
          expect(fixture.transport.calls, hasLength(1));
        } finally {
          Bloc.observer = previous;
          await observed.close();
        }
      },
    );
  }

  test('read errors survive terminal and diagnostic observer errors', () async {
    final StateError originalError = StateError('Synthetic mint proof');
    fixture.tokenRead = (_) async => throw originalError;
    final ActionTerminalObserver<MintTokenState> observer = terminalObserver();
    final BlocObserver previous = Bloc.observer;
    Bloc.observer = observer;
    final MintTokenBloc observed = MintTokenBloc(publisher: fixture.publisher);
    final Future<MintTokenState> delivery = observed.stream
        .firstWhere(observer.terminal)
        .timeout(const Duration(seconds: 1));
    try {
      observed.add(request());
      final MintTokenFailure terminal = await delivery as MintTokenFailure;
      expect(observer.attempted, <MintTokenState>[terminal]);
      expect(observed.state, same(terminal));
      expect(terminal.error, same(originalError));
      expect(terminal.outcome, isNull);
      expect(observer.reported, contains(same(originalError)));
      expect(observed.lastOutcome, isNull);
      expect(fixture.transport.calls, isEmpty);
      expect(TokenActionPublisher.originalOutcomesFor(fixture.sender), isEmpty);
    } finally {
      Bloc.observer = previous;
      await observed.close();
    }
  });

  test(
    'duplicates and disposal preserve the original accepted mint',
    () async {
      fixture.transport.deferred = true;
      bloc
        ..add(request())
        ..add(request());
      await actionTurnsUntil(() => fixture.transport.pending.isNotEmpty);
      final AccountBlockTemplate original = fixture.transport.accepted(
        fixture.transport.calls.single,
      );
      final Future<void> closing = bloc.close();
      fixture.transport.complete(block: original);
      await closing;
      await actionTurnsUntil(() => bloc.lastOutcome != null);
      expect(bloc.lastOutcome!.block, same(original));
      expect(original.amount, BigInt.zero);
      expect(fixture.transport.calls, hasLength(1));
    },
  );

  test('a queued event snapshots mutable token metadata', () {
    final MintTokenRequested event = request();
    fixture.token.owner = tokenAddress;
    expect(event.token.owner, emptyAddress);
    event.token.owner = tokenAddress;
    expect(event.token.owner, emptyAddress);
  });

  test('a changed mint cannot report an older acceptance as Done', () async {
    final TokenActionOutcome original = await fixture.publisher.publish(
      await fixture.intent(),
    );
    final Future<MintTokenState> failed = bloc.stream
        .firstWhere((MintTokenState state) => state is MintTokenFailure)
        .timeout(const Duration(seconds: 1));
    bloc.add(request(BigInt.two));
    final MintTokenFailure state = await failed as MintTokenFailure;
    expect(state.outcome, same(original));
    expect(bloc.state, isNot(isA<MintTokenDone>()));
    expect(fixture.transport.calls, hasLength(1));
  });

  test(
    'closing the adapter fences a provided original intent through preparation',
    () async {
      final TokenActionIntent intent = await fixture.intent();
      final Completer<void> gate = Completer<void>();
      fixture.transport.preparation = gate;
      bloc.add(
        MintTokenRequested(
          amount: intent.amount,
          beneficiaryAddress: emptyAddress,
          token: fixture.token,
          intent: intent,
        ),
      );
      await actionTurnsUntil(() => fixture.transport.calls.isNotEmpty);
      final Future<void> closing = bloc.close();
      gate.complete();
      await closing;
      await actionTurnsUntil(() => bloc.lastOutcome != null);
      expect(fixture.transport.published, 0);
      expect(bloc.lastOutcome!.status, TokenActionStatus.unknown);
      expect(bloc.lastOutcome!.error, same(bloc.lastOutcome!.result!.error));
    },
  );
}
