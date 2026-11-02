part of 'send_transaction_bloc.dart';

/// The base class for events in `SendPaymentBloc`.
sealed class SendTransactionEvent extends Equatable {
  /// Keeps display ownership separate from the shared publication transport.
  const SendTransactionEvent({
    this.requestId,
    this.origin = SendTransactionOrigin.transfer,
  });

  /// An ephemeral identity, never persisted as transaction evidence.
  final Object? requestId;

  /// The surface entitled to react to this operation's result.
  final SendTransactionOrigin origin;
}

/// Event to initiate sending a transfer.
class SendTransactionInitiate extends SendTransactionEvent {
  /// Creates a [SendTransactionInitiate] event.
  const SendTransactionInitiate({
    required this.fromAddress,
    required this.toAddress,
    required this.amount,
    required this.token,
    this.data,
    super.requestId,
  });

  /// The address from which the payment is sent.
  final String fromAddress;

  /// The address to which the payment is sent.
  final String toAddress;

  /// The amount to be transferred.
  final BigInt amount;

  /// Optional data associated with the transfer.
  final List<int>? data;

  /// The token being transferred.
  final Token token;

  @override
  List<Object?> get props => <Object?>[
    fromAddress,
    toAddress,
    amount,
    token,
    data,
    requestId,
  ];
}

/// Event to initiate sending a transfer using an existing account block.
class SendTransactionInitiateFromBlock extends SendTransactionEvent {
  /// Creates a [SendTransactionInitiateFromBlock] event.
  const SendTransactionInitiateFromBlock({
    required this.block,
    required this.fromAddress,
    required this.reasonForGeneratingPlasma,
    super.requestId,
    super.origin = SendTransactionOrigin.contract,
  });

  /// The account block template representing the transfer.
  final AccountBlockTemplate block;

  /// The address from which the payment is sent.
  final String fromAddress;

  /// The reason for generating plasma that will be displayed to the user, in a
  /// notification.
  final String reasonForGeneratingPlasma;

  @override
  List<Object?> get props => <Object?>[block, fromAddress, requestId, origin];
}
