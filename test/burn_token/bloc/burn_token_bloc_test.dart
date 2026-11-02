import 'package:bloc/bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/burn_token/bloc/burn_token_bloc.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/tokens/actions/token_action_publisher.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/exceptions/exceptions.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

import '../../helpers/hydrated_bloc.dart';
import '../../token_actions_redesign/support.dart';

void main() {
  initHydratedStorage();
  late ActionFixture fixture;
  late BurnTokenBloc bloc;
  setUp(() {
    fixture = ActionFixture();
    bloc = BurnTokenBloc(publisher: fixture.publisher);
  });
  tearDown(() async {
    fixture.transport.release();
    await bloc.close();
    await fixture.close();
  });

  BurnTokenRequested request() =>
      BurnTokenRequested(amount: BigInt.one, token: fixture.token);

  ActionTerminalObserver<BurnTokenState> terminalObserver() =>
      ActionTerminalObserver<BurnTokenState>(
        target: (BlocBase<dynamic> candidate) => candidate is BurnTokenBloc,
        terminal: (BurnTokenState state) =>
            state is BurnTokenDone || state is BurnTokenFailure,
      );

  test(
    'initial state is correct',
    () => expect(bloc.state, const BurnTokenInitial()),
  );

  test(
    'done preserves the identical accepted burn after complete fresh proof',
    () async {
      late AccountBlockTemplate accepted;
      fixture.transport.reply = (ActionCall call) =>
          accepted = fixture.transport.accepted(call);
      final Future<BurnTokenState> done = bloc.stream
          .firstWhere((BurnTokenState state) => state is BurnTokenDone)
          .timeout(const Duration(seconds: 1));
      bloc.add(request());
      final BurnTokenDone state = await done as BurnTokenDone;
      expect(state.accountBlock, same(accepted));
      expect(fixture.burns.single.$2, BigInt.one);
      expect(fixture.tokenReads, 2);
      expect(fixture.accountReads, 2);
    },
  );

  for (final Object error in <Object>[
    FailureException(),
    StateError('Synthetic original burn'),
  ]) {
    test(
      'failure preserves original ${error.runtimeType} and unknown outcome',
      () async {
        fixture.transport.error = error;
        final Future<BurnTokenState> failed = bloc.stream
            .firstWhere((BurnTokenState state) => state is BurnTokenFailure)
            .timeout(const Duration(seconds: 1));
        bloc.add(request());
        final BurnTokenFailure state = await failed as BurnTokenFailure;
        expect(state.error, same(error));
        expect(state.outcome!.status, TokenActionStatus.unknown);
        expect(state.outcome!.result!.error, same(error));
      },
    );
  }

  for (final bool acceptedResult in <bool>[true, false]) {
    test(
      'terminal observer errors preserve burn '
      '${acceptedResult ? 'acceptance' : 'uncertainty'}',
      () async {
        final StateError originalError = StateError('Synthetic burn outcome');
        late AccountBlockTemplate accepted;
        fixture.transport
          ..error = acceptedResult ? null : originalError
          ..reply = (ActionCall call) =>
              accepted = fixture.transport.accepted(call);
        final ActionTerminalObserver<BurnTokenState> observer =
            terminalObserver();
        final BlocObserver previous = Bloc.observer;
        Bloc.observer = observer;
        final BurnTokenBloc observed = BurnTokenBloc(
          publisher: fixture.publisher,
        );
        final Future<BurnTokenState> delivery = observed.stream
            .firstWhere(observer.terminal)
            .timeout(const Duration(seconds: 1));
        try {
          observed.add(request());
          final BurnTokenState delivered = await delivery;
          final TokenActionOutcome original = observed.lastOutcome!;
          expect(observer.attempted, hasLength(1));
          expect(delivered, same(observer.attempted.single));
          expect(observed.state, same(delivered));
          expect(observer.reported, contains(same(observer.displayError)));
          if (acceptedResult) {
            final BurnTokenDone terminal =
                observer.attempted.single as BurnTokenDone;
            expect(terminal.accountBlock, same(accepted));
            expect(terminal.outcome, same(original));
            expect(original.status, TokenActionStatus.submitted);
            expect(original.result!.block, same(accepted));
            expect(accepted.amount, BigInt.one);
          } else {
            final BurnTokenFailure terminal =
                observer.attempted.single as BurnTokenFailure;
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
            await fixture.publisher.publish(
              await fixture.intent(mode: TokenActionMode.burn),
            ),
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
    final StateError originalError = StateError('Synthetic burn proof');
    fixture.tokenRead = (_) async => throw originalError;
    final ActionTerminalObserver<BurnTokenState> observer = terminalObserver();
    final BlocObserver previous = Bloc.observer;
    Bloc.observer = observer;
    final BurnTokenBloc observed = BurnTokenBloc(publisher: fixture.publisher);
    final Future<BurnTokenState> delivery = observed.stream
        .firstWhere(observer.terminal)
        .timeout(const Duration(seconds: 1));
    try {
      observed.add(request());
      final BurnTokenFailure terminal = await delivery as BurnTokenFailure;
      expect(observer.attempted, <BurnTokenState>[terminal]);
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

  test('selected non-owner cannot burn an owner-only token', () async {
    fixture.token = actionToken(owner: tokenAddress, burnable: false);
    final Future<BurnTokenState> failed = bloc.stream
        .firstWhere((BurnTokenState state) => state is BurnTokenFailure)
        .timeout(const Duration(seconds: 1));
    bloc.add(request());
    final BurnTokenFailure state = await failed as BurnTokenFailure;
    expect(state.outcome!.status, TokenActionStatus.refused);
    expect(fixture.transport.calls, isEmpty);
  });

  test('an accepted mint cannot become a legacy Burn Done', () async {
    final TokenActionOutcome original = await fixture.publisher.publish(
      await fixture.intent(),
    );
    final Future<BurnTokenState> failed = bloc.stream
        .firstWhere((BurnTokenState state) => state is BurnTokenFailure)
        .timeout(const Duration(seconds: 1));
    bloc.add(request());
    final BurnTokenFailure state = await failed as BurnTokenFailure;
    expect(state.outcome, same(original));
    expect(bloc.state, isNot(isA<BurnTokenDone>()));
    expect(fixture.burns, isEmpty);
    expect(fixture.transport.calls, hasLength(1));
  });
}
