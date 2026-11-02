/// Whether one owner fact is known, pending, or unavailable.
enum PillarOwnerFactState {
  /// A read has not completed.
  loading,

  /// The source supplied a value, including an actual zero.
  available,

  /// The source cannot establish this fact.
  unavailable,
}

/// One independently sourced fact. Unknown money is never replaced by zero.
final class PillarOwnerFact<T extends Object> {
  /// A pending read, without a value.
  const PillarOwnerFact.loading()
    : state = PillarOwnerFactState.loading,
      value = null;

  /// A value actually supplied by the source.
  const PillarOwnerFact.available(T this.value)
    : state = PillarOwnerFactState.available;

  /// A fact the source does not supply.
  const PillarOwnerFact.unavailable()
    : state = PillarOwnerFactState.unavailable,
      value = null;

  /// The read's meaning, independently of any other fact.
  final PillarOwnerFactState state;

  /// Present only when [state] is [PillarOwnerFactState.available].
  final T? value;
}

/// A copied owner read and the root-owned ticket that may admit its actions.
///
/// Amounts are smallest units. A registration constant cannot establish this
/// pillar's locked balance, and registration cost cannot establish a deposit.
/// The boundary is when the reported revocation state next changes.
typedef PillarOwnerSnapshot = ({
  Object authority,
  String ownerAddress,
  String name,
  String producerAddress,
  String rewardAddress,
  BigInt weight,
  BigInt? lockedZnn,
  PillarOwnerFact<BigInt> depositedQsr,
  PillarOwnerFact<BigInt> registrationCostQsr,
  int momentumRewardPercent,
  int delegateRewardPercent,
  int producedMomentums,
  int expectedMomentums,
  bool isRevocable,
  DateTime? revocationBoundaryUtc,
});

/// Existing management flows admitted by the caller, never by the view.
enum PillarOwnerAction {
  /// Opens the existing update flow.
  update,

  /// Opens the existing QSR deposit flow.
  depositQsr,

  /// Opens the existing QSR withdrawal flow.
  withdrawQsr,

  /// Both questions accepted the same still-current owner snapshot.
  revokeConfirmed,
}
