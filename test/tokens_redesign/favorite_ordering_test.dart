import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/l10n/app_localizations.dart';
import 'package:zenon_syrius_wallet_flutter/l10n/l10n.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/token_favorite/repository/favorite_tokens_repository.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/token_favorite/view/token_favorite.dart';
import 'package:zenon_syrius_wallet_flutter/utils/app_theme.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

import 'support.dart';

class _OptimisticFavorites extends TokenTestFavorites {
  @override
  Future<void> add(TokenStandard standard) async {
    standards.add(standard.toString());
    await pending!.future;
  }
}

Widget _host(Widget child) => MaterialApp(
  theme: AppTheme.darkTheme,
  localizationsDelegates: appLocalizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: Center(child: child)),
);

void main() {
  final Token token = tokenFixture(1);

  test(
    'an optimistic underlying write remains invisible until persistence',
    () async {
      final _OptimisticFavorites storage = _OptimisticFavorites()
        ..pending = Completer<void>();
      final PersistedFavoriteTokensRepository repository =
          PersistedFavoriteTokensRepository(storage);
      final Future<void> result = repository.add(token.tokenStandard);
      await tokenTurns();
      expect(storage.contains(token.tokenStandard), isTrue);
      expect(repository.contains(token.tokenStandard), isFalse);
      storage.pending!.complete();
      await result;
      expect(repository.contains(token.tokenStandard), isTrue);
    },
  );

  test('failed persistence retains previous exact membership', () async {
    final TokenTestFavorites storage = TokenTestFavorites()
      ..failure = StateError('isolated persistence failure');
    final PersistedFavoriteTokensRepository repository =
        PersistedFavoriteTokensRepository(storage);
    await expectLater(repository.add(token.tokenStandard), throwsStateError);
    expect(repository.contains(token.tokenStandard), isFalse);
    expect(
      repository.contains(tokenFixture(2, symbol: token.symbol).tokenStandard),
      isFalse,
    );
  });

  test(
    'opposite concurrent requests persist in their explicit order',
    () async {
      final TokenTestFavorites storage = TokenTestFavorites()
        ..pending = Completer<void>();
      final PersistedFavoriteTokensRepository repository =
          PersistedFavoriteTokensRepository(storage);
      final Future<void> added = repository.add(token.tokenStandard);
      final Future<void> removed = repository.remove(token.tokenStandard);
      await tokenTurns();
      expect(repository.contains(token.tokenStandard), isFalse);
      storage.pending!.complete();
      await added;
      await removed;
      expect(repository.contains(token.tokenStandard), isFalse);
      expect(storage.contains(token.tokenStandard), isFalse);
    },
  );

  testWidgets(
    'persisted view callback precedes a delayed optional notification',
    (
      WidgetTester tester,
    ) async {
      final TokenTestFavorites storage = TokenTestFavorites()
        ..pending = Completer<void>();
      final Completer<void> notification = Completer<void>();
      final List<String> events = <String>[];
      await tester.pumpWidget(
        _host(
          TokenFavorite(
            token: token,
            repository: storage,
            callback: () => events.add('view'),
            notify: ({required bool favorite, required Token token}) {
              expect(storage.contains(token.tokenStandard), isTrue);
              events.add('notification');
              return notification.future;
            },
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('token_favorite_button')));
      await tester.pump();
      expect(events, isEmpty);
      storage.pending!.complete();
      for (int turn = 0; turn < 6 && events.isEmpty; turn++) {
        await tester.pump(const Duration(milliseconds: 1));
      }
      expect(events, <String>['view', 'notification']);
      expect(storage.contains(token.tokenStandard), isTrue);
      expect(find.byTooltip('Remove from favorites'), findsOneWidget);
      notification.complete();
      await tester.pump(const Duration(milliseconds: 240));
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'optional callback and notification failures cannot replace success',
    (
      WidgetTester tester,
    ) async {
      final TokenTestFavorites storage = TokenTestFavorites();
      await tester.pumpWidget(
        _host(
          TokenFavorite(
            token: token,
            repository: storage,
            callback: () => throw StateError('optional view disposed'),
            notify: ({required bool favorite, required Token token}) async =>
                throw StateError('optional notification failed'),
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('token_favorite_button')));
      for (int turn = 0; turn < 6; turn++) {
        await tester.pump(const Duration(milliseconds: 1));
      }
      expect(storage.contains(token.tokenStandard), isTrue);
      expect(find.byTooltip('Remove from favorites'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(milliseconds: 240));
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
