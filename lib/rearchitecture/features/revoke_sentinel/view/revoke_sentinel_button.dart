import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/card_parts/card_parts.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/node_owner/node_owner_publisher.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/send/bloc/send_transaction/send_transaction_bloc.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/sentinels_by_owner/bloc/sentinels_by_owner_bloc.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/utils.dart';
import 'package:zenon_syrius_wallet_flutter/utils/plasma_purpose.dart';
import 'package:zenon_syrius_wallet_flutter/utils/utils.dart';
import 'package:zenon_syrius_wallet_flutter/utils/wallet_action_context.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/reusable_widgets/modals/frosted_route.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/reusable_widgets/modals/modal_chrome.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

class _RevokeSnapshot {
  _RevokeSnapshot({
    required this.reader,
    required this.read,
    required this.context,
    required this.sentinel,
    required this.sender,
    required this.epoch,
    required this.boundary,
  });

  final SentinelsByOwnerBloc reader;
  final Object read;
  final WalletActionContext context;
  final SentinelInfo sentinel;
  final SendTransactionBloc sender;
  final int epoch;
  final DateTime? boundary;
  final Object? page = kCurrentPage;
  bool used = false;
}

/// The existing revoke action, bound to one completed owner read and account.
class RevokeSentinelButton extends StatefulWidget {
  /// Keeps both questions and publication on the original owner and sender.
  const RevokeSentinelButton({
    required this.sentinel,
    required this.ownerReader,
    required this.onRevoked,
    this.sender,
    super.key,
  });

  /// The exact owned record shown by the owner panel.
  final SentinelInfo sentinel;

  /// The caller's reader, including its opaque completed-read identity.
  final SentinelsByOwnerBloc ownerReader;

  /// The application's sender shared with transfers and collection.
  final SendTransactionBloc? sender;

  /// Refreshes only while the original panel is still current.
  final VoidCallback onRevoked;

  @override
  State<RevokeSentinelButton> createState() => _RevokeSentinelButtonState();
}

class _RevokeSentinelButtonState extends State<RevokeSentinelButton> {
  int _epoch = 0;
  bool _visible = true;
  bool _disposed = false;
  Object? _operation;
  Object? _boundaryRead;
  DateTime? _boundary;
  ModalRoute<dynamic>? _pageRoute;
  FrostedDialogRoute<bool>? _confirmationRoute;
  NavigatorState? _confirmationNavigator;

