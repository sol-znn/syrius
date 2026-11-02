part of 'burn_token_bloc.dart';

/// Base class for burn-token events.
sealed class BurnTokenEvent extends Equatable {
  /// Creates a [BurnTokenEvent].
  const BurnTokenEvent();

  @override
  List<Object?> get props => <Object?>[];
}

/// Requests burning an amount of a token.
final class BurnTokenRequested extends BurnTokenEvent {
  /// Creates a [BurnTokenRequested] event.
  BurnTokenRequested({
    required this.amount,
    required Token token,
    this.intent,
  }) : _token = Map<String, dynamic>.unmodifiable(token.toJson());

  /// Amount to burn in the token's smallest unit.
  final BigInt amount;

  /// Token to burn.
  final Map<String, dynamic> _token;

  /// Queued SDK metadata cannot be rewritten by the source object.
  Token get token => Token.fromJson(Map<String, dynamic>.of(_token));

  /// An inline or legacy form captures its confirmation before yielding.
  final TokenActionIntent? intent;

  @override
  List<Object?> get props => <Object?>[amount, _token, intent];
}
