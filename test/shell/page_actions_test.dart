import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/l10n/l10n.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/refresh_button/refresh_button.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/disclosure.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/page/page_widgets.dart';
import 'package:zenon_syrius_wallet_flutter/utils/app_theme.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/shell/page_command.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/shell/page_dismiss.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/shell/page_refresh.dart';

Widget _app(
  Widget child, {
  PageRefreshController? refresh,
  PageDismissController? dismiss,
}) => MaterialApp(
  theme: AppTheme.darkTheme,
  localizationsDelegates: appLocalizationsDelegates,
  supportedLocales: const <Locale>[Locale('en')],
  home: Scaffold(
    body: PageRefreshScope(
      controller: refresh ?? PageRefreshController(),
      child: PageDismissScope(
        controller: dismiss ?? PageDismissController(),
        child: Shortcuts(
          shortcuts: const <ShortcutActivator, Intent>{
            SingleActivator(LogicalKeyboardKey.escape): DismissIntent(),
          },
          child: Actions(
            actions: <Type, Action<Intent>>{
              DismissIntent: CallbackAction<DismissIntent>(
                onInvoke: (_) {
                  dismiss?.dismissLatest();
                  return null;
                },
              ),
            },
            child: FocusScope(autofocus: true, child: child),
          ),
        ),
      ),
    ),
  ),
);