  bool get _onPage => _pageRoute?.isCurrent ?? true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final ModalRoute<dynamic>? route = ModalRoute.of(context);
    final bool visible = TickerMode.valuesOf(context).enabled;
    if (!identical(route, _pageRoute) || _visible && !visible) {
      _invalidate();
    }
    _pageRoute = route;
    _visible = visible;
  }

  @override
  void didUpdateWidget(RevokeSentinelButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.ownerReader, widget.ownerReader) ||
        !identical(oldWidget.sentinel, widget.sentinel) ||
        !identical(oldWidget.sender, widget.sender)) {
      _invalidate();
    }
  }

  void _invalidate() {
    _epoch++;
    _dismissOwnedConfirmation();
  }

  @override
  void dispose() {
    _disposed = true;
    _invalidate();
    super.dispose();
  }

  bool _current(_RevokeSnapshot snapshot) =>
      mounted &&
      !_disposed &&
      _visible &&
      snapshot.epoch == _epoch &&
      snapshot.page == kCurrentPage &&
      (_pageRoute?.isActive ?? true) &&
      identical(snapshot.reader, widget.ownerReader) &&
      snapshot.context.isCurrent &&
      snapshot.reader.ownsRead(snapshot.read, snapshot.context.ownerAddress);

  bool _revocable(_RevokeSnapshot snapshot) =>
      snapshot.sentinel.active &&
      snapshot.sentinel.isRevocable &&
      snapshot.boundary != null &&
      snapshot.boundary!.isAfter(DateTime.now().toUtc());

  bool _canContinue(_RevokeSnapshot snapshot, Object operation) =>
      _current(snapshot) &&
      _onPage &&
      identical(_operation, operation) &&
      !snapshot.sender.busy.value &&
      _revocable(snapshot);

  _RevokeSnapshot? _capture(SendTransactionBloc sender) {
    final SentinelsByOwnerBloc reader = widget.ownerReader;
    final Object? read = reader.readOwner;
    final String owner = widget.sentinel.owner.toString();
    if (read == null || !reader.ownsRead(read, owner)) return null;
    final FetchState<List<SentinelInfo>> state = reader.state;
    if (state is! FetchPopulated<List<SentinelInfo>> ||
        !state.data.any(
          (SentinelInfo item) =>
              item.owner.toString() == owner &&
              item.active &&
              item.isRevocable &&
              item.registrationTimestamp ==
                  widget.sentinel.registrationTimestamp,
        )) {
      return null;
    }
    final WalletActionContext? ownerContext = WalletActionContext.capture(
      owner,
    );
    if (ownerContext == null) return null;
    final SentinelInfo copy = SentinelInfo.fromJson(widget.sentinel.toJson());
    if (!identical(_boundaryRead, read)) {
      _boundaryRead = read;
      final int maximum =
          8640000000000 -
          DateTime.now().millisecondsSinceEpoch ~/
              Duration.millisecondsPerSecond;
      _boundary = copy.revokeCooldown > 0 && copy.revokeCooldown < maximum
          ? DateTime.now().toUtc().add(Duration(seconds: copy.revokeCooldown))
          : null;
    }
    return _RevokeSnapshot(
      reader: reader,
      read: read,
      context: ownerContext,
      sentinel: copy,
      sender: sender,
      epoch: _epoch,
      boundary: _boundary,
    );
  }

  Future<bool> _verify(_RevokeSnapshot snapshot) async {
    if (!_current(snapshot) || !_revocable(snapshot)) return false;
    final SentinelInfo? actual = await snapshot.context.client.embedded.sentinel
        .getByOwner(Address.parse(snapshot.context.ownerAddress));
    return _current(snapshot) &&
        _revocable(snapshot) &&
        actual != null &&
        actual.owner.toString() == snapshot.context.ownerAddress &&
        actual.registrationTimestamp ==
            snapshot.sentinel.registrationTimestamp &&
        actual.active &&
        actual.isRevocable;
  }

  Future<void> _revoke(_RevokeSnapshot snapshot) async {
    if (snapshot.used ||
        _operation != null ||
        !_current(snapshot) ||
        !_onPage ||
        !_revocable(snapshot) ||
        snapshot.sender.busy.value) {
      return;
    }
    snapshot.used = true;
    final Object operation = Object();
    final VoidCallback onRevoked = widget.onRevoked;
    setState(() => _operation = operation);
    final NodeOwnerPublisher publisher = NodeOwnerPublisher(
      sender: snapshot.sender,
      context: snapshot.context,
      verifyOwner: () => _verify(snapshot),
      isCurrent: () =>
          _current(snapshot) &&
          _onPage &&
          identical(_operation, operation) &&
          _revocable(snapshot),
    );
    try {
      if (await _confirm(snapshot, operation, finalConfirmation: false) !=
              true ||
          !_canContinue(snapshot, operation)) {
        return;
      }
      if (await _confirm(snapshot, operation, finalConfirmation: true) !=
              true ||
          !_canContinue(snapshot, operation)) {
        return;
      }
      await publisher.createAccountBlock(
        snapshot.context.client.embedded.sentinel.revoke(),
        PlasmaPurpose.disassembleSentinel.message,
        address: Address.parse(snapshot.context.ownerAddress),
        waitForRequiredPlasma: true,
      );
      if (_current(snapshot) && _onPage) {
        try {
          onRevoked();
        } on Object {
          // Optional UI refresh cannot replace the original accepted result.
        }
      }
    } on Object {
      if (mounted && _current(snapshot) && _onPage) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(content: Text(context.l10n.sendOutcomeUncertain)),
        );
      }
    } finally {
      if (mounted && !_disposed && identical(_operation, operation)) {
        setState(() => _operation = null);
      }
    }
  }

  Future<bool?> _confirm(
    _RevokeSnapshot snapshot,
    Object operation, {
    required bool finalConfirmation,
  }) async {
    final NavigatorState navigator = Navigator.of(context);
    final CapturedThemes themes = InheritedTheme.capture(
      from: context,
      to: navigator.context,
    );
    late final FrostedDialogRoute<bool> route;
    bool answered = false;
    void answer({required bool accepted}) {
      if (!mounted ||
          _disposed ||
          answered ||
          !identical(_confirmationRoute, route) ||
          !identical(route.navigator, navigator) ||
          !route.isCurrent) {
        return;
      }
      answered = true;
      final bool valid =
          _current(snapshot) &&
          identical(_operation, operation) &&
          !snapshot.sender.busy.value &&
          _revocable(snapshot);
      navigator.pop(accepted && valid);
    }

    route = FrostedDialogRoute<bool>(
      barrierDismissible: false,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      traversalEdgeBehavior: TraversalEdgeBehavior.closedLoop,
      transitionDuration: const Duration(milliseconds: 150),
      pageBuilder: (BuildContext dialog, _, _) => themes.wrap(
        SafeArea(
          child: Builder(
            builder: (BuildContext dialog) => DialogCard(
              key: Key(
                finalConfirmation
                    ? 'sentinel_owner_revoke_final_dialog'
                    : 'sentinel_owner_revoke_first_dialog',
              ),
              title: finalConfirmation
                  ? dialog.l10n.pillarOwnerRevokeFinalTitle
                  : dialog.l10n.pillarOwnerDisassemble,
              body: Text(
                finalConfirmation
                    ? dialog.l10n.sentinelOwnerRevokeConsequence(
                        snapshot.context.ownerAddress,
                      )
                    : dialog.l10n.disassembleSentinelConfirm(
                        snapshot.context.ownerAddress,
                      ),
                style: AppTokens.of(dialog).dataText,
                textDirection: TextDirection.ltr,
              ),
              actions: <Widget>[
                TextButton(
                  key: const Key('sentinel_owner_revoke_cancel'),
                  style: quietButtonStyle(dialog),
                  onPressed: () => answer(accepted: false),
                  child: Text(dialog.l10n.cancel),
                ),
                OutlinedButton(
                  key: const Key('sentinel_owner_revoke_accept'),
                  style: secondaryButtonStyle(dialog),
                  onPressed: () => answer(accepted: true),
                  child: Text(
                    finalConfirmation
                        ? dialog.l10n.pillarOwnerDisassemble
                        : dialog.l10n.continueText,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    _confirmationRoute = route;
    _confirmationNavigator = navigator;
    try {
      return await navigator.push<bool>(route);
    } finally {
      answered = true;
      if (identical(_confirmationRoute, route)) {
        _confirmationRoute = null;
        _confirmationNavigator = null;
      }
    }
  }

  void _dismissOwnedConfirmation() {
    final FrostedDialogRoute<bool>? route = _confirmationRoute;
    final NavigatorState? navigator = _confirmationNavigator;
    _confirmationRoute = null;
    _confirmationNavigator = null;
    if (route == null || navigator == null) return;
    scheduleMicrotask(() {
      if (navigator.mounted &&
          identical(route.navigator, navigator) &&
          route.isActive) {
        navigator.removeRoute(route);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final SendTransactionBloc sender =
        widget.sender ?? context.read<SendTransactionBloc>();
    return ValueListenableBuilder<bool>(
      valueListenable: sender.busy,
      builder: (_, bool busy, _) {
        final _RevokeSnapshot? snapshot = _capture(sender);
        return OutlinedButton.icon(
          key: const Key('sentinel_owner_revoke'),
          style: cardSecondaryButtonStyle(
            context,
            line: Theme.of(context).colorScheme.error,
          ),
          onPressed:
              !busy &&
                  _operation == null &&
                  snapshot != null &&
                  _current(snapshot) &&
                  _revocable(snapshot)
              ? () => unawaited(_revoke(snapshot))
              : null,
          icon: const Icon(Icons.close, size: 16),
          iconAlignment: IconAlignment.end,
          label: Text(context.l10n.pillarOwnerDisassemble),
        );
      },
    );
  }
}
