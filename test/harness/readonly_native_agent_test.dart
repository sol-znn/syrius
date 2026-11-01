import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:zenon_syrius_wallet_flutter/seams/seam.dart';
import 'package:zenon_syrius_wallet_flutter/utils/original_publications.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/help_widgets/about_card.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/help_widgets/about_information.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/help_widgets/originals_card.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/settings_widgets/node_settings_presenter.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/settings_widgets/node_settings_view.dart';

import '../../harness/app/agent.dart';
import '../../harness/app/presentation_host.dart';
import '../../harness/app/readonly_native_commands.dart';
import '../../harness/app/readonly_sdk_admission.dart';

import '../settings_about_redesign/support.dart' as about_fixture;
import '../settings_node_redesign/support.dart' as node_fixture;

class _Scope {
  final Object sdk = Object();
  final HarnessAgent agent = HarnessAgent.forTest();
  bool current = true;
  bool disabled = false;

  Future<ReadonlySdkAdmission> seal() => ReadonlySdkAdmission.seal(
    sdkOwner: sdk,
    ownersCurrent: () => current,
    automaticDisabled: () => disabled,
    disableAutomatic: () async {
      disabled = true;
    },
  );

  Future<void> open() async {
    agent.reserveReadonlyNative();
    agent.attachReadonlyNative(await seal());
    agent.booted = true;
  }

  Future<Map<String, Object?>> ping() =>
      agent.commandForTest(<String, dynamic>{'cmd': 'ping'});
}

class _Headers extends Fake implements HttpHeaders {
  _Headers([this._token]);

  final String? _token;

  @override
  ContentType? contentType;

  @override
  String? value(String name) => name == 'x-harness-token' ? _token : null;
}

class _Response extends Fake implements HttpResponse {
  final StringBuffer _output = StringBuffer();
  bool _closed = false;

  @override
  final HttpHeaders headers = _Headers();

  @override
  int statusCode = 200;

  bool get closed => _closed;

  Map<String, dynamic> get body =>
      jsonDecode(_output.toString()) as Map<String, dynamic>;

  @override
  void write(Object? value) => _output.write(value);

  @override
  Future<void> close() async {
    _closed = true;
  }
}

class _Request extends Stream<Uint8List> implements HttpRequest {
  _Request(Map<String, dynamic> command, {String token = 'fixture-token'})
    : headers = _Headers(token),
      _body = Uint8List.fromList(utf8.encode(jsonEncode(command)));

  final Uint8List _body;

  @override
  final HttpHeaders headers;

  @override
  final _Response response = _Response();

