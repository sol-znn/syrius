import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import '../../harness/bin/wallet_recipe.dart';
import '../../harness/wallet_address_context.dart';

// Deliberately invalid member strings: no SDK, signer, wallet or filesystem.
const String _first = 'synthetic-first-member';
const String _second = 'synthetic-second-member';
const String _third = 'synthetic-third-member';

Map<String, dynamic> _context({
  List<String> members = const <String>[_first],
  String selected = _first,
  String saved = _first,
  int revision = 20,
  int owner = 1,
}) => <String, dynamic>{
  'members': members, 'selected': selected, 'saved': saved,
  'revision': revision,
  'owner': owner,
};

class _AddressUi {
  Map<String, dynamic>? context = _context();
  String node = 'ws://127.0.0.1:45998';
  int chain = 321;
  String tab = 'dashboard';
  bool addresses = false;
  bool blockAdd = false;
  Object? blockedBy;
  Object? inputGate;
  bool wrongDerivation = false;
  bool selectionUnsettled = false;
  bool stallDerivation = false;
  bool seedSelectionUnsettled = false;
  final Completer<void> stalled = Completer<void>();
  final List<Map<String, Object?>> commands = <Map<String, Object?>>[];
  Duration elapsed = Duration.zero;

  WalletRecipe driver() => WalletRecipe(
    send: send, elapsed: () => elapsed,
    commandTimeout: const Duration(milliseconds: 10),
    wait: (Duration value) async { elapsed += value; },
  );

  List<String> get taps => commands
      .where((Map<String, Object?> value) => value['action'] == 'tap')
      .map((Map<String, Object?> value) => value['key']! as String).toList();

  Map<String, dynamic> observe() => <String, dynamic>{
    'ok': true, 'harnessMode': 'wallet', 'booted': true, 'owner': 1,
    'revision': context?['revision'] ?? 20,
    'walletPresent': true, 'walletInitCompleted': true, 'hasError': false,
    'tab': tab, 'node': node, 'chainId': chain, 'nodeConnected': true,
    'nodeSelectionSaved': true, 'signingChainId': chain,
    'savedSigningChainId': chain, 'signingPolicyReady': true,
    'transitionPending': false, 'question': null,
    'addressContext': context, 'addressesReady': addresses,
    'controls': <Map<String, dynamic>>[
      for (final String key in <String>[
        'nav_settings', 'settings_addresses',
        if (addresses) ...<String>[
          'settings_add_address', 'addresses_select_$_second',
        ],
      ]) <String, dynamic>{
        'key': key, 'enabled': !(key == 'settings_add_address' && blockAdd),
        if (key == 'settings_add_address' && blockAdd && blockedBy != null)
          'blockedBy': blockedBy,
        if (key == 'settings_add_address' && blockAdd && inputGate != null)
          'inputGate': inputGate,
      },
    ],
  };

  Future<Map<String, dynamic>> send(
    Map<String, Object?> command, Duration timeout,
  ) async {
    commands.add(Map<String, Object?>.of(command));
    if (command['action'] == 'observe') return observe();
    if (!WalletAddressContext.parse(command['addressContext']).same(
          WalletAddressContext.parse(context),
        )) {
      return <String, dynamic>{'ok': false,
        'error': 'wallet-recipe-original-address-context-changed'};
    }
    switch (command['key']) {
      case 'nav_settings':
        tab = 'settings';
      case 'settings_addresses':
        addresses = true;
      case 'settings_add_address':
        if (stallDerivation) await stalled.future;
        final WalletAddressContext before = WalletAddressContext.parse(context);
        context = before.members.length == 2
            ? _context(members: <String>[
                if (wrongDerivation) 'synthetic-replaced-member' else _first,
                _second, _third,
              ], selected: _second,
              saved: seedSelectionUnsettled ? _first : _second,
              revision: before.revision + 1)
            : _context(members: <String>[
                if (wrongDerivation) 'synthetic-replaced-member' else _first,
                _second,
              ], revision: 21);
      case 'addresses_select_$_second':
        context = _context(members: <String>[_first, _second],
          selected: selectionUnsettled ? _first : _second, saved: _second,
          revision: selectionUnsettled ? 21 : 22);
    }
    return <String, dynamic>{'ok': true, 'acted': true};
  }
}

