import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/l10n/l10n.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/delegation/view/delegation_panels.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/page/page_widgets.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/segment.dart';
import 'package:zenon_syrius_wallet_flutter/utils/app_theme.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/reusable_widgets/modals/frosted_route.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/tab_children_widgets/nodes_tab_child.dart';

Widget _host(
  Widget child, {
  bool light = false,
  bool rtl = false,
  bool disableAnimations = false,
}) => MaterialApp(
  theme: light ? AppTheme.lightTheme : AppTheme.darkTheme,
  localizationsDelegates: appLocalizationsDelegates,
  supportedLocales: const <Locale>[Locale('en'), Locale('ar')],
  locale: rtl ? const Locale('ar') : const Locale('en'),
  builder: (BuildContext context, Widget? child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(disableAnimations: disableAnimations),
    child: child!,
  ),
  home: Scaffold(body: child),
);

NodesPage _page({NodesTab? initialTab, Map<String, int>? created}) => NodesPage(
  initialTab: initialTab,
  pillarsStrip: const Text('Pillar summary'),
  sentinelsStrip: const Text('Sentinel summary'),
  pillars: _SavedBody(name: 'Pillar', created: created),
  sentinels: _SavedBody(name: 'Sentinel', created: created),
);

class _SavedBody extends StatefulWidget {
  const _SavedBody({required this.name, this.created});

  final String name;
  final Map<String, int>? created;

  @override
  State<_SavedBody> createState() => _SavedBodyState();
}

class _SavedBodyState extends State<_SavedBody> {
  int _count = 0;

