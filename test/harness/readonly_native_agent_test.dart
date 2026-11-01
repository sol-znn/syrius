import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:zenon_syrius_wallet_flutter/utils/original_publications.dart';

import '../../harness/app/agent.dart';
import '../../harness/app/presentation_host.dart';
import '../../harness/app/readonly_native_commands.dart';
import '../../harness/app/readonly_sdk_admission.dart';

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

void main() {
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


  testWidgets('readonly navigation regions preserve passive ancestor keys', (
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
    ];
    Widget region(String key) => SizedBox(
      key: Key(key), width: 200, height: 80,
      child: const ColoredBox(
        color: Color(0xff222222),
        child: Text('Synthetic child', key: Key('synthetic_child')),
      ),
    );
    Future<void> show(Widget content) => tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: Align(alignment: Alignment.topLeft, child: content),
    ));
    Future<void> refused(Map<String, dynamic> command) =>
        expectLater(scope.agent.commandForTest(command),
          throwsA(isA<HarnessError>()));
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
      for (final String fault in <String>[
        'duplicate', 'offstage', 'hidden', 'zero', 'covered',
      ]) {
        final Widget content = switch (fault) {
          'duplicate' => Column(mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              SizedBox(child: region(key)), SizedBox(child: region(key)),
            ]),
          'offstage' => Offstage(child: region(key)),
          'hidden' => Visibility(visible: false, maintainSize: true,
            maintainAnimation: true, maintainState: true, child: region(key)),
          'covered' => Stack(children: <Widget>[
            region(key),
            const Positioned.fill(
              child: ColoredBox(color: Color(0xff444444))),
          ]),
          _ => SizedBox.shrink(child: region(key)),
        };
        await show(content);
        await refused(<String, dynamic>{'cmd': 'assert', 'key': key});
        await refused(<String, dynamic>{'cmd': 'wait', 'key': key,
          'timeoutMs': 0, 'ready': true});
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
