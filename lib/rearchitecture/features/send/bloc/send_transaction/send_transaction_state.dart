part of 'send_transaction_bloc.dart';

/// The display owner of a shared sender operation.
enum SendTransactionOrigin {
  /// An ordinary transfer initiated from Send or its existing deep link.
  transfer,

  /// An existing contract action.
  contract,

  /// One request in the session's explicit reward collection batch.
  collection,
}

/// Represents the possible statuses of the send payment operation.
enum SendTransactionStatus {
  /// The initial state before any payment action has been taken.
  initial,

  /// Indicates that the payment process is currently in progress.
  loading,

  /// Indicates that the payment was successfully processed.
  success,

  /// Indicates that an error occurred during the payment process.
  failure,
}

/// Holds the state for [SendTransactionBloc], including status, data,
/// and error information.
@JsonSerializable(explicitToJson: true)
class SendTransactionState extends Equatable {
  /// Creates a new instance of [SendTransactionState].
  ///
  /// The [status] defaults to [SendTransactionStatus.initial] if not specified.
  const SendTransactionState({
    this.status = SendTransactionStatus.initial,
    this.data,
    this.error,
    this.requestId,
    this.origin = SendTransactionOrigin.transfer,
  });

  /// Creates a new instance from a JSON map.
  factory SendTransactionState.fromJson(Map<String, dynamic> json) =>
      _$SendTransactionStateFromJson(json);

  /// The current status of the send payment operation.
  final SendTransactionStatus status;

  /// The response data from the send payment operation.
  ///
  /// Contains the `AccountBlockTemplate` representing the transaction.
  final AccountBlockTemplate? data;

  /// An object representing any error occurring during the payment operation.
  final SyriusException? error;

  /// Correlates one live request without making it a durable journal entry.
  @JsonKey(includeFromJson: false, includeToJson: false)
  final Object? requestId;

  /// Prevents a contract result clearing or notifying an unrelated Send form.
  @JsonKey(includeFromJson: false, includeToJson: false)
  final SendTransactionOrigin origin;

  /// {@macro state_copy_with}
  SendTransactionState copyWith({
    SendTransactionStatus? status,
    AccountBlockTemplate? data,
    SyriusException? error,
    Object? requestId,
    SendTransactionOrigin? origin,
  }) {
    return SendTransactionState(
      status: status ?? this.status,
      data: data ?? this.data,
      error: error ?? this.error,
      requestId: requestId ?? this.requestId,
      origin: origin ?? this.origin,
    );
  }

  /// {@macro state_to_json}
  Map<String, dynamic> toJson() => _$SendTransactionStateToJson(this);

  @override
  List<Object?> get props => <Object?>[status, data, error, requestId, origin];
}
