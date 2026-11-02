part of 'fuse_plasma_bloc.dart';

/// Base class for all fuse plasma states.
sealed class FusePlasmaState extends Equatable {
  /// Creates a new [FusePlasmaState].
  const FusePlasmaState();

  @override
  List<Object> get props => <Object>[];
}

/// Initial state before fusing starts.
final class FusePlasmaInitial extends FusePlasmaState {
  /// Creates a [FusePlasmaInitial] state.
  const FusePlasmaInitial();
}

/// Failure state emitted when fusing fails.
final class FusePlasmaFailure extends FusePlasmaState {
  /// Creates a [FusePlasmaFailure] state.
  const FusePlasmaFailure({required this.exception, this.error, this.outcome});

  /// The error that caused the fusing operation to fail.
  final SyriusException exception;

  /// Original preparation or SDK error before display mapping.
  final Object? error;

  /// An admitted original remains held after the form leaves.
  final PlasmaFuseOutcome? outcome;

  @override
  List<Object> get props => <Object>[
    exception,
    ?error,
    ?outcome,
  ];
}

/// Success state emitted when fusing completes.
final class FusePlasmaDone extends FusePlasmaState {
  /// Creates a [FusePlasmaDone] state.
  const FusePlasmaDone({required this.accountBlock, this.outcome});

  /// Created account block.
  final AccountBlockTemplate accountBlock;

  /// The identical original result, separate from positive confirmation.
  final PlasmaFuseOutcome? outcome;

  @override
  List<Object> get props => <Object>[
    accountBlock,
    ?outcome,
  ];
}

/// Loading state emitted while fusing is in progress.
final class FusePlasmaLoading extends FusePlasmaState {
  /// Creates a [FusePlasmaLoading] state.
  const FusePlasmaLoading();
}