  @override
  StreamSubscription<Uint8List> listen(
    void Function(Uint8List)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => Stream<Uint8List>.value(_body).listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('Unexpected synthetic request member');
}

Future<T> _driveCatalogCommand<T>(
  WidgetTester tester,
  Future<T> command,
) async {
  bool done = false;
  T? result;
  Object? failure;
  StackTrace? trace;
  unawaited(command.then((T value) {
    result = value;
    done = true;
  }, onError: (Object error, StackTrace stack) {
    failure = error;
    trace = stack;
    done = true;
  }));
  for (int frame = 0; frame < 80 && !done; frame++) {
    await tester.pump(const Duration(milliseconds: 40));
  }
  expect(done, isTrue, reason: 'The original catalog command must finish');
  if (failure != null) Error.throwWithStackTrace(failure!, trace!);
  return result as T;
}


// Follow the original catalog reveal: observe first, then a physical wheel
// step, with the same 20-iteration bound and 250-pixel step.
Future<void> _revealCatalogKey(
  WidgetTester tester,
  HarnessAgent agent,
  String key,
) async {
  for (int attempt = 0; attempt <= 20; attempt++) {
    try {
      await agent.commandForTest(<String, dynamic>{
        'cmd': 'wait', 'key': key, 'timeoutMs': 0,
      });
      return;
    } on HarnessError {
      await _driveCatalogCommand(tester, agent.commandForTest(
        <String, dynamic>{'cmd': 'scroll', 'dy': 250},
      ));
    }
  }
  throw StateError('The original catalog reveal bound was exhausted');
}

void main() {
  testWidgets('readonly observes the actual disabled Sporks card', (
    WidgetTester tester,
  ) async {
    about_fixture.prepareAboutViewport(tester);
    final _Scope scope = _Scope();
    await scope.open();
    final HarnessAgent agent = scope.agent;
    final node_fixture.FakeNodeSettingsSession source =
        node_fixture.FakeNodeSettingsSession();
    final NodeSettingsPresenter presenter = node_fixture.nodePresenter(source);
    double height = 674;
    for (final bool light in <bool>[false, true]) {
      await tester.pumpWidget(about_fixture.aboutHost(
        NodeSettingsView(
          presenter: presenter,
          isCurrent: () => true,
          embeddedNode: const SizedBox(height: 80),
        ),
        light: light, width: 992, height: height,
      ));
      for (int frame = 0;
          frame < 100 && presenter.currentNetwork == null; frame++) {
        await tester.pump(const Duration(milliseconds: 10));
      }
      expect(presenter.currentNetwork, isNotNull);
      await tester.pump();
      final Finder gate = find.byKey(
        const Key('node_settings_sporks_gate'),
      );
      if (!light) {
        // End the inert viewport just below the actual Peers header.
        // The original scroll must expose Sporks through real clipping.
        height = tester.getRect(find.byKey(
          const Key('node_settings_peers_toggle'),
        )).bottom - tester.getRect(find.byKey(
          const Key('node_settings_page'),
        )).top + 1;
        expect(height, inInclusiveRange(1, 674));
        await tester.pumpWidget(about_fixture.aboutHost(
          NodeSettingsView(
            presenter: presenter,
            isCurrent: () => true,
            embeddedNode: const SizedBox(height: 80),
          ),
          light: light, width: 992, height: height,
        ));
        await tester.pump();
      }
      ScrollPosition position() => tester.state<ScrollableState>(
        find.descendant(
          of: find.byKey(const Key('node_settings_page')),
          matching: find.byType(Scrollable),
        ).first,
      ).position;
      if (light) expect(position().pixels, greaterThan(0));
      final List<String> callsBefore = List<String>.of(source.calls);
      await _driveCatalogCommand(tester, agent.commandForTest(
        <String, dynamic>{'cmd': 'scroll', 'dy': -1000000},
      ));
      expect(position().pixels, 0);
      final Map<String, Object?> addReady =
          await agent.commandForTest(<String, dynamic>{
        'cmd': 'assert', 'key': 'node_settings_add',
      });
      expect(addReady['asserted'], isTrue);
      await expectLater(agent.commandForTest(<String, dynamic>{
        'cmd': 'assert', 'key': 'node_settings_sporks_gate',
      }), throwsA(isA<HarnessError>()));
      await _driveCatalogCommand(tester, agent.commandForTest(
        <String, dynamic>{
          'cmd': 'scroll', 'key': 'node_settings_peers_toggle', 'dy': 300,
        },
      ));
      expect(position().pixels, greaterThan(0));
      expect(tester.widget<SeamGate>(gate).seam, Seam.sporks);
      for (final String command in <String>['assert', 'wait']) {
        final Map<String, Object?> result =
            await agent.commandForTest(<String, dynamic>{
          'cmd': command, 'key': 'node_settings_sporks_gate',
          if (command == 'wait') 'timeoutMs': 0,
          if (command == 'wait') 'ready': true,
        });
        final Map<String, Object?> target =
            result['target']! as Map<String, Object?>;
        expect(target['key'], 'node_settings_sporks_gate');
        expect(target['kind'], 'region');
        expect(target['ref'], 0);
      }
      await expectLater(agent.commandForTest(<String, dynamic>{
        'cmd': 'tap', 'key': 'node_settings_sporks_gate',
      }), throwsA(isA<HarnessError>()));
      expect(source.calls, callsBefore);
      expect(scope.disabled, isTrue);
      expect(find.byKey(const Key('node_settings_sporks_body'))
        .hitTestable(), findsNothing);
      expect(tester.takeException(), isNull);
    }
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await presenter.close();
  });

  testWidgets(
    'actual licences list becomes visible after header-targeted scrolling',
    (WidgetTester tester) async {
      about_fixture.prepareAboutViewport(tester);
      final _Scope scope = _Scope();
      await scope.open();
      final HarnessAgent agent = scope.agent;
      // One agent owns its mouse device across both theme renders.
      for (final bool light in <bool>[false, true]) {
        final OriginalsController discovery = OriginalsController();
        await tester.pumpWidget(about_fixture.aboutHost(
          AboutCard(
            loadInformation: () async => AboutInformation(version: 'fixture'),
            loadLicences: () => Stream<LicenseEntry>.value(
              about_fixture.FixtureLicence(<String>[
                'fixture-package',
                for (int index = 0; index < 120; index++)
                  'fixture-registry-$index',
              ], const <LicenseParagraph>[
                LicenseParagraph('Complete fixture licence.', 0),
              ]),
            ),
            licencesTrailingBuilder: (BuildContext context) =>
                OriginalsDiscovery(
                  controller: discovery,
                  isCurrent: () => true,
                ),
            afterLicences: const SizedBox(height: 56),
          ),
          light: light, height: 674,
        ));
        await tester.pump();
        await _driveCatalogCommand(tester, agent.commandForTest(
          <String, dynamic>{'cmd': 'tap', 'key': 'about_licences_toggle'},
        ));
        final Finder list = find.byKey(const Key('about_licences_list'));
        expect(list, findsOneWidget);
        final Rect before = tester.getRect(list);
        expect(before.bottom, greaterThan(780));
        await expectLater(agent.commandForTest(<String, dynamic>{
          'cmd': 'wait', 'key': 'about_licences_list', 'timeoutMs': 0,
        }), throwsA(isA<HarnessError>()));
        await _driveCatalogCommand(tester, agent.commandForTest(
          <String, dynamic>{
            'cmd': 'scroll', 'key': 'about_licences_toggle', 'dy': 300,
          },
        ));
        final Rect section = tester.getRect(
          find.byKey(const Key('about_page')),
        );
        final Rect after = tester.getRect(list);
        expect(section.contains(after.topLeft), isTrue);
        expect(section.contains(after.bottomRight - const Offset(1, 1)),
          isTrue);
        final Map<String, Object?> result =
            await agent.commandForTest(<String, dynamic>{
          'cmd': 'wait', 'key': 'about_licences_list', 'timeoutMs': 0,
        });
        final Map<String, Object?> target =
            result['target']! as Map<String, Object?>;
        expect(target['kind'], 'region');
        expect(target['key'], 'about_licences_list');
        expect(find.text('fixture-package'), findsOneWidget);
        expect(tester.getRect(list).contains(const Offset(640, 390)),
          isTrue);
        await expectLater(agent.commandForTest(<String, dynamic>{
          'cmd': 'assert', 'key': 'about_licences_end',
        }), throwsA(isA<HarnessError>()));
        await _driveCatalogCommand(tester, agent.commandForTest(
          <String, dynamic>{'cmd': 'scroll', 'dy': 1000000},
        ));
        await _revealCatalogKey(tester, agent, 'about_licences_end');
        final Map<String, Object?> endReady =
            await agent.commandForTest(<String, dynamic>{
          'cmd': 'wait', 'key': 'about_licences_end', 'timeoutMs': 0,
        });
        expect((endReady['target']! as Map<String, Object?>)['key'],
          'about_licences_end');
        final Map<String, Object?> end =
            await agent.commandForTest(<String, dynamic>{
          'cmd': 'assert', 'key': 'about_licences_end',
        });
        expect(end['asserted'], isTrue);
        await expectLater(agent.commandForTest(<String, dynamic>{
          'cmd': 'tap', 'key': 'about_licences_end',
        }), throwsA(isA<HarnessError>()));
        expect(discovery.revealed, isFalse);
        final Map<String, Object?> discoveryReady =
            await agent.commandForTest(<String, dynamic>{
          'cmd': 'wait', 'key': 'originals_discovery_field', 'timeoutMs': 0,
        });
        expect((discoveryReady['target']! as Map<String, Object?>)['key'],
          'originals_discovery_field');
        await _driveCatalogCommand(tester, agent.commandForTest(
          <String, dynamic>{
            'cmd': 'type', 'key': 'originals_discovery_field', 'value': '321',
          },
        ));
        expect(discovery.revealed, isTrue);
        expect(scope.disabled, isTrue);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        discovery.dispose();
      }
    },
  );


  testWidgets('readonly regions retain actual widget keys', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: Align(
        alignment: Alignment.topLeft,
        child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
          const ColoredBox(key: Key('home_hero'), color: Color(0xff222222),
            child: SizedBox(width: 200, height: 100,
              child: Text('Synthetic amount', key: Key('home_znn')))),
          GestureDetector(
            onTap: () => fail('Passive observation must not tap'),
            child: const Text('Synthetic rail',
              key: Key('rail_label_dashboard')),
          ),
        ]),
      ),
    ));
    final HarnessAgent ordinary = HarnessAgent.forTest()..booted = true;
    await expectLater(ordinary.commandForTest(<String, dynamic>{
      'cmd': 'assert', 'key': 'home_hero',
    }), throwsA(isA<HarnessError>()));
    final _Scope scope = _Scope();
    await scope.open();
    for (final String key in <String>[
      'home_hero', 'home_znn', 'rail_label_dashboard',
    ]) {
      final Map<String, Object?> result = await scope.agent.commandForTest(
        <String, dynamic>{'cmd': 'assert', 'key': key},
      );
      expect(result['asserted'], isTrue);
      final Map<String, Object?> target =
          result['target']! as Map<String, Object?>;
      final Rect rect = tester.getRect(find.byKey(Key(key)));
      expect(target['key'], key);
      expect(target['kind'], 'region');
      expect(target['rect'], <int>[
        rect.left.round(), rect.top.round(),
        rect.width.round(), rect.height.round(),
      ]);
      final Map<String, Object?> waited = await scope.agent.commandForTest(
        <String, dynamic>{'cmd': 'wait', 'key': key,
          'ready': true, 'timeoutMs': 0},
      );
      expect((waited['target']! as Map<String, Object?>)['key'], key);
    }
    final Map<String, Object?> tree = await scope.agent.commandForTest(
      <String, dynamic>{'cmd': 'tree'},
    );
    final List<Map<String, Object?>> nodes =
        tree['nodes']! as List<Map<String, Object?>>;
    expect(nodes.where((Map<String, Object?> node) =>
        node['kind'] == 'region'), isEmpty);
    expect(OriginalPublications.snapshot(scope.sdk), isEmpty);
  });

  testWidgets('hidden or duplicate regions provide no positive state', (
    WidgetTester tester,
  ) async {
    final _Scope scope = _Scope();
    await scope.open();
    const Widget region = ColoredBox(key: Key('home_hero'),
      color: Color(0xff222222), child: SizedBox(width: 200, height: 80));
    for (final String fault in <String>[
      'duplicate', 'offstage', 'hidden', 'zero',
    ]) {
      final Widget content = switch (fault) {
        'duplicate' => const Column(children: <Widget>[
          SizedBox(child: region), SizedBox(child: region),
        ]),
        'offstage' => const Offstage(child: region),
        'hidden' => const Visibility(visible: false, maintainSize: true,
          maintainAnimation: true, maintainState: true, child: region),
        _ => const SizedBox.shrink(child: region),
      };
      await tester.pumpWidget(Directionality(
        textDirection: TextDirection.ltr,
        child: Align(alignment: Alignment.topLeft, child: content),
      ));
      await expectLater(scope.agent.commandForTest(<String, dynamic>{
        'cmd': 'assert', 'key': 'home_hero',
      }), throwsA(isA<HarnessError>()));
      await expectLater(scope.agent.commandForTest(<String, dynamic>{
        'cmd': 'wait', 'key': 'home_hero', 'timeoutMs': 0, 'ready': true,
      }), throwsA(isA<HarnessError>()));
      expect(tester.takeException(), isNull);
    }
    expect((await scope.ping())['booted'], isTrue);
    expect(OriginalPublications.snapshot(scope.sdk), isEmpty);
  });

  testWidgets('covered regions cannot assert or become controls', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const Directionality(
      textDirection: TextDirection.ltr,
      child: Stack(children: <Widget>[
        Positioned(left: 0, top: 0, width: 200, height: 100,
          child: ColoredBox(key: Key('home_hero'), color: Color(0xff222222),
            child: Text('Synthetic amount', key: Key('home_znn')))),
        Positioned.fill(child: ColoredBox(color: Color(0xff444444))),
      ]),
    ));
    final _Scope scope = _Scope();
    await scope.open();
    for (final Map<String, dynamic> command in <Map<String, dynamic>>[
      <String, dynamic>{'cmd': 'assert', 'key': 'home_hero'},
      <String, dynamic>{'cmd': 'wait', 'key': 'home_hero',
        'timeoutMs': 0, 'ready': true},
      <String, dynamic>{'cmd': 'tap', 'key': 'home_hero'},
      <String, dynamic>{'cmd': 'assert', 'key': 'home_hero', 'nth': 1},
      <String, dynamic>{'cmd': 'wait', 'key': 'home_hero', 'gone': true},
    ]) {
      await expectLater(scope.agent.commandForTest(command),
          throwsA(isA<HarnessError>()));
    }
    expect(OriginalPublications.snapshot(scope.sdk), isEmpty);
  });


  testWidgets('readonly catalog regions preserve passive ancestor keys', (
    WidgetTester tester,
  ) async {
    final _Scope scope = _Scope();
    await scope.open();
    final HarnessAgent ordinary = HarnessAgent.forTest()..booted = true;
    const List<String> keys = <String>[
      'send_form_ready', 'receive_form_ready', 'receive_screen_marker',
      'nodes_pillars_strip', 'pillar_dev1_detail', 'plasma_strip',
      'plasma_fused_list', 'plasma_screen', 'tokens_strip', 'tokens_list',
      'p2p_swaps_strip', 'p2p_swaps_list',
      'accelerator_strip', 'accelerator_list',
      'receive_qr_screen_marker',
      'zap_form_ready',
      'about_page',
      'about_licences_list',
      'about_licences_end',
      'originals_card',
      'node_settings_page',
      'node_settings_nodes',
      'node_settings_count',
      'node_settings_sporks_gate',
      'security_settings_page',
      'security_settings_policies',
      'display_page',
      'wallet_settings_page',
      'wallet_settings_preferences',
      'apps_settings_page',
      'apps_settings_connected',
      'apps_settings_count',
      'addresses_settings_page',
      'about_strip',
      'about_version',
      'about_embedded_version',
      'about_build',
    ];
    Widget region(String key) => SizedBox(
      key: Key(key), width: 200, height: 80,
      child: const ColoredBox(
        color: Color(0xff222222),
        child: Text('Synthetic child', key: Key('synthetic_child')),
      ),
    );
    Widget overflowRegion(String key, Clip behavior) => SizedBox(
      width: 100, height: 40,
      child: ClipRect(
        clipBehavior: behavior,
        child: OverflowBox(
          alignment: Alignment.topLeft,
          minWidth: 200, maxWidth: 200, minHeight: 80, maxHeight: 80,
          child: region(key),
        ),
      ),
    );
    Future<void> show(Widget content) => tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: Align(alignment: Alignment.topLeft, child: content),
    ));
    Future<void> refused(Map<String, dynamic> command, {String? reason}) =>
        expectLater(scope.agent.commandForTest(command), throwsA(
          reason == null ? isA<HarnessError>() : isA<HarnessError>().having(
            (HarnessError error) =>
                (error.detail! as Map<String, Object?>)['readonly_region'],
            'original region refusal', reason,
          ),
        ));
    for (final String key in keys) {
      await show(region(key));
      await expectLater(ordinary.commandForTest(<String, dynamic>{
        'cmd': 'assert', 'key': key,
      }), throwsA(isA<HarnessError>()));
      for (final String command in <String>['assert', 'wait']) {
        final Map<String, Object?> result =
            await scope.agent.commandForTest(<String, dynamic>{
          'cmd': command, 'key': key,
          if (command == 'wait') 'ready': true,
          if (command == 'wait') 'timeoutMs': 0,
        });
        final Map<String, Object?> target =
            result['target']! as Map<String, Object?>;
        final Rect rect = tester.getRect(find.byKey(Key(key)));
        expect(target['key'], key);
        expect(target['kind'], 'region');
        expect(target['ref'], 0);
        expect(target['rect'], <int>[
          rect.left.round(), rect.top.round(),
          rect.width.round(), rect.height.round(),
        ]);
      }
      for (final Map<String, dynamic> command in <Map<String, dynamic>>[
        <String, dynamic>{'cmd': 'tap', 'key': key},
        <String, dynamic>{'cmd': 'assert', 'key': key, 'nth': 1},
        <String, dynamic>{'cmd': 'wait', 'key': key, 'gone': true},
      ]) {
        await refused(command);
      }
      final Map<String, Object?> tree =
          await scope.agent.commandForTest(<String, dynamic>{'cmd': 'tree'});
      final List<Map<String, Object?>> nodes =
          tree['nodes']! as List<Map<String, Object?>>;
      expect(nodes.where((Map<String, Object?> node) =>
          node['kind'] == 'region'), isEmpty);
      await show(overflowRegion(key, Clip.none));
      for (final String command in <String>['assert', 'wait']) {
        final Map<String, Object?> result =
            await scope.agent.commandForTest(<String, dynamic>{
          'cmd': command, 'key': key,
          if (command == 'wait') 'ready': true,
          if (command == 'wait') 'timeoutMs': 0,
        });
        final Map<String, Object?> target =
            result['target']! as Map<String, Object?>;
        expect(target['key'], key);
        expect(target['kind'], 'region');
        expect(target['ref'], 0);
      }
      for (final String fault in <String>[
        'duplicate', 'offstage', 'hidden', 'zero', 'covered', 'clipped',
      ]) {
        final Widget content = switch (fault) {
          'duplicate' => Column(mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              SizedBox(child: region(key)), SizedBox(child: region(key)),
            ]),
          'offstage' => Offstage(child: region(key)),
          'hidden' => Visibility(visible: false, maintainSize: true,
            maintainAnimation: true, maintainState: true, child: region(key)),
          'clipped' => overflowRegion(key, Clip.hardEdge),
          'covered' => Stack(children: <Widget>[
            region(key),
            const Positioned.fill(
              child: ColoredBox(color: Color(0xff444444))),
          ]),
          _ => SizedBox.shrink(child: region(key)),
        };
        await show(content);
        final String? reason = switch (fault) {
          'duplicate' => 'duplicate',
          'offstage' || 'hidden' => 'absent',
          'zero' => 'boundsRefused',
          'clipped' => 'paintClipCheckRefused',
          _ => null,
        };
        await refused(<String, dynamic>{'cmd': 'assert', 'key': key},
          reason: reason,
        );
        await refused(<String, dynamic>{'cmd': 'wait', 'key': key,
          'timeoutMs': 0, 'ready': true}, reason: reason);
        expect(tester.takeException(), isNull);
      }
    }
    for (final String key in <String>[
      'unapproved_passive_region', 'send_amount_field', 'plasma_open_fuse',
    ]) {
      await show(region(key));
      await refused(<String, dynamic>{'cmd': 'assert', 'key': key});
      await refused(<String, dynamic>{'cmd': 'wait', 'key': key,
        'timeoutMs': 0, 'ready': true});
    }
    expect((await scope.ping())['booted'], isTrue);
    expect(OriginalPublications.snapshot(scope.sdk), isEmpty);
  });


  testWidgets('readonly passive centers distinguish gaps from overlays', (
    WidgetTester tester,
  ) async {
    final _Scope scope = _Scope();
    await scope.open();
    final HarnessAgent ordinary = HarnessAgent.forTest()..booted = true;
    for (final String key in <String>['home_hero', 'send_form_ready']) {
      for (final bool covered in <bool>[false, true]) {
        await tester.pumpWidget(Directionality(
          textDirection: TextDirection.ltr,
          child: Align(alignment: Alignment.topLeft,
            child: ColoredBox(color: const Color(0xff222222),
              child: SizedBox(width: 200, height: 100,
                child: Stack(children: <Widget>[
                  Builder(key: Key(key), builder: (_) => const Column(
                    children: <Widget>[
                      SizedBox(height: 20, child: Text('Synthetic top',
                        key: Key('passive_top'))),
                      Spacer(),
                      SizedBox(height: 20, child: Text('Synthetic bottom',
                        key: Key('passive_bottom'))),
                    ],
                  )),
                  if (covered)
                    const Positioned(left: 70, top: 30, width: 60, height: 40,
                      child: ColoredBox(color: Color(0xff444444))),
                ]),
              ),
            ),
          ),
        ));
        for (final String child in <String>['passive_top', 'passive_bottom']) {
          final Map<String, Object?> result =
              await scope.agent.commandForTest(<String, dynamic>{
            'cmd': 'assert', 'key': child,
          });
          expect(result['asserted'], isTrue);
        }
        await expectLater(ordinary.commandForTest(<String, dynamic>{
          'cmd': 'assert', 'key': key,
        }), throwsA(isA<HarnessError>()));
        for (final String command in <String>['assert', 'wait']) {
          final Map<String, dynamic> fields = <String, dynamic>{
            'cmd': command, 'key': key,
            if (command == 'wait') 'ready': true,
            if (command == 'wait') 'timeoutMs': 0,
          };
          if (covered) {
            await expectLater(scope.agent.commandForTest(fields),
              throwsA(isA<HarnessError>()));
          } else {
            final Map<String, Object?> result =
                await scope.agent.commandForTest(fields);
            final Map<String, Object?> target =
                result['target']! as Map<String, Object?>;
            expect(target['key'], key);
            expect(target['kind'], 'region');
            expect(target['ref'], 0);
            final Rect rect = tester.getRect(find.byKey(Key(key)));
            expect(target['rect'], <int>[
              rect.left.round(), rect.top.round(),
              rect.width.round(), rect.height.round(),
            ]);
          }
        }
        await expectLater(scope.agent.commandForTest(<String, dynamic>{
          'cmd': 'tap', 'key': key,
        }), throwsA(isA<HarnessError>()));
        expect(tester.takeException(), isNull);
      }
    }
    final Map<String, Object?> tree =
        await scope.agent.commandForTest(<String, dynamic>{'cmd': 'tree'});
    final List<Map<String, Object?>> nodes =
        tree['nodes']! as List<Map<String, Object?>>;
    expect(nodes.where((Map<String, Object?> node) =>
        node['kind'] == 'region'), isEmpty);
    expect(OriginalPublications.snapshot(scope.sdk), isEmpty);
  });

  test('inspection entry refuses foreign nodes and chains before UI access',
      () async {
    final _Scope scope = _Scope();
    await scope.open();
    for (final Map<String, dynamic> fields in <Map<String, dynamic>>[
      <String, dynamic>{'expectedNode': 'wss://example.invalid:443'},
      <String, dynamic>{'expectedNodeChain': 1},
      <String, dynamic>{
        'key': 'node_settings_endpoint', 'value': 'ws://127.0.0.1:45999',
      },
      <String, dynamic>{
        'key': 'node_settings_client_chain', 'value': '1',
      },
      <String, dynamic>{
        'key': 'node_settings_select_ws://127.0.0.1:45999',
      },
    ]) {
      await expectLater(scope.agent.commandForTest(<String, dynamic>{
        'cmd': 'readonly-entry', 'action': 'observe', ...fields,
      }), throwsA(isA<ReadonlyNativeCommandRefused>()));
    }
    expect((await scope.ping())['pid'], pid);
    expect(OriginalPublications.snapshot(scope.sdk), isEmpty);
  });

  test('binding without the original native window holds the actual agent',
      () async {
    final _Scope scope = _Scope();
    await scope.open();
    await expectLater(scope.agent.commandForTest(<String, dynamic>{
      'cmd': 'readonly-wallet-bind',
    }), throwsA(isA<HarnessError>()));
    await expectLater(scope.ping(),
        throwsA(isA<ReadonlyNativeCommandRefused>()));
    expect(OriginalPublications.snapshot(scope.sdk), isEmpty);
  });

  test('ordinary original ping keeps the wallet mode without SDK sealing',
      () async {
    final HarnessAgent agent = HarnessAgent.forTest();
    final Map<String, Object?> result =
        await agent.commandForTest(<String, dynamic>{'cmd': 'ping'});
    expect(result['harnessMode'], 'wallet');
    expect(result['booted'], isFalse);
    expect(result.containsKey('readonlyAdmission'), isFalse);
  });

  test('reserved startup exposes only pending ping before SDK admission',
      () async {
    final _Scope scope = _Scope();
    scope.agent.reserveReadonlyNative();
    final Map<String, Object?> pending = await scope.ping();
    expect(pending['booted'], isFalse);
    expect(pending['harnessMode'], 'readonly-native');
    expect(pending.containsKey('pid'), isFalse);
    for (final String command in <String>['state', 'type', 'readonly-state']) {
      await expectLater(
        scope.agent.commandForTest(<String, dynamic>{'cmd': command}),
        throwsA(isA<ReadonlyNativeCommandRefused>()),
      );
    }
    expect(OriginalPublications.snapshot(scope.sdk), isEmpty);
  });

  test('sealed readiness uses the original agent ping and fixed SDK scope',
      () async {
    final _Scope scope = _Scope();
    await scope.open();
    final Map<String, Object?> result = await scope.ping();
    expect(result['pid'], pid);
    expect(result['booted'], isTrue);
    expect(result['harnessMode'], 'readonly-native');
    expect(result['readonlyAdmission'], <String, Object>{
      'schema': 1,
      'scope': 'readonly_native_sdk_admission',
      'status': 'CURRENT',
      'publicationAdmissionPaused': true,
      'automaticReceiveDisabled': true,
    });
    expect(scope.disabled, isTrue);
  });

  test('financial routes cannot bypass the original agent admission',
      () async {
    final _Scope scope = _Scope();
    await scope.open();
    for (final String command in <String>[
      'seed', 'lab-send', 'lab-quiesce', 'lab-reopen-observe',
      'wallet-recipe', 'clipboard',
    ]) {
      await expectLater(
        scope.agent.commandForTest(<String, dynamic>{'cmd': command}),
        throwsA(isA<ReadonlyNativeCommandRefused>()),
      );
    }
    expect(OriginalPublications.snapshot(scope.sdk), isEmpty);
    expect(OriginalPublications.hasRefusedAdmission(scope.sdk), isFalse);
    expect((await scope.ping())['booted'], isTrue);
  });

  test('early readiness cannot attach an SDK after its failed observation',
      () async {
    final _Scope scope = _Scope();
    scope.agent
      ..reserveReadonlyNative()
      ..booted = true;
    await expectLater(scope.ping(),
        throwsA(isA<ReadonlyNativeCommandRefused>()));
    scope.agent.booted = false;
    final ReadonlySdkAdmission sdk = await scope.seal();
    expect(() => scope.agent.attachReadonlyNative(sdk),
        throwsA(isA<ReadonlyNativeCommandRefused>()));
  });

  test('a used or booted ordinary agent cannot reserve inspection later',
      () async {
    final HarnessAgent used = HarnessAgent.forTest();
    await used.commandForTest(<String, dynamic>{'cmd': 'ping'});
    expect(used.reserveReadonlyNative, throwsA(isA<HarnessError>()));
    final HarnessAgent booted = HarnessAgent.forTest()..booted = true;
    expect(booted.reserveReadonlyNative, throwsA(isA<HarnessError>()));
  });

  test('presentation and original native inspection are mutually exclusive',
      () {
    final HarnessPresentationController controller =
        HarnessPresentationController();
    addTearDown(controller.dispose);
    final HarnessAgent preview = HarnessAgent.forTest()
      ..usePresentation(
        controller: controller,
        isCurrent: () => true,
        context: () => null,
      );
    expect(preview.reserveReadonlyNative, throwsA(isA<HarnessError>()));
    final HarnessAgent native = HarnessAgent.forTest()
      ..reserveReadonlyNative();
    expect(
      () => native.usePresentation(
        controller: controller,
        isCurrent: () => true,
        context: () => null,
      ),
      throwsA(isA<HarnessError>()),
    );
  });

  test('a changed SDK observation stays held after restoration', () async {
    final _Scope scope = _Scope();
    await scope.open();
    scope.current = false;
    await expectLater(scope.ping(),
        throwsA(isA<ReadonlySdkAdmissionRefused>()));
    scope.current = true;
    await expectLater(scope.ping(),
        throwsA(isA<ReadonlyNativeCommandRefused>()));
  });

  test('the actual original ping await cannot borrow changed SDK ownership',
      () async {
    final _Scope scope = _Scope();
    await scope.open();
    final Future<void> refused = expectLater(
      scope.ping(),
      throwsA(isA<ReadonlySdkAdmissionRefused>()),
    );
    scope.current = false;
    await refused;
  });

  test('an original UI refusal stays exact while its SDK remains current',
      () async {
    final _Scope scope = _Scope();
    await scope.open();
    await expectLater(
      scope.agent.commandForTest(<String, dynamic>{'cmd': 'entry-check'}),
      throwsA(isA<HarnessError>().having(
        (HarnessError error) => error.message,
        'original error',
        'native entry capture is unavailable',
      )),
    );
    expect((await scope.ping())['booted'], isTrue);
  });

  test('duplicate attachment cannot supply a second positive SDK scope',
      () async {
    final _Scope scope = _Scope();
    scope.agent.reserveReadonlyNative();
    final ReadonlySdkAdmission sdk = await scope.seal();
    scope.agent.attachReadonlyNative(sdk);
    expect(() => scope.agent.attachReadonlyNative(sdk),
        throwsA(isA<ReadonlyNativeCommandRefused>()));
    scope.agent.booted = true;
    await expectLater(scope.ping(),
        throwsA(isA<ReadonlyNativeCommandRefused>()));
  });

  test('an unreserved agent cannot attach an inspection SDK', () async {
    final _Scope scope = _Scope();
    final ReadonlySdkAdmission sdk = await scope.seal();
    expect(() => scope.agent.attachReadonlyNative(sdk),
        throwsA(isA<HarnessError>()));
  });

  test('actual transport keeps pending refusals finite without raw errors',
      () async {
    final HarnessAgent agent = HarnessAgent.forTest()
      ..reserveReadonlyNative();
    final _Request request = _Request(<String, dynamic>{'cmd': 'type'});
    await agent.serveForTest(request, 'fixture-token');
    expect(request.response.statusCode, 400);
    expect(request.response.closed, isTrue);
    expect(request.response.body, <String, Object>{
      'ok': false,
      'error': 'READONLY_NATIVE_COMMAND_REFUSED',
    });
    expect(request.response.headers.contentType, ContentType.json);
  });

  test('actual transport projects a replaced SDK without private details',
      () async {
    final _Scope scope = _Scope();
    await scope.open();
    scope.current = false;
    final _Request request = _Request(<String, dynamic>{'cmd': 'ping'});
    await scope.agent.serveForTest(request, 'fixture-token');
    expect(request.response.statusCode, 400);
    expect(request.response.closed, isTrue);
    expect(request.response.body, <String, Object>{
      'ok': false,
      'error': 'READONLY_NATIVE_SDK_REFUSED',
    });
  });

  test('original authentication and ordinary transport errors stay intact',
      () async {
    final HarnessAgent agent = HarnessAgent.forTest();
    final _Request wrong = _Request(
      <String, dynamic>{'cmd': 'ping'},
      token: 'another-fixture-token',
    );
    await agent.serveForTest(wrong, 'fixture-token');
    expect(wrong.response.body, <String, Object>{
      'ok': false,
      'error': 'bad token',
    });
    final _Request unknown = _Request(<String, dynamic>{'cmd': 'unknown'});
    await agent.serveForTest(unknown, 'fixture-token');
    expect(unknown.response.statusCode, 400);
    expect(unknown.response.closed, isTrue);
    expect(unknown.response.body, <String, Object>{
      'ok': false,
      'error': 'unknown command unknown',
    });
  });
}
