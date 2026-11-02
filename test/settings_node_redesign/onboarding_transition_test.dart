import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/settings_widgets/node_settings_presenter.dart';

import 'support.dart';

void main() {
  test('pristine onboarding persists a compatible node before entry', () async {
    final FakeNodeSettingsSession source = FakeNodeSettingsSession(
      origin: null,
      originalChain: null,
    );
    final NodeSettingsPresenter presenter = nodePresenter(source);
    addTearDown(presenter.close);
    expect(source.originalTarget, isA<NodeSettingsPristineTarget>());
    await presenter.refresh();
    expect(source.calls, isEmpty);
    expect(
      await presenter.select(
        remoteNode,
        epoch: presenter.authorityEpoch,
        question: (_) async =>
            fail('Compatible nodes require no mismatch consent.'),
      ),
      isTrue,
    );
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
    expect(source.savedNode, remoteNode);
    expect(source.transitionHeld, isFalse);
    expect(presenter.currentNetwork?.node, remoteNode);
  });

  test(
    'pristine mismatch requires consent and retains the signing policy',
    () async {
      final FakeNodeSettingsSession source = FakeNodeSettingsSession(
        origin: null,
        originalChain: null,
      );
      final NodeSettingsPresenter presenter = nodePresenter(source);
      addTearDown(presenter.close);
      NodeSettingsMismatch? question;
      expect(
        await presenter.select(
          customNode,
          epoch: presenter.authorityEpoch,
          question: (NodeSettingsMismatch original) async {
            question = original;
            return true;
          },
        ),
        isTrue,
      );
      expect(question?.node, customNode);
      expect(question?.nodeChain, 321);
      expect(question?.clientChain, 1);
      expect(presenter.currentNetwork?.chain, 321);
      expect(source.signingChain, 1);
      expect(source.savedChain, 1);
      expect(
        source.calls.where(
          (String call) =>
              call.startsWith('clientChain:') || call.startsWith('emitChain:'),
        ),
        isEmpty,
      );
      expect(source.transitionHeld, isFalse);
    },
  );

  test('declining a pristine mismatch cannot invent a restored node', () async {
    final FakeNodeSettingsSession source = FakeNodeSettingsSession(
      origin: null,
      originalChain: null,
    );
    final NodeSettingsPresenter presenter = nodePresenter(source);
    addTearDown(presenter.close);
    expect(
      await presenter.select(
        customNode,
        epoch: presenter.authorityEpoch,
        question: (_) async => false,
      ),
      isFalse,
    );
    expect(source.calls, <String>[
      'lease',
      'connect:$customNode',
      'frontier:$customNode',
    ]);
    expect(source.savedNode, isNull);
    expect(source.selected, isNull);
    expect(source.transitionHeld, isTrue);
    expect(presenter.currentNetwork, isNull);
    expect(
      await presenter.select(
        remoteNode,
        epoch: presenter.authorityEpoch,
        question: (_) async => true,
      ),
      isFalse,
    );
    expect(source.calls, <String>[
      'lease',
      'connect:$customNode',
      'frontier:$customNode',
    ]);
  });

  test(
    'a false pristine connection stays held without another attempt',
    () async {
      final FakeNodeSettingsSession source = FakeNodeSettingsSession(
        origin: null,
        originalChain: null,
      )..connectAnswer = false;
      final NodeSettingsPresenter presenter = nodePresenter(source);
      addTearDown(presenter.close);
      expect(
        await presenter.select(
          remoteNode,
          epoch: presenter.authorityEpoch,
          question: (_) async => fail('No frontier was established.'),
        ),
        isFalse,
      );
      expect(source.calls, <String>['lease', 'connect:$remoteNode']);
      expect(source.transitionHeld, isTrue);
      expect(source.savedNode, isNull);
    },
  );

  test(
    'a saved onboarding node requires an explicit confirmation action',
    () async {
      final FakeNodeSettingsSession source = FakeNodeSettingsSession(
        origin: remoteNode,
      );
      final NodeSettingsPresenter presenter = nodePresenter(source);
      addTearDown(presenter.close);
      expect(
        await presenter.select(
          remoteNode,
          epoch: presenter.authorityEpoch,
          question: (_) async => true,
        ),
        isFalse,
      );
      expect(source.calls, isEmpty);
      expect(
        await presenter.select(
          remoteNode,
          epoch: presenter.authorityEpoch,
          confirmCurrent: true,
          question: (_) async => fail('The real frontier matches.'),
        ),
        isTrue,
      );
      expect(source.calls.last, 'callback');
      expect(
        source.calls.where((String call) => call.startsWith('frontier:')),
        <String>['frontier:$remoteNode'],
      );
      expect(source.transitionHeld, isFalse);
    },
  );

  test(
    'disposed pristine owner retains completion and refuses entry',
    () async {
      final FakeNodeSettingsSession source = FakeNodeSettingsSession(
        origin: null,
        originalChain: null,
      );
      final Completer<void> original = Completer<void>();
      source.gates['connect:$remoteNode'] = original;
      final NodeSettingsPresenter presenter = nodePresenter(source);
      final Future<bool> attempt = presenter.select(
        remoteNode,
        epoch: presenter.authorityEpoch,
        question: (_) async => true,
      );
      await source.saw('connect:$remoteNode');
      await presenter.close();
      original.complete();
      expect(await attempt, isFalse);
      expect(source.calls, <String>['lease', 'connect:$remoteNode']);
      expect(source.connected, remoteNode);
      expect(source.savedNode, isNull);
      expect(source.transitionHeld, isTrue);
    },
  );

  test('a nonpositive original frontier cannot authorize onboarding', () async {
    final FakeNodeSettingsSession source = FakeNodeSettingsSession(
      origin: null,
      originalChain: null,
    )..chains[remoteNode] = 0;
    final NodeSettingsPresenter presenter = nodePresenter(source);
    addTearDown(presenter.close);
    expect(
      await presenter.select(
        remoteNode,
        epoch: presenter.authorityEpoch,
        question: (_) async => fail('Invalid chains cannot request consent.'),
      ),
      isFalse,
    );
    expect(source.calls, <String>[
      'lease',
      'connect:$remoteNode',
      'frontier:$remoteNode',
    ]);
    expect(source.savedNode, isNull);
    expect(source.transitionHeld, isTrue);
  });
}