  @override
  void initState() {
    super.initState();
    final Map<String, int>? created = widget.created;
    if (created != null) {
      created[widget.name] = (created[widget.name] ?? 0) + 1;
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    children: <Widget>[
      TextButton(
        key: Key('${widget.name}_action'),
        onPressed: () => setState(() => _count++),
        child: Text('${widget.name} action $_count'),
      ),
      TextField(key: Key('${widget.name}_field')),
      Text('${widget.name} ticking: ${TickerMode.valuesOf(context).enabled}'),
    ],
  );
}

NodesTab? _selected(WidgetTester tester) => tester
    .widget<Segment<NodesTab>>(find.byKey(const Key('nodes_segment')))
    .selected;

Future<void> _pick(WidgetTester tester, NodesTab tab) async {
  await tester.tap(find.byKey(Segment.keyOf('nodes_tab', tab)));
  await tester.pumpAndSettle();
}

void main() {
  setUp(NodesPage.resetSessionSelection);

  testWidgets('card headings retain one live tab control and reported counts', (
    WidgetTester tester,
  ) async {
    final Map<String, int> created = <String, int>{};
    NodesPage page({int? pillarCount, int? sentinelCount}) => NodesPage(
      pillarsStrip: const Text('Pillar summary'),
      sentinelsStrip: const Text('Sentinel summary'),
      pillars: const Text('Unused pillar placeholder'),
      sentinels: const Text('Unused sentinel placeholder'),
      pillarCount: pillarCount,
      sentinelCount: sentinelCount,
      pillarsBuilder: (Widget tabs) => Panel(
        heading: tabs,
        child: _SavedBody(name: 'Pillar', created: created),
      ),
      sentinelsBuilder: (Widget tabs) => Panel(
        heading: tabs,
        child: _SavedBody(name: 'Sentinel', created: created),
      ),
    );
    await tester.pumpWidget(_host(page(pillarCount: 97)));
    expect(find.byKey(const Key('nodes_segment')), findsOneWidget);
    expect(find.byType(SegmentThumb), findsOneWidget);
    expect(
      tester
          .widget<Segment<NodesTab>>(
            find.byKey(const Key('nodes_segment')),
          )
          .appearance,
      SegmentAppearance.heading,
    );
    expect(find.textContaining('Unused'), findsNothing);
    expect(created, <String, int>{'Pillar': 1});
    await tester.enterText(find.byKey(const Key('Pillar_field')), 'retained');
    await _pick(tester, NodesTab.sentinels);
    await tester.pumpWidget(_host(page(pillarCount: 98, sentinelCount: 0)));
    expect(_selected(tester), NodesTab.sentinels);
    final Segment<NodesTab> tabs = tester.widget<Segment<NodesTab>>(
      find.byKey(const Key('nodes_segment')),
    );
    expect(tabs.appearance, SegmentAppearance.heading);
    expect(find.byType(SegmentThumb), findsOneWidget);
    expect(tabs.items.map((SegmentItem<NodesTab> item) => item.count), <int>[
      98,
      0,
    ]);
    await _pick(tester, NodesTab.pillars);
    expect(find.text('retained'), findsOneWidget);
    expect(created, <String, int>{'Pillar': 1, 'Sentinel': 1});
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'inline owner panel retains edits without hidden input or ticks',
    (
      WidgetTester tester,
    ) async {
      final SemanticsHandle semantics = tester.ensureSemantics();
      try {
        await tester.pumpWidget(
          _host(
            const NodesPage(
              initialTab: NodesTab.pillars,
              pillarsStrip: Text('Pillar summary'),
              sentinelsStrip: Text('Sentinel summary'),
              pillars: Text('Pillars list'),
              sentinels: Text('Sentinels list'),
              pillarsPanel: _SavedBody(name: 'Owner'),
            ),
          ),
        );
        await tester.enterText(
          find.byKey(const Key('Owner_field')),
          'owner edit',
        );
        await _pick(tester, NodesTab.sentinels);
        expect(find.semantics.byLabel('Owner action 0'), findsNothing);
        expect(
          find.text('Owner ticking: false', skipOffstage: false),
          findsOneWidget,
        );
        await _pick(tester, NodesTab.pillars);
        expect(find.text('owner edit'), findsOneWidget);
        expect(find.text('Owner ticking: true'), findsOneWidget);
        expect(tester.takeException(), isNull);
      } finally {
        semantics.dispose();
      }
    },
  );

  testWidgets('the unvisited list is not built or fetched early', (
    WidgetTester tester,
  ) async {
    final Map<String, int> created = <String, int>{};
    await tester.pumpWidget(_host(_page(created: created)));
    expect(created, <String, int>{'Pillar': 1});
    expect(_selected(tester), NodesTab.pillars);
    expect(find.text('Sentinel summary'), findsNothing);

    await _pick(tester, NodesTab.sentinels);
    expect(created, <String, int>{'Pillar': 1, 'Sentinel': 1});
    await _pick(tester, NodesTab.pillars);
    expect(created, <String, int>{'Pillar': 1, 'Sentinel': 1});
  });

  testWidgets('edits and row actions survive visiting the other tab', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(_host(_page()));
    await tester.enterText(find.byKey(const Key('Pillar_field')), 'saved');
    await tester.tap(find.byKey(const Key('Pillar_action')));
    await _pick(tester, NodesTab.sentinels);
    await tester.enterText(find.byKey(const Key('Sentinel_field')), 'other');
    await _pick(tester, NodesTab.pillars);

    expect(find.text('Pillar action 1'), findsOneWidget);
    final EditableText field = tester.widget<EditableText>(
      find.descendant(
        of: find.byKey(const Key('Pillar_field')),
        matching: find.byType(EditableText),
      ),
    );
    expect(field.controller.text, 'saved');
    await _pick(tester, NodesTab.sentinels);
    expect(find.text('other'), findsOneWidget);
  });

  testWidgets('the next visit resumes the session choice', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(_host(_page()));
    await _pick(tester, NodesTab.sentinels);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(_host(_page()));
    expect(_selected(tester), NodesTab.sentinels);
    expect(find.text('Sentinel summary'), findsOneWidget);
  });

