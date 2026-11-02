import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/send/bloc/send_transaction/send_transaction_bloc.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/tokens/actions/token_action_publisher.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/tokens/widgets/token_inline_actions.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/extensions/buildcontext_extension.dart';
import 'package:zenon_syrius_wallet_flutter/utils/global.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/reusable_widgets/modals/frosted_route.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/reusable_widgets/modals/modal_chrome.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

/// Existing token dialogs use the same exact proof and publisher as the row.
class TokenActionDialog extends StatefulWidget {
  /// [publisher] is captured before the dialog crosses the Navigator boundary.
  const TokenActionDialog({
    required this.token,
    required this.mode,
    this.publisher,
    this.isCurrent,
    this.question,
    this.allowCapture = true,
    super.key,
  });

  /// Metadata describes the dialog. It cannot authorize publication.
  final Token token;

  /// Legacy dialogs keep their existing one-action identity.
  final TokenActionMode mode;

  /// Original selected account, SDK APIs and shared sender.
  final TokenActionPublisher? publisher;

  /// Optional original caller authority, captured before opening.
  final bool Function()? isCurrent;

  /// Allows finite source widget tests without a modal interaction.
  final TokenActionQuestion? question;

  /// A failed original capture cannot be replaced by another selected account.
  final bool allowCapture;

  /// Opens only with the caller's captured sender and wallet context.
  static Future<void> open(
    BuildContext context, {
    required Token token,
    required TokenActionMode mode,
  }) {
    final String? selected = kSelectedAddress;
    TokenActionPublisher? publisher;
    try {
      if (selected != null) {
        publisher = TokenActionPublisher.capture(
          sender: context.read<SendTransactionBloc>(),
          address: selected,
        );
      }
    } on Object {
      publisher = null;
    }
    return showFrostedDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => TokenActionDialog(
        token: token,
        mode: mode,
        publisher: publisher,
        allowCapture: false,
      ),
    );
  }

  @override
  State<TokenActionDialog> createState() => _TokenActionDialogState();
}

class _TokenActionDialogState extends State<TokenActionDialog> {
  int _epoch = 0;
  bool _busy = false;
  TokenActionSubmission? _submission;
  ModalRoute<dynamic>? _route;
  NavigatorState? _navigator;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final ModalRoute<dynamic>? route = ModalRoute.of(context);
    final NavigatorState? navigator = Navigator.maybeOf(context);
    if (_route != null &&
        (!identical(_route, route) || !identical(_navigator, navigator))) {
      _epoch++;
      _submission = null;
      _busy = false;
    }
    _route = route;
    _navigator = navigator;
  }

  @override
  void didUpdateWidget(TokenActionDialog oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.token.tokenStandard != widget.token.tokenStandard ||
        !identical(oldWidget.publisher, widget.publisher) ||
        oldWidget.mode != widget.mode ||
        oldWidget.allowCapture != widget.allowCapture) {
      _epoch++;
      _submission = null;
      _busy = false;
    }
  }

  Future<void> _settleChrome(
    TokenActionSubmission submission,
    bool Function() owns,
  ) async {
    try {
      await submission.settlement;
    } on Object {
      // Even an exceptional original Future has finished using this chrome.
    }
    if (!owns()) return;
    setState(() {
      _submission = null;
      _busy = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final int epoch = _epoch;
    final ModalRoute<dynamic>? route = _route;
    final NavigatorState? navigator = _navigator;
    final TokenActionPublisher? publisher = widget.publisher;
    final String standard = widget.token.tokenStandard.toString();
    final TokenActionMode mode = widget.mode;
    bool presentation() =>
        mounted &&
        epoch == _epoch &&
        route != null &&
        route.isActive &&
        navigator != null &&
        navigator.mounted &&
        identical(_route, route) &&
        identical(_navigator, navigator) &&
        identical(route.navigator, navigator) &&
        (widget.isCurrent?.call() ?? true);
    bool current() => presentation() && route!.isCurrent;
    final String label = switch (widget.mode) {
      TokenActionMode.mint => context.l10n.mint,
      TokenActionMode.burn => context.l10n.burn,
      TokenActionMode.transfer => context.l10n.tokensTransferOwnership,
      TokenActionMode.flags => context.l10n.tokensFlags,
    };
    return PopScope(
      canPop: !_busy,
      child: DialogCard(
        title: '$label ${widget.token.symbol}',
        body: TokenInlineActions(
          token: widget.token,
          fixedMode: widget.mode,
          publisher: widget.publisher,
          isCurrent: presentation,
          question: widget.question,
          showFacts: false,
          authorityEpoch: epoch,
          allowCapture: widget.allowCapture,
          onSubmission: (TokenActionSubmission submission) {
            if (!presentation() ||
                _submission != null ||
                submission.intent.standard.toString() != standard ||
                submission.intent.mode != mode ||
                !identical(
                  submission.intent.proof.session,
                  submission.publisher.session,
                ) ||
                (publisher != null &&
                    !identical(publisher, submission.publisher))) {
              return;
            }
            bool owns() =>
                mounted &&
                epoch == _epoch &&
                identical(_submission, submission) &&
                identical(widget.publisher, publisher) &&
                widget.token.tokenStandard.toString() == standard &&
                widget.mode == mode &&
                route != null &&
                route.isActive &&
                navigator != null &&
                navigator.mounted &&
                identical(_route, route) &&
                identical(_navigator, navigator) &&
                identical(route.navigator, navigator);
            setState(() {
              _submission = submission;
              _busy = true;
            });
            unawaited(_settleChrome(submission, owns));
          },
          onOutcome: (TokenActionOutcome outcome) {
            if (current() && outcome.status == TokenActionStatus.submitted) {
              _epoch++;
              navigator!.pop();
            }
          },
        ),
        actions: <Widget>[
          TextButton(
            style: quietButtonStyle(context),
            onPressed: _busy
                ? null
                : () {
                    if (_busy || !current()) return;
                    _epoch++;
                    navigator!.pop();
                  },
            child: Text(context.l10n.cancel),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _epoch++;
    _submission = null;
    super.dispose();
  }
}
