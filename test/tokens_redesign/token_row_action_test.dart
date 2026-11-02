import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/tokens/widgets/token_row_action.dart';
import 'package:zenon_syrius_wallet_flutter/utils/app_theme.dart';

const Key _row = Key('token-action-column');
const List<String> _tooltips = <String>[
  'Mint',
  'Burn',
  'Transfer ownership',
  'Visit domain',
];
const List<IconData> _icons = <IconData>[
  Icons.add_circle_outline,
  Icons.local_fire_department_outlined,
  Icons.swap_horiz,
  Icons.open_in_new,
];

Key _actionKey(int index) => ValueKey<String>('token-row-action-$index');

Widget _host({
  required ThemeData theme,
  required TextDirection direction,
  required List<VoidCallback?> callbacks,
}) => MaterialApp(
  theme: theme,
  home: Directionality(
    textDirection: direction,
    child: Scaffold(
      body: Center(
        // Row children keep their intrinsic width and height. A constraint
        // on each child would hide an oversized or undersized tap target.
        child: SizedBox(
          key: _row,
          width: 128,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              for (int index = 0; index < _tooltips.length; index++)
                TokenRowAction(
                  key: _actionKey(index),
                  tooltip: _tooltips[index],
                  icon: Icon(_icons[index]),
                  onPressed: callbacks[index],
                ),
            ],
          ),
        ),
      ),
    ),
  ),
);

void main() {
  for (final ThemeData appTheme in <ThemeData>[
    AppTheme.darkTheme,
    AppTheme.lightTheme,
  ]) {
    for (final TextDirection direction in TextDirection.values) {
      for (final bool enabled in <bool>[true, false]) {
        for (final MaterialTapTargetSize? tapTarget in <MaterialTapTargetSize?>[
          null,
          ...MaterialTapTargetSize.values,
        ]) {
          final String targetName = tapTarget?.name ?? 'default';
          testWidgets(
            '${appTheme.brightness.name} ${direction.name} '
            '${enabled ? 'enabled' : 'disabled'} $targetName token actions '
            'fit 128 px with working callbacks and semantics',
            (WidgetTester tester) async {
              final SemanticsHandle semantics = tester.ensureSemantics();
              try {
                final ThemeData theme = tapTarget == null
                    ? appTheme
                    : appTheme.copyWith(materialTapTargetSize: tapTarget);
                final List<int> activated = <int>[];
                final List<VoidCallback?> callbacks = <VoidCallback?>[
                  for (int index = 0; index < _tooltips.length; index++)
                    if (enabled) () => activated.add(index) else null,
                ];
                await tester.pumpWidget(
                  _host(
                    theme: theme,
                    direction: direction,
                    callbacks: callbacks,
                  ),
                );
                expect(tester.takeException(), isNull);
                expect(find.byType(TokenRowAction), findsNWidgets(4));
                final Rect column = tester.getRect(find.byKey(_row));
                expect(column.size, const Size(128, 32));
                Rect? previous;
                for (int index = 0; index < _tooltips.length; index++) {
                  final Finder action = find.byKey(_actionKey(index));
                  final Rect bounds = tester.getRect(action);
                  expect(bounds.size, const Size.square(32));
                  expect(bounds.left, greaterThanOrEqualTo(column.left));
                  expect(bounds.right, lessThanOrEqualTo(column.right));
                  expect(bounds.top, column.top);
                  expect(bounds.bottom, column.bottom);
                  final Rect? previousBounds = previous;
                  if (previousBounds != null) {
                    expect(
                      direction == TextDirection.ltr
                          ? bounds.left
                          : bounds.right,
                      direction == TextDirection.ltr
                          ? previousBounds.right
                          : previousBounds.left,
                    );
                  }
                  previous = bounds;

                  // The keyed public widget remains an IconButton for the
                  // existing token-row callers that inspect its callback.
                  expect(
                    tester.widget<IconButton>(action).onPressed,
                    same(callbacks[index]),
                  );
                  final Finder button = find.descendant(
                    of: action,
                    matching: find.byType(IconButton),
                  );
                  expect(button, findsOneWidget);
                  expect(tester.getSize(button), const Size.square(32));
                  expect(
                    tester.widget<IconButton>(button).onPressed,
                    same(callbacks[index]),
                  );
                  expect(find.byTooltip(_tooltips[index]), findsOneWidget);
                  final SemanticsNode node = tester.getSemantics(action);
                  expect(
                    node.getSemanticsData().flagsCollection.isButton,
                    isTrue,
                  );
                  expect(
                    node.getSemanticsData().flagsCollection.isEnabled,
                    enabled ? ui.Tristate.isTrue : ui.Tristate.isFalse,
                  );
                  expect(
                    node.getSemanticsData().tooltip,
                    _tooltips[index],
                  );
                  expect(
                    node.getSemanticsData().hasAction(ui.SemanticsAction.tap),
                    enabled,
                  );
                  await tester.tapAt(bounds.center);
                  await tester.pump();
                }
                expect(activated, enabled ? <int>[0, 1, 2, 3] : isEmpty);

                for (int index = 0; index < _tooltips.length; index++) {
                  final SemanticsNode node = tester.getSemantics(
                    find.byKey(_actionKey(index)),
                  );
                  node.owner!.performAction(node.id, ui.SemanticsAction.tap);
                  await tester.pump();
                }
                expect(
                  activated,
                  enabled ? <int>[0, 1, 2, 3, 0, 1, 2, 3] : isEmpty,
                );
                expect(tester.takeException(), isNull);
                await tester.pumpWidget(const SizedBox.shrink());
              } finally {
                semantics.dispose();
              }
            },
          );
        }
      }
    }
  }
}
