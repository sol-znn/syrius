import 'package:bloc/bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/tokens/actions/token_action_publisher.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/transfer_token/bloc/transfer_token_bloc.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/exceptions/exceptions.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

import '../../helpers/hydrated_bloc.dart';
import '../../token_actions_redesign/support.dart';

void main() {
  initHydratedStorage();
  late ActionFixture fixture;
  late TransferTokenBloc bloc;
  setUp(() {
    fixture = ActionFixture(initialToken: actionToken(burnable: false));
    bloc = TransferTokenBloc(publisher: fixture.publisher);
  });
  tearDown(() async {
    fixture.transport.release();
    await bloc.close();
    await fixture.close();
  });

  TransferTokenRequested request() => TransferTokenRequested(
    newOwnerAddress: tokenAddress,
    token: fixture.token,
  );

  ActionTerminalObserver<TransferTokenState> terminalObserver() =>
      ActionTerminalObserver<TransferTokenState>(
        target: (BlocBase<dynamic> candidate) => candidate is TransferTokenBloc,
        terminal: (TransferTokenState state) =>
            state is TransferTokenDone || state is TransferTokenFailure,
      );

  test(
    'initial state is correct',
    () => expect(bloc.state, const TransferTokenInitial()),
  );

  test(
    'done retains original block, frozen new owner and unchanged flags',
    () async {
      late AccountBlockTemplate accepted;
      fixture.transport.reply = (ActionCall call) =>
          accepted = fixture.transport.accepted(call);
      final Future<TransferTokenState> done = bloc.stream
          .firstWhere((TransferTokenState state) => state is TransferTokenDone)
          .timeout(const Duration(seconds: 1));
      bloc.add(request());
      final TransferTokenDone state = await done as TransferTokenDone;
      expect(state.accountBlock, same(accepted));
      expect(state.newOwnerAddress, tokenAddress.toString());
      expect(fixture.transfers.single, (true, false, tokenAddress.toString()));
      expect(state.outcome!.result!.block, same(accepted));
    },
  );

  for (final Object error in <Object>[
    FailureException(),
    StateError('Synthetic original transfer'),
  ]) {
    test(
      'failure retains original ${error.runtimeType} and unknown outcome',
      () async {
        fixture.transport.error = error;
        final Future<TransferTokenState> failed = bloc.stream
            .firstWhere(
              (TransferTokenState state) => state is TransferTokenFailure,
            )
            .timeout(const Duration(seconds: 1));
        bloc.add(request());
        final TransferTokenFailure state = await failed as TransferTokenFailure;
        expect(state.error, same(error));
        expect(state.outcome!.status, TokenActionStatus.unknown);
        expect(state.outcome!.result!.error, same(error));
      },
    );
  }

  for (final bool acceptedResult in <bool>[true, false]) {
    test(
      'terminal observer errors preserve transfer '
      '${acceptedResult ? 'acceptance' : 'uncertainty'}',
      () async {
        final StateError originalError = StateError(
          'Synthetic transfer outcome',
        );
        late AccountBlockTemplate accepted;
        fixture.transport
          ..error = acceptedResult ? null : originalError
          ..reply = (ActionCall call) =>
              accepted = fixture.transport.accepted(call);
        final ActionTerminalObserver<TransferTokenState> observer =
            terminalObserver();
        final BlocObserver previous = Bloc.observer;
        Bloc.observer = observer;
        final TransferTokenBloc observed = TransferTokenBloc(
          publisher: fixture.publisher,
        );
        final Future<TransferTokenState> delivery = observed.stream
            .firstWhere(observer.terminal)
            .timeout(const Duration(seconds: 1));
        try {
          observed.add(request());
          final TransferTokenState delivered = await delivery;
          final TokenActionOutcome original = observed.lastOutcome!;
          expect(observer.attempted, hasLength(1));
          expect(delivered, same(observer.attempted.single));
          expect(observed.state, same(delivered));
          expect(observer.reported, contains(same(observer.displayError)));
          if (acceptedResult) {
            final TransferTokenDone terminal =
                observer.attempted.single as TransferTokenDone;
            expect(terminal.accountBlock, same(accepted));
            expect(terminal.newOwnerAddress, tokenAddress.toString());
            expect(terminal.outcome, same(original));
            expect(original.status, TokenActionStatus.submitted);
            expect(original.result!.block, same(accepted));
          } else {
            final TransferTokenFailure terminal =
                observer.attempted.single as TransferTokenFailure;
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
              await fixture.intent(
                mode: TokenActionMode.transfer,
                receiver: tokenAddress.toString(),
              ),
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
    final StateError originalError = StateError('Synthetic transfer proof');
    fixture.tokenRead = (_) async => throw originalError;
    final ActionTerminalObserver<TransferTokenState> observer =
        terminalObserver();
    final BlocObserver previous = Bloc.observer;
    Bloc.observer = observer;
    final TransferTokenBloc observed = TransferTokenBloc(
      publisher: fixture.publisher,
    );
    final Future<TransferTokenState> delivery = observed.stream
        .firstWhere(observer.terminal)
        .timeout(const Duration(seconds: 1));
    try {
      observed.add(request());
      final TransferTokenFailure terminal =
          await delivery as TransferTokenFailure;
      expect(observer.attempted, <TransferTokenState>[terminal]);
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
    'selected non-owner cannot transfer a wallet address own token',
    () async {
      fixture.token = actionToken(owner: tokenAddress);
      final Future<TransferTokenState> failed = bloc.stream
          .firstWhere(
            (TransferTokenState state) => state is TransferTokenFailure,
          )
          .timeout(const Duration(seconds: 1));
      bloc.add(request());
      final TransferTokenFailure state = await failed as TransferTokenFailure;
      expect(state.outcome!.status, TokenActionStatus.refused);
      expect(fixture.transfers, isEmpty);
      expect(fixture.transport.calls, isEmpty);
    },
  );

  test('an accepted burn cannot become a legacy Transfer Done', () async {
    final TokenActionOutcome original = await fixture.publisher.publish(
      await fixture.intent(mode: TokenActionMode.burn),
    );
    final Future<TransferTokenState> failed = bloc.stream
        .firstWhere((TransferTokenState state) => state is TransferTokenFailure)
        .timeout(const Duration(seconds: 1));
    bloc.add(request());
    final TransferTokenFailure state = await failed as TransferTokenFailure;
    expect(state.outcome, same(original));
    expect(bloc.state, isNot(isA<TransferTokenDone>()));
    expect(fixture.transfers, isEmpty);
    expect(fixture.transport.calls, hasLength(1));
  });
}
