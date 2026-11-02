part of 'burn_token_bloc.dart';

/// Base class for burn-token states.
sealed class BurnTokenState extends Equatable {
  /// Creates a [BurnTokenState].
  const BurnTokenState();

  @override
  List<Object?> get props => <Object?>[];
}

/// Initial state before a burn is requested.
final class BurnTokenInitial extends BurnTokenState {
  /// Creates a [BurnTokenInitial] state.
  const BurnTokenInitial();
}

/// Loading state while the token is being burned.
final class BurnTokenLoading extends BurnTokenState {
  /// Creates a [BurnTokenLoading] state.
  const BurnTokenLoading();
}

/// Success state emitted after the token has been burned.
final class BurnTokenDone extends BurnTokenState {
  /// Creates a [BurnTokenDone] state.
  const BurnTokenDone({required this.accountBlock, this.outcome});

  /// Account block returned after burning the token.
  final AccountBlockTemplate accountBlock;

  /// The identical original sender result.
  final TokenActionOutcome? outcome;

  @override
  List<Object?> get props => <Object?>[accountBlock, outcome];
}

/// Failure state emitted when burning fails.
final class BurnTokenFailure extends BurnTokenState {
  /// Creates a [BurnTokenFailure] state.
  const BurnTokenFailure({required this.error, this.outcome});

  /// Error that caused the burn to fail.
  final Object error;

  /// Display mapping leaves the original error intact.
  SyriusException get exception =>
      error is SyriusException ? error as SyriusException : FailureException();

  /// Admitted uncertainty remains held by the common publisher.
  final TokenActionOutcome? outcome;

  @override
  List<Object?> get props => <Object?>[error, outcome];
}
