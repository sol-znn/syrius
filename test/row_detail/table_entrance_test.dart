import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/l10n/l10n.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/infinite_scroll_table/infinite_scroll_table.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/list_entrance.dart';
import 'package:zenon_syrius_wallet_flutter/utils/app_theme.dart';

Widget _app(List<String> items, List<String> actions) => MaterialApp(
  theme: AppTheme.darkTheme,
  localizationsDelegates: appLocalizationsDelegates,
  supportedLocales: const <Locale>[Locale('en')],
  home: Scaffold(
    body: ListEntrance(
      itemKeys: <LocalKey>[
        for (final String item in items) ValueKey<String>(item),
      ],
      child: InfiniteScrollTable<String>(
        items: items,
        hasReachedMax: true,
        columns: const <InfiniteScrollTableColumnType>[
          InfiniteScrollTableColumnType.blank,
        ],
        itemKeyGenerator: ValueKey<String>.new,
        rowBuilder: (String item, int index, Widget row) => ListEntranceItem(
          key: ValueKey<String>(item),
          child: row,
        ),
        generateRowCells: (String item) => <Widget>[
          InfiniteScrollTableCell(
            child: TextButton(
              onPressed: () => actions.add(item),
              child: Text(item),
            ),
          ),
        ],
        onScrollReachedBottom: () {},
      ),
    ),
  ),
);

void main() {
  testWidgets(
    'table wrappers keep row input and do not replay known identities',
    (
      WidgetTester tester,
    ) async {
      final List<String> actions = <String>[];
      await tester.pumpWidget(_app(<String>['first', 'second'], actions));
      await tester.pumpAndSettle();
      await tester.tap(find.text('first'));
      expect(actions, <String>['first']);

      await tester.pumpWidget(_app(<String>['second', 'first'], actions));
      // Reordering does not grant a new entrance to an already known row.
      expect(find.text('first').hitTestable(), findsOneWidget);
      expect(find.text('second').hitTestable(), findsOneWidget);
      await tester.tap(find.text('second'));
      expect(actions, <String>['first', 'second']);
      expect(tester.takeException(), isNull);
    },
  );
}
