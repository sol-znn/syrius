import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:zenon_syrius_wallet_flutter/utils/constants.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/settings_widgets/wallet_settings_presenter.dart';

import 'support.dart';

void main() {
  test('mount keeps exact keys, defaults and custom values without writes', () {
    final WalletSettingsFixture source = WalletSettingsFixture();
    final WalletSettingsPresenter presenter = WalletSettingsPresenter(
      binding: source.bind(),
    );
    addTearDown(presenter.close);
    expect(
      WalletPreference.values.map((WalletPreference item) => item.key),
      <String>[
        kAutoReceiveKey,
        kEnableDesktopNotificationsKey,
        kLaunchAtStartupKey,
        kEnableClipboardWatcherKey,
      ],
    );
    expect(presenter.state.values, <WalletPreference, bool?>{
      WalletPreference.autoReceive: true,
      WalletPreference.desktopNotifications: false,
      WalletPreference.launchAtStartup: false,
      WalletPreference.clipboard: false,
    });
    source.store.entries
      ..[kAutoReceiveKey] = false
      ..[kLaunchAtStartupKey] = true
      ..[kEnableDesktopNotificationsKey] = 'retained custom content'
      ..['unrelated'] = 47;
    presenter.refresh();
    expect(presenter.state.values[WalletPreference.autoReceive], isFalse);
    expect(presenter.state.values[WalletPreference.launchAtStartup], isTrue);
    expect(
      presenter.state.values[WalletPreference.desktopNotifications],
      isNull,
    );
    expect(
      source.store.entries[kEnableDesktopNotificationsKey],
      'retained custom content',
    );
    expect(source.store.entries['unrelated'], 47);
    expect(source.store.writes, isEmpty);
    expect(source.effects, isEmpty);
  });

  test(
    'commit precedes the original effect and preserves its write Future',
    () async {
      final WalletSettingsFixture source = WalletSettingsFixture();
      source.store.deferred = true;
      final WalletSettingsBinding binding = source.bind();
      final Future<WalletPreferenceOutcome> operation = binding.change(
        WalletPreference.autoReceive,
        value: false,
        isCurrent: source.captureView(),
      );
      expect(source.store.writes, hasLength(1));
      expect(source.effects, isEmpty);
      expect(binding.pending(WalletPreference.autoReceive), same(operation));
      source.store.writes.single.complete();
      final WalletPreferenceOutcome outcome = await operation.timeout(
        const Duration(seconds: 1),
      );
      expect(outcome.status, WalletPreferenceStatus.applied);
      expect(outcome.write, same(source.store.writes.single.reply.future));
      expect(source.store.entries[kAutoReceiveKey], isFalse);
      expect(source.effects, <(WalletPreference, bool)>[
        (WalletPreference.autoReceive, false),
      ]);
      expect(source.notices, source.effects);
      expect(binding.outcomes.single, same(outcome));
      expect(binding.outcomes.clear, throwsUnsupportedError);
    },
  );

  test(
    'remount shares pending work and observes a disposed view write',
    () async {
      final WalletSettingsFixture source = WalletSettingsFixture();
      source.store.deferred = true;
      final WalletSettingsBinding original = source.bind();
      final WalletSettingsPresenter first = WalletSettingsPresenter(
        binding: original,
      );
      final Future<WalletPreferenceOutcome> operation = first.change(
        WalletPreference.clipboard,
        value: true,
        isCurrent: source.captureView(),
      )!;
      await first.close();
      source.leaveAndReturn();
      final WalletSettingsBinding next = source.bind();
      final WalletSettingsPresenter second = WalletSettingsPresenter(
        binding: next,
      );
      addTearDown(second.close);
      expect(second.state.busy, contains(WalletPreference.clipboard));
      expect(next.pending(WalletPreference.clipboard), same(operation));
      expect(
        next.change(
          WalletPreference.clipboard,
          value: true,
          isCurrent: source.captureView(),
        ),
        same(operation),
      );
      source.store.writes.single.complete();
      final WalletPreferenceOutcome outcome = await operation.timeout(
        const Duration(seconds: 1),
      );
      expect(outcome.committed, isTrue);
      expect(source.effects, hasLength(1));
      expect(source.notices, isEmpty);
      expect(second.state.busy, isEmpty);
      expect(second.state.values[WalletPreference.clipboard], isTrue);
      expect(next.outcomes.single, same(original.outcomes.single));
    },
  );

  test(
    'one key serializes writes and effects across independent bindings',
    () async {
      final WalletSettingsFixture source = WalletSettingsFixture();
      source.store.deferred = true;
      final WalletSettingsBinding original = source.bind();
      final Future<WalletPreferenceOutcome> first = original.change(
        WalletPreference.launchAtStartup,
        value: true,
        isCurrent: source.captureView(),
      );
      final Future<WalletPreferenceOutcome> second = source.bind().change(
        WalletPreference.launchAtStartup,
        value: false,
        isCurrent: source.captureView(),
      );
      expect(source.store.writes, hasLength(1));
      source.store.writes.first.complete();
      await first.timeout(const Duration(seconds: 1));
      expect(source.store.writes, hasLength(2));
      expect(source.effects, <(WalletPreference, bool)>[
        (WalletPreference.launchAtStartup, true),
      ]);
      source.store.writes.last.complete();
      await second.timeout(const Duration(seconds: 1));
      expect(source.effects, <(WalletPreference, bool)>[
        (WalletPreference.launchAtStartup, true),
        (WalletPreference.launchAtStartup, false),
      ]);
      expect(source.store.entries[kLaunchAtStartupKey], isFalse);
      expect(original.outcomes, hasLength(2));
    },
  );

  test(
    'a deferred effect also holds its key while another key can commit',
    () async {
      final WalletSettingsFixture source = WalletSettingsFixture();
      final Completer<Object?> effect = Completer<Object?>();
      source.effect = () => effect.future;
      final WalletSettingsBinding binding = source.bind();
      final Future<WalletPreferenceOutcome> first = binding.change(
        WalletPreference.launchAtStartup,
        value: true,
        isCurrent: source.captureView(),
      );
      await Future<void>.value();
      final Future<WalletPreferenceOutcome> second = binding.change(
        WalletPreference.launchAtStartup,
        value: false,
        isCurrent: source.captureView(),
      );
      final Future<WalletPreferenceOutcome> independent = binding.change(
        WalletPreference.desktopNotifications,
        value: true,
        isCurrent: source.captureView(),
      );
      expect(source.store.writes, hasLength(2));
      effect.complete(true);
      await Future.wait<WalletPreferenceOutcome>(
        <Future<WalletPreferenceOutcome>>[first, second, independent],
      ).timeout(const Duration(seconds: 1));
      expect(source.store.writes, hasLength(3));
      expect(source.store.entries[kLaunchAtStartupKey], isFalse);
      expect(source.store.entries[kEnableDesktopNotificationsKey], isTrue);
    },
  );

  for (final String replacement in <String>[
    'wallet',
    'preferences',
    'box',
    'client',
    'sender',
    'node',
    'path',
    'chain',
    'revision',
  ]) {
    test(
      'a $replacement replacement cannot apply an admitted old write',
      () async {
        final WalletSettingsFixture source = WalletSettingsFixture();
        source.store.deferred = true;
        final WalletSettingsBinding binding = source.bind();
        final Future<WalletPreferenceOutcome> operation = binding.change(
          WalletPreference.autoReceive,
          value: false,
          isCurrent: source.captureView(),
        );
        switch (replacement) {
          case 'wallet':
            source.wallet = Object();
          case 'preferences':
            source.preferences = Object();
          case 'box':
            source.box = Object();
          case 'client':
            source.client = Object();
          case 'sender':
            source.sender = Object();
          case 'node':
            source.node = 'replacement-node';
          case 'path':
            source.path = 'replacement-wallet';
          case 'chain':
            source.chain++;
          case 'revision':
            source.revision++;
        }
        source.store.writes.single.complete();
        final WalletPreferenceOutcome outcome = await operation.timeout(
          const Duration(seconds: 1),
        );
        expect(outcome.status, WalletPreferenceStatus.applyFailed);
        expect(outcome.committed, isTrue);
        expect(outcome.write, same(source.store.writes.single.reply.future));
        expect(source.effects, isEmpty);
        expect(source.notices, isEmpty);
        expect(binding.outcomes.single, same(outcome));
      },
    );
  }

  test(
    'stale queued choices and returned resources cannot regain authority',
    () async {
      final WalletSettingsFixture source = WalletSettingsFixture();
      final WalletSettingsBinding binding = source.bind();
      final Object original = source.wallet;
      source.wallet = Object();
      expect(binding.ownsResources, isFalse);
      source.wallet = original;
      expect(binding.ownsResources, isFalse);
      final WalletPreferenceOutcome outcome = await binding.change(
        WalletPreference.autoReceive,
        value: false,
        isCurrent: source.captureView(),
      );
      expect(outcome.status, WalletPreferenceStatus.refused);
      expect(source.store.writes, isEmpty);
    },
  );

  test(
    'write and effect failures preserve their exact original errors',
    () async {
      final WalletSettingsFixture source = WalletSettingsFixture();
      source.store.deferred = true;
      final WalletSettingsBinding binding = source.bind();
      final StateError error = StateError('Original synthetic write failure');
      final Future<WalletPreferenceOutcome> failed = binding.change(
        WalletPreference.clipboard,
        value: true,
        isCurrent: source.captureView(),
      );
      source.store.writes.single.reply.completeError(error);
      final WalletPreferenceOutcome saved = await failed;
      expect(saved.status, WalletPreferenceStatus.saveFailed);
      expect(saved.error, same(error));
      expect(saved.write, same(source.store.writes.single.reply.future));
      expect(source.effects, isEmpty);
      source.store.deferred = false;
      source.effect = () => Future<Object?>.error(error);
      final WalletPreferenceOutcome applied = await binding.change(
        WalletPreference.clipboard,
        value: true,
        isCurrent: source.captureView(),
      );
      expect(applied.status, WalletPreferenceStatus.applyFailed);
      expect(applied.committed, isTrue);
      expect(applied.error, same(error));
      expect(source.store.entries[kEnableClipboardWatcherKey], isTrue);
    },
  );

  test(
    'false platform answers and notification errors remain distinct',
    () async {
      final WalletSettingsFixture source = WalletSettingsFixture()
        ..effect = () => Future<Object?>.value(false);
      final WalletSettingsBinding binding = source.bind();
      final WalletPreferenceOutcome refused = await binding.change(
        WalletPreference.launchAtStartup,
        value: true,
        isCurrent: source.captureView(),
      );
      expect(refused.status, WalletPreferenceStatus.applyFailed);
      expect(refused.effectResult, isFalse);
      expect(refused.error, isNull);
      expect(refused.committed, isTrue);
      final StateError error = StateError(
        'Original synthetic observer failure',
      );
      source
        ..effect = null
        ..noticeError = error;
      final WalletPreferenceOutcome accepted = await binding.change(
        WalletPreference.desktopNotifications,
        value: true,
        isCurrent: source.captureView(),
      );
      expect(accepted.status, WalletPreferenceStatus.applied);
      expect(accepted.error, isNull);
      expect(accepted.observerError, same(error));
    },
  );

  test(
    'the original notice Future survives stale delivery without display',
    () async {
      final WalletSettingsFixture source = WalletSettingsFixture();
      final Completer<int> notice = Completer<int>();
      int displays = 0;
      bool notified = false;
      final WalletSettingsBinding binding = WalletSettingsBinding(
        store: source.store,
        ownsResources: () => true,
        apply:
            (
              _, {
              required bool value,
              required bool Function() ownsResources,
            }) => Future<Object?>.value(true),
        notify:
            (_, {required bool value, required bool Function() canDisplay}) {
              notified = true;
              return notice.future;
            },
        display:
            (_, {required bool value, required bool Function() canDisplay}) =>
                displays++,
      );
      final Future<WalletPreferenceOutcome> operation = binding.change(
        WalletPreference.desktopNotifications,
        value: true,
        isCurrent: source.captureView(),
      );
      for (int step = 0; step < 20 && !notified; step++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(notified, isTrue);
      source.leaveAndReturn();
      final StateError failure = StateError('Original notice backend failed');
      notice.completeError(failure);
      final WalletPreferenceOutcome outcome = await operation;
      expect(outcome.status, WalletPreferenceStatus.applied);
      expect(outcome.notification, same(notice.future));
      expect(outcome.observerError, same(failure));
      expect(outcome.error, isNull);
      expect(displays, 0);
      expect(binding.outcomes.single, same(outcome));
    },
  );
}
