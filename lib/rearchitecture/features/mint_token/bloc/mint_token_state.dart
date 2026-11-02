part of 'mint_token_bloc.dart';

/// Base class for mint-token states.
sealed class MintTokenState extends Equatable {
  /// Creates a [MintTokenState].
  const MintTokenState();

  @override
  List<Object?> get props => <Object?>[];
}

/// Initial state before minting starts.
final class MintTokenInitial extends MintTokenState {
  /// Creates a [MintTokenInitial] state.
  const MintTokenInitial();
}

/// Loading state while the token is being minted.
final class MintTokenLoading extends MintTokenState {
  /// Creates a [MintTokenLoading] state.
  const MintTokenLoading();
}

/// Success state emitted after the token has been minted.
final class MintTokenDone extends MintTokenState {
  /// Creates a [MintTokenDone] state.
  const MintTokenDone({
    required this.accountBlock,
    required this.requestedMintAmount,
    this.outcome,
  });

  /// Account block returned after minting the token.
  final AccountBlockTemplate accountBlock;

  /// The contract call's requested units, separate from the SDK block amount.
  final BigInt requestedMintAmount;

  /// Identical original result retained by the common publication journal.
  final TokenActionOutcome? outcome;

  @override
  List<Object?> get props => <Object?>[
    accountBlock,
    requestedMintAmount,
    outcome,
  ];
}

/// Failure state emitted when minting fails.
final class MintTokenFailure extends MintTokenState {
  /// Creates a [MintTokenFailure] state.
  const MintTokenFailure({required this.error, this.outcome});

  /// Error that caused minting to fail.
  final Object error;

  /// Display mapping cannot replace [error] or an admitted unknown outcome.
  SyriusException get exception =>
      error is SyriusException ? error as SyriusException : FailureException();

  /// An admitted unknown result remains held against duplicate retries.
  final TokenActionOutcome? outcome;

  @override
  List<Object?> get props => <Object?>[error, outcome];
}
