import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/blocs/receive_origin.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/send/bloc/send_transaction/send_transaction_bloc.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/send/model/send_intent.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/send/widgets/send_confirmation.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/send/widgets/send_populated.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

import 'lab_transfer_witness.dart';
import 'seed_policy.dart';

/// Retains the actual form State, its sender and the original worker lease.
/// It performs no signing, submission, cancellation or application mutation.
final class LabSendUiBinding {
  LabSendUiBinding._(this.form, this.owner, this.source, this.origin);

  factory LabSendUiBinding.capture({
    required Element form,
    required SeedSource source,
    required ReceiveOrigin origin,
  }) {
    source.environment.requireLab();
    if (form is! StatefulElement || form.widget is! SendPopulated ||
        form.state is! SendFormOrigin) {
      throw const SeedRefused('original-send-form-required');
    }
    final LabSendUiBinding binding = LabSendUiBinding._(
      form, form.state as SendFormOrigin, source, origin,
    )..requireForm();
    return binding;
  }

  final StatefulElement form;
  final SendFormOrigin owner;
  final SeedSource source;
  final ReceiveOrigin origin;
  bool _revoked = false;
  LabSendUiReview? _review;

  /// Normal form/dialog disposal after input cannot revoke an original Future.
  bool get isCurrent {
    if (_revoked) return false;
    try {
      final SeedEnvironment env = source.environment;
      _revoked = !source.isCurrent || !origin.isCurrent ||
          origin.chainId != 321 || origin.nodeChainId != 321 ||
          origin.selectedAddress != env.owner ||
          !listEquals(origin.addresses, env.members) ||
          !identical(owner.originalSender, origin.sender);
    } on Object {
      _revoked = true;
    }
    return !_revoked;
  }

  void requireForm() {
    bool same = false;
    try {
      same = isCurrent && form.mounted &&
          form.widget is SendPopulated && identical(form.state, owner) &&
          TickerMode.valuesOf(form).enabled &&
          identical(form.read<SendTransactionBloc>(), owner.originalSender);
    } on Object {
      same = false;
    }
    if (!same) {
      _revoked = true;
      throw const SeedRefused('original-send-form-changed');
    }
  }

  /// The actual Accept element must descend from the actual form's review.
  LabSendUiReview captureReview(Element button, {required Offset center}) {
    requireForm();
    if (_review != null) {
      throw const SeedRefused('original-send-review-already-captured');
    }
    final (Element dialog, SendConfirmation shown) = _shown(button);
    final SendIntent intent = shown.intent;
    final SeedEnvironment env = source.environment;
    if (!owner.matchesOriginalReview(intent) ||
        intent.fromAddress != env.owner ||
        intent.toAddress != env.members[0] ||
        intent.recipientInput != env.members[0] || intent.amountInput != '1' ||
        intent.amount != BigInt.from(100000000) ||
        intent.tokenStandard != znnZts.toString() ||
        intent.symbol != 'ZNN' || intent.decimals != 8) {
      throw const SeedRefused('original-transfer-review-mismatch');
    }
    final LabTransferWitness witness = LabTransferWitness.capture(
      sender: owner.originalSender, intent: intent,
      owner: env.owner, recipient: env.members[0], isCurrent: () => isCurrent,
    );
    final LabSendUiReview review = LabSendUiReview._(
      this, button, dialog, intent, witness, center,
    );
    _review = review;
    review.requireReady(button, center: center);
    return review;
  }
}

(Element, SendConfirmation) _shown(Element button) {
  Element? dialog;
  SendConfirmation? shown;
  bool accept = button.widget.key == const Key('send_confirmation_accept');
  button.visitAncestorElements((Element ancestor) {
    if (ancestor.widget.key == const Key('send_confirmation_accept')) {
      accept = true;
    }
    if (ancestor.widget case final SendConfirmation value) {
      dialog = ancestor;
      shown = value;
      return false;
    }
    return true;
  });
  if (!button.mounted || !accept || shown == null || dialog == null ||
      ModalRoute.of(button)?.isCurrent != true ||
      !TickerMode.valuesOf(button).enabled) {
    throw const SeedRefused('original-send-review-required');
  }
  return (dialog!, shown!);
}

/// Exact UI identity is required only before the ordinary pointer down/up.
final class LabSendUiReview {
  LabSendUiReview._(
    this.binding, this.button, this.dialog, this.intent, this.witness,
    this.center,
  ) : requestId = intent.requestId;

  final LabSendUiBinding binding;
  final Element button;
  final Element dialog;
  final SendIntent intent;
  final Object requestId;
  final LabTransferWitness witness;
  final Offset center;

  void requireReady(Element currentButton, {required Offset center}) {
    binding.requireForm();
    final (Element currentDialog, SendConfirmation shown) =
        _shown(currentButton);
    if (center != this.center) {
      throw const SeedRefused('original-send-review-center-changed');
    }
    if (!identical(currentButton, button)) {
      throw const SeedRefused('original-send-review-button-changed');
    }
    if (!identical(currentDialog, dialog)) {
      throw const SeedRefused('original-send-review-dialog-changed');
    }
    if (!identical(shown.intent, intent) ||
        !identical(shown.intent.requestId, requestId)) {
      throw const SeedRefused('original-send-review-intent-changed');
    }
    if (!binding.owner.matchesOriginalReview(intent)) {
      throw const SeedRefused('original-send-review-draft-changed');
    }
    witness.requireReady();
  }
}
