import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/settings_widgets/node_settings_presenter.dart';

import 'support.dart';

void main() {
  late FakeNodeSettingsSession source;
  late NodeSettingsPresenter presenter;

  setUp(() {
    source = FakeNodeSettingsSession();
    presenter = nodePresenter(source);
  });

  tearDown(() async {
    if (!presenter.isClosed) {
      await presenter.close();
    }
  });

  test('opening has no invented endpoint facts or side effects', () {
    expect(presenter.state.entries.length, 3);
    expect(presenter.currentNetwork, isNull);
    expect(source.calls, isEmpty);
  });

  test('a switch persists before globals and notice', () async {
    final bool changed = await presenter.select(
      remoteNode,
      epoch: presenter.authorityEpoch,
      question: (_) async => fail('matching chains ask no question'),
    );
    expect(changed, isTrue);
    expect(source.calls, <String>[
      'lease',
      'connect:$remoteNode',
      'frontier:$remoteNode',
      'checkpoint:0',
      'save:$remoteNode',
      'globals:$remoteNode:1',
      'announce',
      'release',
      'notice:connected',
      'callback',
    ]);
    expect(source.connected, remoteNode);
    expect(presenter.state.activeNode, remoteNode);
    expect(presenter.state.clientChain, 1);
    expect(presenter.state.busy, isFalse);
  });

  test('declined mismatch verifies the original without commit', () async {
    NodeSettingsMismatch? asked;
    final bool changed = await presenter.select(
      customNode,
      epoch: presenter.authorityEpoch,
      question: (NodeSettingsMismatch mismatch) async {
        asked = mismatch;
        return false;
      },
    );
    expect(changed, isFalse);
    expect(asked?.node, customNode);
    expect(asked?.nodeChain, 321);
    expect(asked?.clientChain, 1);
    expect(source.calls, <String>[
      'lease',
      'connect:$customNode',
      'frontier:$customNode',
      'connect:$embeddedNode',
      'frontier:$embeddedNode',
      'restored:1',
      'release',
    ]);
    expect(presenter.state.activeNode, embeddedNode);
    expect(presenter.state.clientChain, 1);
  });

  test('accepted mismatch keeps independent signing policy', () async {
    expect(
      await presenter.select(
        customNode,
        epoch: presenter.authorityEpoch,
        question: (_) async => true,
      ),
      isTrue,
    );
    expect(presenter.currentNetwork?.chain, 321);
    expect(presenter.state.clientChain, 1);
    expect(source.signingChain, 1);
    expect(
      source.calls.where((String call) => call.startsWith('clientChain')),
      isEmpty,
    );
  });

  for (final String stage in <String>[
    'connect:$remoteNode',
    'frontier:$remoteNode',
    'checkpoint:0',
    'save:$remoteNode',
  ]) {
    test('replacement during $stage refuses commit', () async {
      final Completer<void> gate = Completer<void>();
      source.gates[stage] = gate;
      final Future<bool> change = presenter.select(
        remoteNode,
        epoch: presenter.authorityEpoch,
        question: (_) async => true,
      );
      await source.saw(stage).timeout(const Duration(seconds: 1));
      source.authority = false;
      gate.complete();
      expect(await change.timeout(const Duration(seconds: 1)), isFalse);
      expect(source.calls, isNot(contains('announce')));
      expect(source.calls, isNot(contains('notice:connected')));
      expect(source.calls, isNot(contains('callback')));
      expect(presenter.state.activeNode, embeddedNode);
      expect(presenter.currentNetwork, isNull);
    });
  }

  test('question cannot revive after visibility reversal', () async {
    final Completer<bool> answer = Completer<bool>();
    final Completer<void> asked = Completer<void>();
    final Future<bool> change = presenter.select(
      customNode,
      epoch: presenter.authorityEpoch,
      question: (_) {
        asked.complete();
        return answer.future;
      },
    );
    await asked.future.timeout(const Duration(seconds: 1));
    presenter
      ..setVisible(visible: false)
      ..setVisible(visible: true);
    answer.complete(true);
    expect(await change.timeout(const Duration(seconds: 1)), isFalse);
    expect(source.calls, <String>[
      'lease',
      'connect:$customNode',
      'frontier:$customNode',
      'connect:$embeddedNode',
      'frontier:$embeddedNode',
      'restored:1',
      'release',
    ]);
    expect(source.connected, source.selected);
    expect(source.transitionHeld, isFalse);
  });

  test('old callbacks refuse before capturing another source', () async {
    final int original = presenter.authorityEpoch;
    presenter
      ..setVisible(visible: false)
      ..setVisible(visible: true);
    expect(
      await presenter.select(
        remoteNode,
        epoch: original,
        question: (_) async => true,
      ),
      isFalse,
    );
    expect(source.calls, isEmpty);
  });

  test('concurrent presses issue exactly one connection', () async {
    final Completer<void> gate = Completer<void>();
    source.gates['connect:$remoteNode'] = gate;
    final int epoch = presenter.authorityEpoch;
    final Future<bool> first = presenter.select(
      remoteNode,
      epoch: epoch,
      question: (_) async => true,
    );
    expect(
      await presenter.select(
        customNode,
        epoch: epoch,
        question: (_) async => true,
      ),
      isFalse,
    );
    gate.complete();
    expect(await first.timeout(const Duration(seconds: 1)), isTrue);
    expect(
      source.calls.where((String call) => call.startsWith('connect:')),
      <String>['connect:$remoteNode'],
    );
  });

  test('save failure stays exact and never announces', () async {
    final Object failure = StateError('synthetic original save failure');
    source.failures['save:$remoteNode'] = failure;
    expect(
      await presenter.select(
        remoteNode,
        epoch: presenter.authorityEpoch,
        question: (_) async => true,
      ),
      isFalse,
    );
    expect(presenter.lastError, same(failure));
    expect(presenter.lastStack, isNotNull);
    expect(source.calls, isNot(contains('announce')));
    expect(source.connected, embeddedNode);
    expect(source.savedNode, embeddedNode);
    expect(source.transitionHeld, isFalse);
  });

  for (final bool disposed in <bool>[false, true]) {
    test('saved node restores after scope loss, disposed $disposed', () async {
      final Completer<void> gate = Completer<void>();
      source.gates['save:$remoteNode'] = gate;
      final Future<bool> change = presenter.select(
        remoteNode,
        epoch: presenter.authorityEpoch,
        question: (NodeSettingsMismatch _) async => true,
      );
      await source.saw('save:$remoteNode').timeout(const Duration(seconds: 1));
      expect(source.savedNode, remoteNode);
      if (disposed) {
        await presenter.close();
      } else {
        presenter.setVisible(visible: false);
      }
      gate.complete();
      expect(await change.timeout(const Duration(seconds: 1)), isFalse);
      expect(source.savedNode, embeddedNode);
      expect(source.selected, embeddedNode);
      expect(source.connected, embeddedNode);
      expect(source.transitionHeld, isFalse);
      expect(source.calls, isNot(contains('announce')));
      expect(
        source.calls.indexOf('restoreNode:$embeddedNode'),
        lessThan(source.calls.indexOf('release')),
      );
    });
  }

  test('failed original preference restoration retains quarantine', () async {
    final Completer<void> gate = Completer<void>();
    source.gates['save:$remoteNode'] = gate;
    source.failures['restoreNode:$embeddedNode'] = StateError(
      'synthetic original preference refusal',
    );
    final Future<bool> change = presenter.select(
      remoteNode,
      epoch: presenter.authorityEpoch,
      question: (NodeSettingsMismatch _) async => true,
    );
    await source.saw('save:$remoteNode').timeout(const Duration(seconds: 1));
    presenter.setVisible(visible: false);
    gate.complete();
    expect(await change.timeout(const Duration(seconds: 1)), isFalse);
    expect(source.savedNode, remoteNode);
    expect(source.selected, embeddedNode);
    expect(source.transitionHeld, isTrue);
    expect(source.calls, isNot(contains('release')));
    expect(source.calls, isNot(contains('announce')));
  });

  test('cleanup cannot overwrite a replacement preference value', () async {
    final Completer<void> gate = Completer<void>();
    source.gates['save:$remoteNode'] = gate;
    final Future<bool> change = presenter.select(
      remoteNode,
      epoch: presenter.authorityEpoch,
      question: (NodeSettingsMismatch _) async => true,
    );
    await source.saw('save:$remoteNode').timeout(const Duration(seconds: 1));
    source.savedNode = 'wss://replacement.example:35998';
    presenter.setVisible(visible: false);
    gate.complete();
    expect(await change.timeout(const Duration(seconds: 1)), isFalse);
    expect(source.savedNode, 'wss://replacement.example:35998');
    expect(source.calls, isNot(contains('restoreNode:$embeddedNode')));
    expect(source.calls, isNot(contains('release')));
    expect(source.transitionHeld, isTrue);
  });

  test('an original mismatch cannot release a replacement lease', () async {
    final Completer<bool> answer = Completer<bool>();
    final Completer<void> asked = Completer<void>();
    final Future<bool> change = presenter.select(
      customNode,
      epoch: presenter.authorityEpoch,
      question: (NodeSettingsMismatch _) {
        asked.complete();
        return answer.future;
      },
    );
    await asked.future.timeout(const Duration(seconds: 1));
    source.ownsTransition = false;
    answer.complete(false);
    expect(await change.timeout(const Duration(seconds: 1)), isFalse);
    expect(source.transitionHeld, isTrue);
    expect(source.calls, isNot(contains('connect:$embeddedNode')));
    expect(source.calls, isNot(contains('release')));
    expect(source.calls, isNot(contains('announce')));
  });

  test('notice failure retains the accepted connection', () async {
    final Object failure = StateError('synthetic observer failure');
    source.failures['notice:connected'] = failure;
    expect(
      await presenter.select(
        remoteNode,
        epoch: presenter.authorityEpoch,
        question: (_) async => true,
      ),
      isTrue,
    );
    expect(presenter.lastError, same(failure));
    expect(presenter.state.activeNode, remoteNode);
    expect(source.calls.where((String call) => call == 'announce').length, 1);
    expect(source.calls.last, 'callback');
  });

  test('reentrant announcement revokes later callbacks', () async {
    source.afterPublish = () => source.authority = false;
    expect(
      await presenter.select(
        remoteNode,
        epoch: presenter.authorityEpoch,
        question: (NodeSettingsMismatch _) async => true,
      ),
      isTrue,
    );
    expect(source.selected, remoteNode);
    expect(source.calls.where((String call) => call == 'announce').length, 1);
    expect(source.calls, isNot(contains('notice:connected')));
    expect(source.calls, isNot(contains('callback')));
    expect(source.calls, isNot(contains('connect:$embeddedNode')));
    expect(source.transitionHeld, isTrue);
    expect(presenter.currentNetwork, isNull);
  });

  test('failed rollback keeps quarantine and original failure', () async {
    final Object original = StateError('synthetic save refusal');
    source.failures['save:$remoteNode'] = original;
    source.failures['connect:$embeddedNode'] = StateError('synthetic rollback');
    expect(
      await presenter.select(
        remoteNode,
        epoch: presenter.authorityEpoch,
        question: (NodeSettingsMismatch _) async => true,
      ),
      isFalse,
    );
    expect(presenter.lastError, same(original));
    expect(source.transitionHeld, isTrue);
    expect(source.calls, isNot(contains('release')));
    expect(source.calls, isNot(contains('announce')));
    expect(presenter.currentNetwork, isNull);
  });

  test('cleanup never overwrites a replacement transport owner', () async {
    final Completer<void> gate = Completer<void>();
    source.gates['frontier:$remoteNode'] = gate;
    final Future<bool> change = presenter.select(
      remoteNode,
      epoch: presenter.authorityEpoch,
      question: (NodeSettingsMismatch _) async => true,
    );
    await source
        .saw('frontier:$remoteNode')
        .timeout(const Duration(seconds: 1));
    source
      ..authority = false
      ..connected = 'wss://replacement.example:35998';
    gate.complete();
    expect(await change.timeout(const Duration(seconds: 1)), isFalse);
    expect(source.connected, 'wss://replacement.example:35998');
    expect(source.calls, isNot(contains('connect:$embeddedNode')));
    expect(source.transitionHeld, isTrue);
  });

  test('a changed original chain cannot prove rollback', () async {
    final Completer<bool> answer = Completer<bool>();
    final Completer<void> asked = Completer<void>();
    final Future<bool> change = presenter.select(
      customNode,
      epoch: presenter.authorityEpoch,
      question: (NodeSettingsMismatch _) {
        asked.complete();
        return answer.future;
      },
    );
    await asked.future.timeout(const Duration(seconds: 1));
    source.chains[embeddedNode] = 321;
    answer.complete(false);
    expect(await change.timeout(const Duration(seconds: 1)), isFalse);
    expect(source.transitionHeld, isTrue);
    expect(source.calls, isNot(contains('release')));
    expect(source.calls, isNot(contains('restored:321')));
    expect(presenter.currentNetwork, isNull);
  });

  test('unknown original chain cannot borrow the signing policy', () async {
    await presenter.close();
    source = FakeNodeSettingsSession(originalChain: null);
    presenter = nodePresenter(source);
    expect(source.chains[embeddedNode], source.clientChain);
    expect(
      await presenter
          .select(
            customNode,
            epoch: presenter.authorityEpoch,
            question: (NodeSettingsMismatch _) async => false,
          )
          .timeout(const Duration(seconds: 1)),
      isFalse,
    );
    expect(source.connected, customNode);
    expect(source.selected, embeddedNode);
    expect(source.savedNode, embeddedNode);
    expect(source.transitionHeld, isTrue);
    expect(source.calls, isNot(contains('connect:$embeddedNode')));
    expect(source.calls, isNot(contains('release')));
    expect(source.calls, isNot(contains('announce')));
    expect(presenter.currentNetwork, isNull);
  });

  test('an accepted new node needs no guessed original chain', () async {
    await presenter.close();
    source = FakeNodeSettingsSession(originalChain: null);
    presenter = nodePresenter(source);
    expect(
      await presenter
          .select(
            customNode,
            epoch: presenter.authorityEpoch,
            question: (NodeSettingsMismatch _) async => true,
          )
          .timeout(const Duration(seconds: 1)),
      isTrue,
    );
    expect(source.selected, customNode);
    expect(source.savedNode, customNode);
    expect(source.signingChain, 1);
    expect(source.transitionHeld, isFalse);
    expect(source.calls, contains('announce'));
    expect(source.calls, isNot(contains('connect:$embeddedNode')));
  });

  test('unknown native shutdown retains quarantine', () async {
    source
      ..spawnedUnowned = true
      ..failures['save:$remoteNode'] = StateError('synthetic original failure');
    expect(
      await presenter.select(
        remoteNode,
        epoch: presenter.authorityEpoch,
        question: (NodeSettingsMismatch _) async => true,
      ),
      isFalse,
    );
    expect(source.connected, source.selected);
    expect(source.transitionHeld, isTrue);
    expect(source.calls, isNot(contains('release')));
    expect(presenter.currentNetwork, isNull);
  });

  test('replaced transport preserves unknown peer facts', () async {
    source.peers = null;
    await presenter.refresh();
    expect(presenter.currentNetwork?.peers, isNull);
    expect(presenter.currentNetwork?.chain, 1);
    source.authority = false;
    expect(presenter.currentNetwork, isNull);
    source.authority = true;
    expect(
      presenter.currentNetwork,
      isNull,
      reason: 'observed revocation is final',
    );
  });

  test('a late read cannot repaint after visibility reversal', () async {
    final Completer<void> gate = Completer<void>();
    source.gates['network:$embeddedNode'] = gate;
    final Future<void> read = presenter.refresh();
    presenter
      ..setVisible(visible: false)
      ..setVisible(visible: true);
    gate.complete();
    await read.timeout(const Duration(seconds: 1));
    expect(presenter.currentNetwork, isNull);
  });

  test('client chain requires an explicit saved choice', () async {
    expect(
      await presenter.changeClientChain(321, epoch: presenter.authorityEpoch),
      isTrue,
    );
    expect(source.calls, <String>[
      'lease',
      'frontier:$embeddedNode',
      'saveChain:321',
      'clientChain:321',
      'release',
      'emitChain:321',
      'notice:chainChanged',
    ]);
    expect(presenter.state.activeNode, embeddedNode);
    expect(presenter.state.clientChain, 321);
  });

  test('a closed chain form restores its pending preference', () async {
    final Completer<void> gate = Completer<void>();
    source.gates['saveChain:321'] = gate;
    bool formOpen = true;
    final Future<bool> change = presenter.changeClientChain(
      321,
      epoch: presenter.authorityEpoch,
      isCurrent: () => formOpen,
    );
    await source.saw('saveChain:321').timeout(const Duration(seconds: 1));
    formOpen = false;
    gate.complete();
    expect(await change.timeout(const Duration(seconds: 1)), isFalse);
    expect(source.calls, <String>[
      'lease',
      'frontier:$embeddedNode',
      'saveChain:321',
      'connect:$embeddedNode',
      'frontier:$embeddedNode',
      'restoreChain:1',
      'restored:1',
      'release',
    ]);
    expect(source.signingChain, 1);
    expect(source.savedChain, 1);
    expect(source.transitionHeld, isFalse);
  });

  test('failed chain preference restoration keeps publication held', () async {
    final Completer<void> gate = Completer<void>();
    source.gates['saveChain:321'] = gate;
    source.failures['restoreChain:1'] = StateError(
      'synthetic signing preference refusal',
    );
    bool formOpen = true;
    final Future<bool> change = presenter.changeClientChain(
      321,
      epoch: presenter.authorityEpoch,
      isCurrent: () => formOpen,
    );
    await source.saw('saveChain:321').timeout(const Duration(seconds: 1));
    formOpen = false;
    gate.complete();
    expect(await change.timeout(const Duration(seconds: 1)), isFalse);
    expect(source.savedChain, 321);
    expect(source.signingChain, 1);
    expect(source.transitionHeld, isTrue);
    expect(source.calls, isNot(contains('release')));
    expect(source.calls, isNot(contains('clientChain:321')));
  });

  test('disposed chain UI restores its own completed preference put', () async {
    final Completer<void> gate = Completer<void>();
    source.gates['saveChain:321'] = gate;
    final Future<bool> change = presenter.changeClientChain(
      321,
      epoch: presenter.authorityEpoch,
    );
    await source.saw('saveChain:321').timeout(const Duration(seconds: 1));
    await presenter.close();
    gate.complete();
    expect(await change.timeout(const Duration(seconds: 1)), isFalse);
    expect(source.savedChain, 1);
    expect(source.signingChain, 1);
    expect(source.transitionHeld, isFalse);
    expect(source.calls, isNot(contains('clientChain:321')));
    expect(source.calls, isNot(contains('notice:chainChanged')));
  });

  test('catalog edits never connect or delete fixed rows', () async {
    expect(
      await presenter.storeNode(
        epoch: presenter.authorityEpoch,
        original: remoteNode,
      ),
      isFalse,
    );
    expect(source.calls, isEmpty);
    expect(
      await presenter.storeNode(
        epoch: presenter.authorityEpoch,
        original: customNode,
        replacement: 'wss://changed.example:35998',
      ),
      isTrue,
    );
    expect(source.calls, <String>['catalog', 'notice:updated']);
    expect(source.connected, embeddedNode);
  });

  test('a closed presenter cleans up its pending operation', () async {
    final Completer<void> gate = Completer<void>();
    source.gates['frontier:$remoteNode'] = gate;
    final Future<bool> change = presenter.select(
      remoteNode,
      epoch: presenter.authorityEpoch,
      question: (_) async => true,
    );
    await source
        .saw('frontier:$remoteNode')
        .timeout(const Duration(seconds: 1));
    await presenter.close();
    gate.complete();
    expect(await change.timeout(const Duration(seconds: 1)), isFalse);
    expect(source.calls, isNot(contains('announce')));
  });

  test('endpoint validation keeps exact supported URLs and explicit ports', () {
    expect(isNodeSettingsEndpoint(remoteNode), isTrue);
    expect(
      isNodeSettingsEndpoint('wss://user:secret@node.example:35998'),
      isFalse,
    );
    expect(isNodeSettingsEndpoint('wss://node.example'), isFalse);
    expect(isNodeSettingsEndpoint('$remoteNode/'), isFalse);
    expect(isNodeSettingsEndpoint('$remoteNode?other=node'), isFalse);
    expect(isNodeSettingsEndpoint(' $remoteNode'), isFalse);
  });
}
