import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/blocs/blocs.dart';
import 'package:zenon_syrius_wallet_flutter/main.dart';
import 'package:zenon_syrius_wallet_flutter/model/model.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/token_favorite/bloc/token_favorite_bloc.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/token_favorite/exceptions/favorite_tokens_exception.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/token_favorite/repository/favorite_tokens_repository.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/tokens/widgets/token_row_action.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/extensions/buildcontext_extension.dart';
import 'package:zenon_syrius_wallet_flutter/utils/app_theme.dart';
import 'package:zenon_syrius_wallet_flutter/utils/notification_utils.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

const String _kAddTooltip = 'Add to favorites';
const String _kRemoveTooltip = 'Remove from favorites';

/// Optional delivery after the exact favorite membership has been persisted.
typedef TokenFavoriteNotification =
    Future<void> Function({
      required bool favorite,
      required Token token,
    });

/// The star of a token row: adds the token to the wallet's favorites, or
/// takes it out.
class TokenFavorite extends StatelessWidget {
  /// Creates a [TokenFavorite].
  const TokenFavorite({
    required this._token,
    required this._callback,
    this.repository,
    this.notify,
    super.key,
  });
  final Token _token;
  final VoidCallback _callback;

  /// A shared page repository prevents optimistic membership while persisting.
  final FavoriteTokensRepository? repository;

  /// Optional notification delivery, after the committed view callback.
  final TokenFavoriteNotification? notify;

  @override
  Widget build(BuildContext context) {
    return BlocProvider<TokenFavoriteBloc>(
      create: (_) => TokenFavoriteBloc(
        tokenStandard: _token.tokenStandard,
        repository: repository,
      ),
      child: _View(callback: _callback, token: _token, notify: notify),
    );
  }
}

class _View extends StatelessWidget {
  const _View({required this._callback, required this._token, this.notify});

  final VoidCallback _callback;
  final Token _token;
  final TokenFavoriteNotification? notify;

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<TokenFavoriteBloc, TokenFavoriteState>(
      listener: _onTokenFavoriteStateChanged,
      // While the change is being saved the star keeps the look it had: the
      // bloc ignores a second press, and a spinner in a list row would only
      // make the row jump.
      buildWhen: (_, TokenFavoriteState current) =>
          current is! TokenFavoriteLoading,
      builder: (BuildContext context, TokenFavoriteState state) {
        final bool isFavorite = switch (state) {
          TokenFavoriteFavorited() => true,
          TokenFavoriteNotFavorited() || TokenFavoriteLoading() => false,
          TokenFavoriteFailure(:final FavoriteTokensException exception) =>
            exception is RemovingFromFavoriteTokensException,
        };
        return TokenRowAction(
          key: const Key('token_favorite_button'),
          tooltip: isFavorite ? _kRemoveTooltip : _kAddTooltip,
          onPressed: () => context.read<TokenFavoriteBloc>().add(
            isFavorite
                ? const TokenFavoriteRemoved()
                : const TokenFavoriteAdded(),
          ),
          icon: AnimatedSwitcher(
            duration: Durations.short4,
            switchInCurve: Easing.emphasizedDecelerate,
            switchOutCurve: Easing.emphasizedAccelerate,
            transitionBuilder: (Widget child, Animation<double> animation) =>
                ScaleTransition(scale: animation, child: child),
            child: Icon(
              isFavorite ? Icons.star : Icons.star_border,
              key: ValueKey<bool>(isFavorite),
              color: isFavorite
                  ? AppTokens.of(context).znnInk
                  : AppTokens.of(context).faint,
            ),
          ),
        );
      },
    );
  }

  void _onTokenFavoriteStateChanged(
    BuildContext context,
    TokenFavoriteState state,
  ) {
    if (state is TokenFavoriteFavorited) {
      _notifyView();
      unawaited(_sendAddedNotification(context));
    } else if (state is TokenFavoriteNotFavorited) {
      _notifyView();
      unawaited(_sendRemovedNotification(context));
    } else if (state is TokenFavoriteFailure) {
      final String title = switch (state.exception) {
        AddingToFavoriteTokensException() =>
          context.l10n.errorAddingTokenToFavorites(_token.name),
        RemovingFromFavoriteTokensException() =>
          context.l10n.errorRemovingTokenFromFavorites(_token.name),
      };
      unawaited(_sendFailure(state.exception, title));
    }
  }

  void _notifyView() {
    try {
      _callback();
    } on Object {
      // A disposed optional view cannot replace the persisted membership.
    }
  }

  Future<void> _sendFailure(FavoriteTokensException error, String title) async {
    try {
      await NotificationUtils.sendNotificationError(error, title);
    } on Object {
      // Notification delivery is optional after a known storage failure.
    }
  }

  Future<void> _sendAddedNotification(BuildContext context) async {
    try {
      if (notify != null) {
        await notify!(favorite: true, token: _token);
        return;
      }
      await sl.get<NotificationsBloc>().addNotification(
        WalletNotification(
          title: context.l10n.tokenAddedToFavorites(_token.name),
          details: context.l10n.tokenSummary(
            _token.name,
            _token.symbol,
            _token.tokenStandard,
          ),
          timestamp: DateTime.now().millisecondsSinceEpoch,
          type: NotificationType.addedTokenFavourite,
        ),
      );
    } on Object {
      // Membership is already persisted and the view already received it.
    }
  }

  Future<void> _sendRemovedNotification(BuildContext context) async {
    try {
      if (notify != null) {
        await notify!(favorite: false, token: _token);
        return;
      }
      await sl.get<NotificationsBloc>().addNotification(
        WalletNotification(
          title: context.l10n.tokenRemovedFromFavorites(_token.name),
          details: context.l10n.tokenSummary(
            _token.name,
            _token.symbol,
            _token.tokenStandard,
          ),
          timestamp: DateTime.now().millisecondsSinceEpoch,
          type: NotificationType.removedTokenFavourite,
        ),
      );
    } on Object {
      // Membership is already persisted and the view already received it.
    }
  }
}
