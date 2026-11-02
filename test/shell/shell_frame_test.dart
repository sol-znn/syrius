import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/shell/shell_frame.dart';

class _Owner extends StatefulWidget {
  const _Owner({required this.onCreate, required this.onDispose});

  final VoidCallback onCreate;
  final VoidCallback onDispose;

  @override
  State<_Owner> createState() => _OwnerState();
}

class _OwnerState extends State<_Owner> {
  final TextEditingController password = TextEditingController();

  @override
  void initState() {
    super.initState();
    widget.onCreate();
  }

  @override
  void dispose() {
    password.dispose();
    widget.onDispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox.expand(
    child: Center(child: TextField(controller: password)),
  );
}

void main() {
  testWidgets(
    'entry status changes preserve the mounted authentication owner',
    (
      WidgetTester tester,
    ) async {
      final ValueNotifier<bool> locked = ValueNotifier<bool>(true);
      addTearDown(locked.dispose);
      int created = 0;
      int disposed = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ShellFrame(
              locked: locked,
              rail: const SizedBox(width: 76),
              page: _Owner(
                onCreate: () => created++,
                onDispose: () => disposed++,
              ),
              status: const SizedBox(height: 18),
            ),
          ),
        ),
      );
      final _OwnerState owner = tester.state<_OwnerState>(find.byType(_Owner));
      await tester.enterText(find.byType(TextField), 'local fixture');
      for (final bool value in <bool>[false, true, false]) {
        locked.value = value;
        await tester.pump();
        expect(tester.state(find.byType(_Owner)), same(owner));
        expect(owner.password.text, 'local fixture');
        expect(created, 1);
        expect(disposed, 0);
      }
      await tester.pumpWidget(const SizedBox.shrink());
      expect(disposed, 1);
    },
  );

  for (final TextDirection direction in TextDirection.values) {
    for (final bool scrollable in <bool>[false, true]) {
      testWidgets(
        'working gutters match the reference in $direction, scroll $scrollable',
        (WidgetTester tester) async {
          tester.view.physicalSize = const Size(1280, 780);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final ValueNotifier<bool> locked = ValueNotifier<bool>(false);
          addTearDown(locked.dispose);
          const Key rail = ValueKey<String>('reference rail');
          const Key page = ValueKey<String>('reference page');
          const Key content = ValueKey<String>('reference first content');
          const Key status = ValueKey<String>('reference status');
          await tester.pumpWidget(
            MaterialApp(
              home: Directionality(
                textDirection: direction,
                child: Scaffold(
                  body: Column(
                    children: <Widget>[
                      const SizedBox(height: 32),
                      Expanded(
                        child: ShellFrame(
                          locked: locked,
                          rail: const SizedBox(key: rail, width: 56),
                          page: SizedBox.expand(
                            key: page,
                            child: scrollable
                                ? ListView(
                                    children: const <Widget>[
                                      SizedBox(key: content, height: 20),
                                      SizedBox(height: 1000),
                                    ],
                                  )
                                : const Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: <Widget>[
                                      SizedBox(key: content, height: 20),
                                      Expanded(child: SizedBox()),
                                    ],
                                  ),
                          ),
                          status: const SizedBox(
                            key: status,
                            width: double.infinity,
                            height: 44,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
          final bool ltr = direction == TextDirection.ltr;
          final double pageLeft = ltr ? 60 : 16;
          expect(
            tester.getRect(find.byKey(rail)),
            Rect.fromLTWH(ltr ? 0 : 1224, 32, 56, 748),
          );
          expect(
            tester.getRect(find.byKey(page)),
            Rect.fromLTWH(pageLeft, 36, 1204, 674),
          );
          expect(tester.getTopLeft(find.byKey(content)).dy, 36);
          expect(
            tester.getRect(find.byKey(status)),
            Rect.fromLTWH(pageLeft, 722, 1204, 44),
          );
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  for (final TextDirection direction in TextDirection.values) {
    testWidgets(
      'entry fills the field and excludes its retained rail in $direction',
      (
        WidgetTester tester,
      ) async {
        final ValueNotifier<bool> locked = ValueNotifier<bool>(false);
        final FocusNode railFocus = FocusNode();
        addTearDown(locked.dispose);
        addTearDown(railFocus.dispose);
        const Key page = ValueKey<String>('page field');
        const Key status = ValueKey<String>('connection status');
        await tester.pumpWidget(
          MaterialApp(
            home: Directionality(
              textDirection: direction,
              child: Scaffold(
                body: ShellFrame(
                  locked: locked,
                  rail: SizedBox(
                    width: 76,
                    child: TextButton(
                      focusNode: railFocus,
                      onPressed: () {},
                      child: const Text('Private rail'),
                    ),
                  ),
                  page: const SizedBox.expand(key: page),
                  status: const SizedBox(
                    key: status,
                    width: double.infinity,
                    height: 18,
                  ),
                ),
              ),
            ),
          ),
        );
        final Size viewport = tester.getSize(find.byType(Scaffold));
        expect(tester.getSize(find.byKey(page)).width, viewport.width - 96);
        railFocus.requestFocus();
        await tester.pump();
        expect(railFocus.hasFocus, isTrue);
        locked.value = true;
        await tester.pump();
        expect(find.text('Private rail'), findsNothing);
        expect(find.text('Private rail', skipOffstage: false), findsOneWidget);
        expect(railFocus.hasFocus, isFalse);
        expect(railFocus.canRequestFocus, isFalse);
        expect(tester.getTopLeft(find.byKey(page)).dx, 0);
        expect(tester.getSize(find.byKey(page)).width, viewport.width);
        expect(tester.getTopLeft(find.byKey(status)).dx, 16);
        expect(tester.getSize(find.byKey(status)).width, viewport.width - 32);
        final TickerMode mode = tester.widget<TickerMode>(
          find
              .descendant(
                of: find.byType(Offstage, skipOffstage: false).last,
                matching: find.byType(TickerMode, skipOffstage: false),
                skipOffstage: false,
              )
              .first,
        );
        expect(mode.enabled, isFalse);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}
