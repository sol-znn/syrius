import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// What a person has typed into the send form and not yet sent.
class SendDraft extends Equatable {
  /// Creates a draft; an empty one by default.
  const SendDraft({
    this.fromAddress,
    this.tokenStandard,
    this.recipient = '',
    this.amount = '',
  });

  /// The sending address, or null for the wallet's selected one.
  final String? fromAddress;

  /// The token chosen, as its token standard, or null for the first coin.
  final String? tokenStandard;

  /// The recipient field, as typed.
  final String recipient;

  /// The amount field, as typed.
  final String amount;

  /// Whether nothing has been entered or chosen.
  bool get isEmpty =>
      fromAddress == null &&
      tokenStandard == null &&
      recipient.isEmpty &&
      amount.isEmpty;

  @override
  List<Object?> get props => <Object?>[
    fromAddress,
    tokenStandard,
    recipient,
    amount,
  ];
}

/// Keeps a half-filled send form while its page is not on screen.
///
/// The shell builds only the page that is shown, so leaving Transfer
/// disposes the form and its text controllers. This holds the four values
/// above the page switch, and the form writes to it as they change and reads
/// it back when it is built again.
///
/// It lives in memory only (a plain cubit, never hydrated), and is cleared
/// when a send succeeds and when the wallet locks: a recipient and an amount
/// should not outlast the session that typed them, nor be offered again
/// after they were sent.
class SendDraftCubit extends Cubit<SendDraft> {
  /// Creates the holder, empty.
  SendDraftCubit() : super(const SendDraft());

  /// Records the form as it now stands.
  void save({
    required String fromAddress,
    required String tokenStandard,
    required String recipient,
    required String amount,
  }) {
    emit(
      SendDraft(
        fromAddress: fromAddress,
        tokenStandard: tokenStandard,
        recipient: recipient,
        amount: amount,
      ),
    );
  }

  /// Forgets everything.
  void clear() => emit(const SendDraft());

  /// An old accepted request cannot clear a draft edited while it waited.
  bool clearIfUnchanged(SendDraft expected) {
    if (isClosed || !identical(state, expected)) return false;
    clear();
    return true;
  }

  /// Selects one exact recipient without submitting or changing the amount.
  /// Mounted forms observe it too, so returning to Send is not required.
  void selectRecipient(String recipient) => emit(
    SendDraft(
      fromAddress: state.fromAddress,
      tokenStandard: state.tokenStandard,
      recipient: recipient,
      amount: state.amount,
    ),
  );

  /// A row selects its exact asset without reusing another asset's amount.
  /// The existing recipient remains a draft, subject to normal confirmation.
  void selectToken({
    required String fromAddress,
    required String tokenStandard,
  }) {
    if (isClosed) return;
    emit(
      SendDraft(
        fromAddress: fromAddress,
        tokenStandard: tokenStandard,
        recipient: state.recipient,
        amount:
            state.fromAddress == fromAddress &&
                state.tokenStandard == tokenStandard
            ? state.amount
            : '',
      ),
    );
  }
}
