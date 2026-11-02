part of 'fuse_plasma_bloc.dart';

/// Base class for all fuse plasma events.
sealed class FusePlasmaEvent extends Equatable {
  /// Creates a new [FusePlasmaEvent].
  const FusePlasmaEvent();

  @override
  List<Object?> get props => <Object?>[];
}

/// Requests fusing QSR for Plasma.
final class FusePlasmaRequested extends FusePlasmaEvent {
  /// Creates a [FusePlasmaRequested] event.
  const FusePlasmaRequested({
    required this.beneficiaryAddress,
    required this.amount,
    this.session,
    this.isCurrent,
    this.draft,
  });

  /// Address that will receive the generated Plasma.
  final String beneficiaryAddress;

  /// QSR in its integer smallest units.
  final BigInt amount;

  /// Production authority captured before the form yields or asks a question.
  final PlasmaSession? session;

  /// The original form can revoke preparation without replacing its result.
  final bool Function()? isCurrent;

  /// An old event observes its original draft instead of consuming a rearm.
  final PlasmaFuseDraft? draft;

  @override
  List<Object?> get props => <Object?>[
    beneficiaryAddress,
    amount,
    session,
    isCurrent,
    draft,
  ];
}
