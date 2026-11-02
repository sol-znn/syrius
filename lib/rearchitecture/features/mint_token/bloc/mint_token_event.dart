part of 'mint_token_bloc.dart';

/// Base class for mint-token events.
sealed class MintTokenEvent extends Equatable {
  /// Creates a [MintTokenEvent].
  const MintTokenEvent();

  @override
  List<Object?> get props => <Object?>[];
}

/// Requests minting an amount of a token to a beneficiary address.
final class MintTokenRequested extends MintTokenEvent {
  /// Creates a [MintTokenRequested] event.
  MintTokenRequested({
    required this.amount,
    required Address beneficiaryAddress,
    required Token token,
    this.intent,
  }) : _token = Map<String, dynamic>.unmodifiable(token.toJson()),
       _beneficiary = beneficiaryAddress.toString();

  /// Amount to mint in the token's smallest unit.
  final BigInt amount;

  /// Address that will receive the minted tokens.
  final String _beneficiary;

  /// SDK address copies cannot rewrite the frozen beneficiary.
  Address get beneficiaryAddress => Address.parse(_beneficiary);

  /// Token to mint.
  final Map<String, dynamic> _token;

  /// Independent metadata keeps a queued event immutable.
  Token get token => Token.fromJson(Map<String, dynamic>.of(_token));

  /// Forms capture this before their confirmation yields.
  final TokenActionIntent? intent;

  @override
  List<Object?> get props => <Object?>[amount, _beneficiary, _token, intent];
}