  testWidgets('an explicit legacy destination overrides the session choice', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(_host(_page(initialTab: NodesTab.sentinels)));
    expect(_selected(tester), NodesTab.sentinels);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(_host(_page(initialTab: NodesTab.pillars)));
    expect(_selected(tester), NodesTab.pillars);
  });

  testWidgets('a new explicit destination applies without resetting bodies', (
    WidgetTester tester,
  ) async {
    final Map<String, int> created = <String, int>{};
    await tester.pumpWidget(_host(_page(created: created)));
    await tester.tap(find.byKey(const Key('Pillar_action')));
    await tester.pumpWidget(
      _host(_page(initialTab: NodesTab.sentinels, created: created)),
    );
    await tester.pumpAndSettle();
    expect(_selected(tester), NodesTab.sentinels);
    await _pick(tester, NodesTab.pillars);
    expect(find.text('Pillar action 1'), findsOneWidget);
    expect(created['Pillar'], 1);
  });

  testWidgets('hidden bodies expose no semantics or running ticker', (
    WidgetTester tester,
  ) async {
    final SemanticsHandle semantics = tester.ensureSemantics();
    try {
      await tester.pumpWidget(_host(_page()));
      await _pick(tester, NodesTab.sentinels);
      expect(find.semantics.byLabel('Pillar action 0'), findsNothing);
      expect(find.semantics.byLabel('Sentinel action 0'), findsOneWidget);
      expect(find.text('Sentinel ticking: true'), findsOneWidget);
      expect(
        find.text('Pillar ticking: false', skipOffstage: false),
        findsOneWidget,
      );
      await _pick(tester, NodesTab.pillars);
      expect(find.semantics.byLabel('Sentinel action 0'), findsNothing);
      expect(find.semantics.byLabel('Pillar action 0'), findsOneWidget);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets(
    'the shared segment changes the view with the arrow keys',
    (WidgetTester tester) async {
      await tester.pumpWidget(_host(_page()));
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(_selected(tester), NodesTab.sentinels);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
      expect(_selected(tester), NodesTab.pillars);
    },
    variant: const TargetPlatformVariant(<TargetPlatform>{
      TargetPlatform.macOS,
      TargetPlatform.windows,
      TargetPlatform.linux,
    }),
  );

  testWidgets('mode content keeps its 260 ms fade with OS motion disabled', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(_host(_page(), disableAnimations: true));
    await tester.tap(
      find.byKey(Segment.keyOf('nodes_tab', NodesTab.sentinels)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 130));
    final Finder fades = find.descendant(
      of: find.byKey(const Key('nodes_page')),
      matching: find.byType(FadeTransition),
    );
    final FadeTransition fading = tester.widget<FadeTransition>(fades.first);
    expect(fading.opacity.value, greaterThan(0));
    expect(fading.opacity.value, lessThan(1));
    await tester.pump(const Duration(milliseconds: 130));
    expect(tester.widget<FadeTransition>(fades.first).opacity.value, 1);
    await tester.pumpAndSettle();
  });

  for (final bool light in <bool>[false, true]) {
    testWidgets(
      'the layout fits 1200 by 600 in both directions, light=$light',
      (
        WidgetTester tester,
      ) async {
        await tester.binding.setSurfaceSize(const Size(1200, 600));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        for (final bool rtl in <bool>[false, true]) {
          await tester.pumpWidget(_host(_page(), light: light, rtl: rtl));
          await tester.pumpAndSettle();
          await _pick(tester, NodesTab.sentinels);
          expect(tester.takeException(), isNull);
          expect(_selected(tester), NodesTab.sentinels);
        }
      },
    );
  }

  testWidgets('the action panel is frosted and can be closed by keyboard', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      _host(
        Builder(
          builder: (BuildContext context) => TextButton(
            onPressed: () => showNodesPanel(
              context: context,
              title: 'Rewards',
              body: const Text('Reward history'),
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.byType(FrostedSurface), findsOneWidget);
    expect(find.text('Reward history'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Reward history'), findsNothing);
  });
}
