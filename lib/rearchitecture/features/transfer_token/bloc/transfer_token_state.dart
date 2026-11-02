part of 'transfer_token_bloc.dart';

/// Base class for transfer-token states.
sealed class TransferTokenState extends Equatable {
  /// Creates a [TransferTokenState].
  const TransferTokenState();

  @override
  List<Object?> get props => <Object?>[];
}

/// Initial state before an ownership transfer is requested.
final class TransferTokenInitial extends TransferTokenState {
  /// Creates a [TransferTokenInitial] state.
  const TransferTokenInitial();
}

/// Loading state while ownership is being transferred.
final class TransferTokenLoading extends TransferTokenState {
  /// Creates a [TransferTokenLoading] state.
  const TransferTokenLoading();
}

/// Success state emitted after ownership has been transferred.
final class TransferTokenDone extends TransferTokenState {
  /// Creates a [TransferTokenDone] state.
  const TransferTokenDone({
    required this.accountBlock,
    required this.newOwnerAddress,
    this.outcome,
  });

  /// Account block returned after transferring ownership.
  final AccountBlockTemplate accountBlock;

  /// The address named by the original confirmation, never an edited field.
  final String newOwnerAddress;

  /// The common publisher's original result.
  final TokenActionOutcome? outcome;

  @override
  List<Object?> get props => <Object?>[accountBlock, newOwnerAddress, outcome];
}

/// Failure state emitted when transferring ownership fails.
final class TransferTokenFailure extends TransferTokenState {
  /// Creates a [TransferTokenFailure] state.
  const TransferTokenFailure({required this.error, this.outcome});

  /// Error that caused the ownership transfer to fail.
  final Object error;

  /// Mapping for existing error presentation leaves the original error intact.
  SyriusException get exception =>
      error is SyriusException ? error as SyriusException : FailureException();

  /// An unknown admitted request is retained and cannot be retried implicitly.
  final TokenActionOutcome? outcome;

  @override
  List<Object?> get props => <Object?>[error, outcome];
}