void main() {
  testWidgets(
    'commands reuse the visible page scope and release their binding',
    (
      WidgetTester tester,
    ) async {
      final PageCommandController<String> target =
          PageCommandController<String>();
      addTearDown(target.dispose);
      int calls = 0;
      bool visible = true;
      late StateSetter update;
      expect(target.invoke('delegate'), isFalse);
      await tester.pumpWidget(
        _app(
          StatefulBuilder(
            builder: (_, StateSetter setState) {
              update = setState;
              return TickerMode(
                enabled: visible,
                child: PageCommandAction<String>(
                  controller: target,
                  command: 'delegate',
                  onInvoke: (_) => calls++,
                  child: const Text('Page'),
                ),
              );
            },
          ),
        ),
      );
      expect(target.invoke('delegate'), isTrue);
      expect(calls, 1);
      expect(target.invoke('unknown'), isFalse);
      update(() => visible = false);
      await tester.pump();
      expect(target.invoke('delegate'), isFalse);
      expect(calls, 1);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(target.invoke('delegate'), isFalse);
    },
  );

  testWidgets(
    'refresh uses current visible callbacks and releases detached pages',
    (
      WidgetTester tester,
    ) async {
      final PageRefreshController refresh = PageRefreshController();
      addTearDown(refresh.dispose);
      late StateSetter update;
      int version = 1;
      bool hidden = true;
      bool enabled = true;
      final List<int> reads = <int>[];
      await tester.pumpWidget(
        _app(
          StatefulBuilder(
            builder: (_, StateSetter setState) {
              update = setState;
              final int current = version;
              return Column(
                children: <Widget>[
                  PageRefreshAction(
                    enabled: enabled,
                    onRefresh: () => reads.add(current),
                    child: const Text('Visible'),
                  ),
                  TickerMode(
                    enabled: !hidden,
                    child: PageRefreshAction(
                      onRefresh: () => reads.add(-1),
                      child: const Text('Other tab'),
                    ),
                  ),
                ],
              );
            },
          ),
          refresh: refresh,
        ),
      );
      refresh.refresh();
      expect(reads, <int>[1]);
      update(() {
        version = 2;
        enabled = false;
        hidden = false;
      });
      await tester.pump();
      refresh.refresh();
      expect(reads, <int>[1, -1]);
      update(() {
        enabled = true;
        hidden = true;
      });
      await tester.pump();
      refresh.refresh();
      expect(reads, <int>[1, -1, 2]);
      await tester.pumpWidget(const SizedBox.shrink());
      refresh.refresh();
      expect(reads, <int>[1, -1, 2]);
    },
  );

  testWidgets('a button registers its existing read and pauses under a modal', (
    WidgetTester tester,
  ) async {
    final PageRefreshController refresh = PageRefreshController();
    addTearDown(refresh.dispose);
    int reads = 0;
    await tester.pumpWidget(
      _app(
        Builder(
          builder: (BuildContext context) => Column(
            children: <Widget>[
              RefreshButton(onPressed: () => reads++),
              TextButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => const AlertDialog(content: Text('Dialog')),
                ),
                child: const Text('Open'),
              ),
            ],
          ),
        ),
        refresh: refresh,
      ),
    );
    await tester.tap(find.byType(IconButton));
    refresh.refresh();
    expect(reads, 2);
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    refresh.refresh();
    expect(reads, 2);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Dialog'), findsNothing);
    refresh.refresh();
    expect(reads, 3);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a reparented binding leaves its old destination controller', (
    WidgetTester tester,
  ) async {
    final PageRefreshController first = PageRefreshController();
    final PageRefreshController second = PageRefreshController();
    addTearDown(first.dispose);
    addTearDown(second.dispose);
    final GlobalKey binding = GlobalKey();
    bool moved = false;
    late StateSetter update;
    int reads = 0;
    await tester.pumpWidget(
      _app(
        StatefulBuilder(
          builder: (_, StateSetter setState) {
            update = setState;
            final Widget action = PageRefreshAction(
              key: binding,
              onRefresh: () => reads++,
              child: const Text('Read'),
            );
            return Column(
              children: <Widget>[
                PageRefreshScope(
                  controller: first,
                  child: moved ? const SizedBox.shrink() : action,
                ),
                PageRefreshScope(
                  controller: second,
                  child: moved ? action : const SizedBox.shrink(),
                ),
              ],
            );
          },
        ),
      ),
    );
    first.refresh();
    second.refresh();
    expect(reads, 1);
    update(() => moved = true);
    await tester.pump();
    first.refresh();
    expect(reads, 1);
    second.refresh();
    expect(reads, 2);
    await tester.pumpWidget(const SizedBox.shrink());
    first.refresh();
    second.refresh();
    expect(reads, 2);
  });

  testWidgets('Escape closes a bare disclosure from its external opener', (
    WidgetTester tester,
  ) async {
    final PageDismissController dismiss = PageDismissController();
    final DisclosureController form = DisclosureController();
    final TextEditingController draft = TextEditingController(text: 'draft');
    addTearDown(dismiss.dispose);
    addTearDown(form.dispose);
    addTearDown(draft.dispose);
    await tester.pumpWidget(
      _app(
        Column(
          children: <Widget>[
            TextButton(onPressed: form.open, child: const Text('New')),
            Disclosure.bare(
              controller: form,
              keepAlive: true,
              child: TextField(controller: draft),
            ),
          ],
        ),
        dismiss: dismiss,
      ),
    );
    await tester.tap(find.text('New'));
    await tester.pumpAndSettle();
    expect(form.isOpen, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(form.isOpen, isFalse);
    expect(find.byType(TextField).hitTestable(), findsNothing);
    await tester.pumpAndSettle();
    form.open();
    await tester.pumpAndSettle();
    expect(draft.text, 'draft');
    expect(find.byType(TextField).hitTestable(), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(dismiss.dismissLatest(), isFalse);
  });

  testWidgets('Escape inside nested content closes the nearest open layer', (
    WidgetTester tester,
  ) async {
    final PageDismissController dismiss = PageDismissController();
    final DisclosureController outer = DisclosureController(open: true);
    final DisclosureController inner = DisclosureController(open: true);
    final FocusNode input = FocusNode();
    addTearDown(dismiss.dispose);
    addTearDown(outer.dispose);
    addTearDown(inner.dispose);
    addTearDown(input.dispose);
    await tester.pumpWidget(
      _app(
        Disclosure(
          title: 'Outer',
          controller: outer,
          keepAlive: true,
          child: Disclosure(
            title: 'Inner',
            controller: inner,
            keepAlive: true,
            child: TextField(focusNode: input),
          ),
        ),
        dismiss: dismiss,
      ),
    );
    input.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(inner.isOpen, isFalse);
    expect(outer.isOpen, isTrue);
    expect(dismiss.dismissLatest(), isTrue);
    await tester.pumpAndSettle();
    expect(outer.isOpen, isFalse);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'Escape skips hidden layers and cannot fold an ordinary empty-note panel',
    (
      WidgetTester tester,
    ) async {
      final PageDismissController dismiss = PageDismissController();
      addTearDown(dismiss.dispose);
      int hiddenDismissals = 0;
      await tester.pumpWidget(
        _app(
          Column(
            children: <Widget>[
              const Panel(
                title: 'Fixed',
                emptyNote: 'None yet',
                shrinkWrap: true,
                child: Text('Contents'),
              ),
              TickerMode(
                enabled: false,
                child: PageDismissAction(
                  open: true,
                  onDismiss: () => hiddenDismissals++,
                  child: const Text('Hidden tab'),
                ),
              ),
            ],
          ),
          dismiss: dismiss,
        ),
      );
      expect(dismiss.dismissLatest(), isFalse);
      expect(hiddenDismissals, 0);
      expect(find.text('Contents'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(dismiss.dismissLatest(), isFalse);
    },
  );
}
