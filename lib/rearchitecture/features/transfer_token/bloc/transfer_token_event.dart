part of 'transfer_token_bloc.dart';

/// Base class for transfer-token events.
sealed class TransferTokenEvent extends Equatable {
  /// Creates a [TransferTokenEvent].
  const TransferTokenEvent();

  @override
  List<Object?> get props => <Object?>[];
}

/// Requests transferring ownership of a token to a new address.
final class TransferTokenRequested extends TransferTokenEvent {
  /// Creates a [TransferTokenRequested] event.
  TransferTokenRequested({
    required Address newOwnerAddress,
    required Token token,
    this.intent,
  }) : _token = Map<String, dynamic>.unmodifiable(token.toJson()),
       _newOwner = newOwnerAddress.toString();

  /// Address that will become the token owner.
  final String _newOwner;

  /// A returned SDK address copy cannot rewrite the captured recipient.
  Address get newOwnerAddress => Address.parse(_newOwner);

  /// Token whose ownership will be transferred.
  final Map<String, dynamic> _token;

  /// Mutable SDK metadata cannot change the queued original request.
  Token get token => Token.fromJson(Map<String, dynamic>.of(_token));

  /// The form's original question, captured before yielding.
  final TokenActionIntent? intent;

  @override
  List<Object?> get props => <Object?>[_newOwner, _token, intent];
}