void main() {
  _AddressUi seedUi() => _AddressUi()
    ..context = _context(members: <String>[_first, _second],
      selected: _second, saved: _second);

  test('blocked original seed controls retain their first fixed guard reason',
      () async {
    for (final (Object?, String) sample in <(Object?, String)>[
      (null, 'wallet-recipe-control-disabled'),
      ('widget', 'wallet-recipe-control-widget-disabled'),
      ('entrance', 'wallet-recipe-control-entrance-pending'),
      ('layout', 'wallet-recipe-control-layout-pending'),
      ('hit_test', 'wallet-recipe-control-not-reachable'),
      ('synthetic-private-input', 'wallet-recipe-control-disabled'),
      (true, 'wallet-recipe-control-disabled'),
    ]) {
      final _AddressUi ui = seedUi()
        ..blockAdd = true
        ..blockedBy = sample.$1;
      final WalletRecipe driver = ui.driver();
      final WalletAddressContext original =
          WalletAddressContext.parse(ui.context);
      await expectLater(driver.prepareSeedAddress(original), throwsA(
        isA<WalletRecipeRefused>().having(
          (WalletRecipeRefused value) => value.diagnostic?['reason'],
          'original blocking predicate', sample.$2,
        ),
      ));
      expect(ui.elapsed, const Duration(seconds: 30));
      expect(ui.taps.where((String key) => key == 'settings_add_address'),
        isEmpty);
      final int commands = ui.commands.length;
      await expectLater(driver.prepareSeedAddress(original),
        throwsA(isA<WalletRecipeRefused>()));
      expect(ui.commands, hasLength(commands));
    }
    // The real driver retains its refusal, deadline and input revocation.
    for (final (Object?, String) sample in <(Object?, String)>[
      ('backend', 'wallet-recipe-address-backend-blocked'),
      ('mounted', 'wallet-recipe-address-mounted-blocked'),
      ('hidden', 'wallet-recipe-address-hidden-blocked'),
      ('window', 'wallet-recipe-address-window-blocked'),
      ('section', 'wallet-recipe-address-section-blocked'),
      ('focus', 'wallet-recipe-address-focus-blocked'),
      ('route', 'wallet-recipe-address-route-blocked'),
      ('ticker', 'wallet-recipe-address-ticker-blocked'),
      ('busy', 'wallet-recipe-address-busy-blocked'),
      ('unknown', 'wallet-recipe-control-widget-disabled'),
      ('ready', 'wallet-recipe-control-widget-disabled'),
      (true, 'wallet-recipe-control-widget-disabled'),
      ('synthetic-private-input', 'wallet-recipe-control-widget-disabled'),
    ]) {
      final Object? gate = sample.$1;
      final _AddressUi ui = seedUi()
        ..blockAdd = true ..blockedBy = 'widget' ..inputGate = gate;
      final WalletRecipe driver = ui.driver();
      final WalletAddressContext original =
          WalletAddressContext.parse(ui.context);
      final String reason = sample.$2;
      await expectLater(driver.prepareSeedAddress(original), throwsA(
        isA<WalletRecipeRefused>().having(
          (WalletRecipeRefused value) => value.diagnostic?['reason'],
          'cached original input predicate', reason,
        ),
      ));
      expect(ui.elapsed, const Duration(seconds: 30));
      expect(ui.taps, isNot(contains('settings_add_address')));
      final int commands = ui.commands.length;
      await expectLater(driver.prepareSeedAddress(original),
          throwsA(isA<WalletRecipeRefused>()));
      expect(ui.commands, hasLength(commands));
    }
  });

  test('seed preparation appends index two without changing index one',
      () async {
    final _AddressUi ui = seedUi();
    final WalletAddressContext original =
        WalletAddressContext.parse(ui.context);
    final WalletAddressContext result = await ui.driver().prepareSeedAddress(
      original,
    );
    expect(result.derivedFrom(original), isTrue);
    expect(result.members, <String>[_first, _second, _third]);
    expect(result.selected, _second);
    expect(ui.taps, <String>[
      'nav_settings', 'settings_addresses', 'settings_add_address',
    ]);
  });

  test('seed preparation refuses existing index two and wrong selection',
      () async {
    for (final _AddressUi ui in <_AddressUi>[
      seedUi()..context = _context(members: <String>[_first, _second, _third],
        selected: _second, saved: _second),
      seedUi()..context = _context(members: <String>[_first, _second]),
    ]) {
      await expectLater(ui.driver().prepareSeedAddress(
        WalletAddressContext.parse(ui.context),
      ), throwsA(isA<WalletRecipeRefused>()));
      expect(ui.taps, isEmpty);
    }
  });

  test('seed derivation with a changed prefix cannot be tried again',
      () async {
    final _AddressUi ui = seedUi()..wrongDerivation = true;
    final WalletRecipe driver = ui.driver();
    final WalletAddressContext original =
        WalletAddressContext.parse(ui.context);
    await expectLater(driver.prepareSeedAddress(original),
      throwsA(isA<WalletRecipeRefused>()));
    await expectLater(driver.prepareSeedAddress(original),
      throwsA(isA<WalletRecipeRefused>()));
    expect(ui.taps.where((String key) => key == 'settings_add_address'),
      hasLength(1));
  });

  test('uncertain seed derivation keeps its late original and never retaps',
      () async {
    final _AddressUi ui = seedUi()..stallDerivation = true;
    final WalletRecipe driver = ui.driver();
    final WalletAddressContext original =
        WalletAddressContext.parse(ui.context);
    await expectLater(driver.prepareSeedAddress(original),
      throwsA(isA<WalletRecipeRefused>()));
    ui.stalled.complete();
    await Future<void>.delayed(Duration.zero);
    await expectLater(driver.prepareSeedAddress(original),
      throwsA(isA<WalletRecipeRefused>()));
    expect(ui.taps.where((String key) => key == 'settings_add_address'),
      hasLength(1));
  });

  test('a changed committed selection cannot qualify seed derivation',
      () async {
    final _AddressUi ui = seedUi()..seedSelectionUnsettled = true;
    await expectLater(ui.driver().prepareSeedAddress(
      WalletAddressContext.parse(ui.context),
    ), throwsA(isA<WalletRecipeRefused>()));
    expect(ui.taps.where((String key) => key == 'settings_add_address'),
      hasLength(1));
  });

  test('membership refuses unknown, duplicate, missing and private fields', () {
    for (final Object? value in <Object?>[
      null, <String, dynamic>{},
      <String, dynamic>{..._context(), 'private': 'never projected'},
      _context(members: <String>[_first, _first]),
      _context(selected: _second), _context(saved: _second),
      _context(revision: -1),
      _context(owner: 0),
    ]) {
      expect(() => WalletAddressContext.parse(value), throwsFormatException);
    }
  });

  test('derivation retains the original prefix and exactly one revision', () {
    final WalletAddressContext original = WalletAddressContext.parse(
      _context(),
    );
    expect(WalletAddressContext.parse(_context(
      members: <String>[_first, _second], revision: 21,
    )).derivedFrom(original), isTrue);
    for (final Map<String, dynamic> value in <Map<String, dynamic>>[
      _context(members: <String>[_second, _first], revision: 21),
      _context(members: <String>[_first, _second], revision: 22),
      _context(members: <String>[_first, _second], revision: 21, owner: 2),
      _context(members: <String>[_first, _second], selected: _second,
        saved: _second, revision: 21),
    ]) {
      expect(WalletAddressContext.parse(value).derivedFrom(original), isFalse);
    }
  });

  test('a committed preference alone cannot prove selection', () {
    final WalletAddressContext original = WalletAddressContext.parse(
      _context(members: <String>[_first, _second]),
    );
    final WalletAddressContext pending = WalletAddressContext.parse(_context(
      members: <String>[_first, _second], saved: _second,
    ));
    expect(pending.selectionPending(original, 1), isTrue);
    expect(pending.selectedFrom(original, 1), isFalse);
    expect(WalletAddressContext.parse(_context(
      members: <String>[_first, _second], selected: _second,
      saved: _second, revision: 21,
    )).selectedFrom(original, 1), isTrue);
  });

  test('the original controls derive once then select index one once',
      () async {
    final _AddressUi ui = _AddressUi();
    expect(await ui.driver().selectLabAddress(), <String, Object>{
      'index': 1, 'members': 2, 'generated': true,
      'selected': true, 'persisted': true,
    });
    expect(ui.taps, <String>['nav_settings', 'settings_addresses',
      'settings_add_address', 'addresses_select_$_second']);
    expect(ui.commands.where((Map<String, Object?> value) =>
      value['action'] != 'observe').every((Map<String, Object?> value) =>
        value['addressContext'] != null), isTrue);
  });

  test('an existing second member is never derived again', () async {
    final _AddressUi ui = _AddressUi()
      ..context = _context(members: <String>[_first, _second], revision: 21);
    expect((await ui.driver().selectLabAddress())['generated'], isFalse);
    expect(ui.taps, isNot(contains('settings_add_address')));
    expect(ui.taps.where((String key) => key.startsWith('addresses_select_')),
      hasLength(1));
  });

  test('an already persisted index one needs no new input', () async {
    final _AddressUi ui = _AddressUi()
      ..context = _context(members: <String>[_first, _second],
        selected: _second, saved: _second);
    expect((await ui.driver().selectLabAddress())['persisted'], isTrue);
    expect(ui.taps, isEmpty);
  });

  test('foreign lab and unresolved original selection receive no input',
      () async {
    for (final _AddressUi ui in <_AddressUi>[
      _AddressUi()..node = 'ws://127.0.0.1:55998',
      _AddressUi()..chain = 1,
      _AddressUi()..context = null,
      _AddressUi()..context = _context(
        members: <String>[_first, _second], saved: _second,
      ),
    ]) {
      await expectLater(ui.driver().selectLabAddress(),
        throwsA(isA<WalletRecipeRefused>()));
      expect(ui.taps, isEmpty);
    }
  });

  test('replaced derivation retires without selecting or deriving again',
      () async {
    final _AddressUi ui = _AddressUi()..wrongDerivation = true;
    final WalletRecipe driver = ui.driver();
    await expectLater(driver.selectLabAddress(),
      throwsA(isA<WalletRecipeRefused>()));
    final int original = ui.commands.length;
    await expectLater(driver.selectLabAddress(),
      throwsA(isA<WalletRecipeRefused>()));
    expect(ui.commands, hasLength(original));
    expect(ui.taps.where((String key) => key == 'settings_add_address'),
      hasLength(1));
    expect(ui.taps.any((String key) => key.startsWith('addresses_select_')),
      isFalse);
  });

  test('a late original derivation is never retried after timeout', () async {
    final _AddressUi ui = _AddressUi()..stallDerivation = true;
    final WalletRecipe driver = ui.driver();
    await expectLater(driver.selectLabAddress(),
      throwsA(isA<WalletRecipeRefused>()));
    ui.stalled.complete();
    await Future<void>.delayed(Duration.zero);
    final int original = ui.commands.length;
    await expectLater(driver.selectLabAddress(),
      throwsA(isA<WalletRecipeRefused>()));
    expect(ui.commands, hasLength(original));
    expect(ui.taps.where((String key) => key == 'settings_add_address'),
      hasLength(1));
  });

  test('pending selection cannot receive a second selection tap', () async {
    final _AddressUi ui = _AddressUi()..selectionUnsettled = true;
    final WalletRecipe driver = ui.driver();
    await expectLater(driver.selectLabAddress(),
      throwsA(isA<WalletRecipeRefused>()));
    final int original = ui.commands.length;
    await expectLater(driver.selectLabAddress(),
      throwsA(isA<WalletRecipeRefused>()));
    expect(ui.commands, hasLength(original));
    expect(ui.taps.where((String key) => key.startsWith('addresses_select_')),
      hasLength(1));
  });
}
