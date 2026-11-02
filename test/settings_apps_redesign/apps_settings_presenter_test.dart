import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/settings_widgets/apps_settings_presenter.dart';

import 'support.dart';

void main() {
  late AppsFixture source;
  setUp(() => source = AppsFixture());
  tearDown(() => source.close());

  test(
    'persists a non-secret intent before the exact original effect',
    () async {
      source.deferredPersistence = true;
      final Completer<Object?> response = Completer<Object?>();
      final Object originalResult = Object();
      source.effect = (_, _) => response.future;
      final AppsSettingsBinding binding = source.bind();
      final Future<AppsActionOutcome> pending = binding.pair(
        Uri.parse(validPairingLink),
        source.captureView(),
      );
      expect(source.actions, isEmpty);
      expect(source.writes, hasLength(1));
      expect(source.writes.single.intent.stored, <String, Object>{
        'version': 1,
        'sequence': 1,
        'action': 'pair',
      });
      source.writes.single.complete();
      await source.effectStarted.future;
      expect(source.actions.single.$1, AppsActionKind.pair);
      response.complete(originalResult);
      final AppsActionOutcome outcome = await pending;
      expect(outcome.status, AppsActionStatus.completed);
      expect(
        identical(outcome.persistence, source.writes.single.reply.future),
        isTrue,
      );
      expect(identical(outcome.effect, response.future), isTrue);
      expect(identical(outcome.effectResult, originalResult), isTrue);
      expect(binding.outcomes.single, same(outcome));
    },
  );

  test(
    'a failed original write retains its exact error and admits no effect',
    () async {
      source.deferredPersistence = true;
      final AppsSettingsBinding binding = source.bind();
      final Object error = StateError('fixture persistence failure');
      final StackTrace stack = StackTrace.current;
      final Future<AppsActionOutcome> pending = binding.setEnabled(
        enabled: false,
        visible: source.captureView(),
      );
      source.writes.single.reply.completeError(error, stack);
      final AppsActionOutcome outcome = await pending;
      expect(outcome.status, AppsActionStatus.saveFailed);
      expect(outcome.error, same(error));
      expect(outcome.stackTrace, same(stack));
      expect(outcome.effect, isNull);
      expect(source.actions, isEmpty);
    },
  );

  for (final String resource in <String>['box', 'client', 'revision', 'view']) {
    test(
      'a changed $resource refuses effects after delayed persistence',
      () async {
        source.deferredPersistence = true;
        final AppsSettingsBinding binding = source.bind();
        final Future<AppsActionOutcome> pending = binding.disconnect(
          source.rows.first,
          source.captureView(),
        );
        final Map<String, Object?> originalEntries = source.entries;
        switch (resource) {
          case 'box':
            source
              ..box = Object()
              ..entries = <String, Object?>{};
          case 'client':
            source.client = Object();
          case 'revision':
            source.revision++;
          case 'view':
            source.leaveAndReturn();
        }
        source.writes.single.complete();
        final AppsActionOutcome outcome = await pending;
        expect(outcome.status, AppsActionStatus.refused);
        expect(source.actions, isEmpty);
        expect(originalEntries, contains('intent'));
        if (resource == 'box') expect(source.entries, isEmpty);
      },
    );
  }

  test('a backend that leaves and returns cannot revive its old receipt', () {
    final AppsSettingsBinding binding = source.bind();
    final Object original = source.box;
    source.box = Object();
    expect(binding.isCurrent, isFalse);
    source.box = original;
    expect(binding.isCurrent, isFalse);
    expect(binding.read().connections, isEmpty);
  });

  test('a same-topic replacement is not the original session', () async {
    final AppsSettingsBinding binding = source.bind();
    final AppsConnection original = source.rows.last;
    source.rows[1] = AppsConnection(
      identity: original.identity,
      incarnation: Object(),
      kind: original.kind,
      site: original.site,
      accounts: original.accounts,
      url: original.url,
      pairingTopic: original.pairingTopic,
      expiry: original.expiry,
      acknowledged: original.acknowledged,
    );
    final AppsActionOutcome outcome = await binding.disconnect(
      original,
      source.captureView(),
    );
    expect(outcome.status, AppsActionStatus.refused);
    expect(source.writes, isEmpty);
    expect(source.actions, isEmpty);
  });

  test(
    'a same-requester replacement cannot be removed after persistence',
    () async {
      source.deferredPersistence = true;
      final AppsSettingsBinding binding = source.bind();
      final AppsConnection original = source.rows.first;
      final Future<AppsActionOutcome> pending = binding.disconnect(
        original,
        source.captureView(),
      );
      source.rows[0] = AppsConnection(
        identity: original.identity,
        incarnation: 'grant:2',
        kind: original.kind,
        site: original.site,
        accounts: original.accounts,
      );
      source.writes.single.complete();
      expect((await pending).status, AppsActionStatus.refused);
      expect(source.actions, isEmpty);
      expect(source.rows.first.incarnation, 'grant:2');
    },
  );

  test('the original journal blocks duplicate remounted actions', () async {
    final Completer<Object?> response = Completer<Object?>();
    source.effect = (_, _) => response.future;
    final AppsSettingsBinding binding = source.bind();
    final Future<AppsActionOutcome> pending = binding.disconnect(
      source.rows.last,
      source.captureView(),
    );
    await source.effectStarted.future;
    final AppsSettingsBinding remounted = source.bind();
    expect(remounted.busy, isTrue);
    expect(
      (await remounted.disconnect(
        source.rows.last,
        source.captureView(),
      )).status,
      AppsActionStatus.refused,
    );
    expect(source.writes, hasLength(1));
    response.complete('original result');
    final AppsActionOutcome outcome = await pending;
    expect(remounted.outcomes.single, same(outcome));
    expect(remounted.busy, isFalse);
  });

  test(
    'an original effect error remains exact after presenter disposal',
    () async {
      final Completer<Object?> response = Completer<Object?>();
      source.effect = (_, _) => response.future;
      final AppsSettingsBinding binding = source.bind();
      final AppsSettingsPresenter presenter = AppsSettingsPresenter(binding);
      final bool Function() visible = source.captureView();
      final Future<AppsActionOutcome> pending = presenter.run(
        (AppsSettingsBinding original) =>
            original.disconnect(source.rows.last, visible),
        visible,
      );
      await source.effectStarted.future;
      await presenter.close();
      source.leaveAndReturn();
      final Object error = StateError('fixture transport failure');
      final StackTrace stack = StackTrace.current;
      response.completeError(error, stack);
      final AppsActionOutcome outcome = await pending;
      expect(outcome.status, AppsActionStatus.failed);
      expect(outcome.error, same(error));
      expect(outcome.stackTrace, same(stack));
      expect(identical(outcome.effect, response.future), isTrue);
      expect(binding.outcomes.single, same(outcome));
    },
  );

  test(
    'an accepted original result survives disposal without replacement paint',
    () async {
      final Completer<Object?> response = Completer<Object?>();
      source.effect = (_, _) => response.future;
      final AppsSettingsBinding binding = source.bind();
      final AppsSettingsPresenter presenter = AppsSettingsPresenter(binding);
      final bool Function() visible = source.captureView();
      final Future<AppsActionOutcome> pending = presenter.run(
        (AppsSettingsBinding original) =>
            original.setEnabled(enabled: false, visible: visible),
        visible,
      );
      await source.effectStarted.future;
      await presenter.close();
      response.complete(false);
      final AppsActionOutcome outcome = await pending;
      expect(outcome.status, AppsActionStatus.completed);
      expect(outcome.effectResult, isFalse);
      expect(binding.outcomes.single, same(outcome));
      expect(presenter.isClosed, isTrue);
    },
  );

  test(
    'pairing disconnection leaves its real session in the combined list',
    () async {
      source.effect = (AppsActionKind kind, Object? row) {
        expect(kind, AppsActionKind.disconnectPairing);
        expect(row, same(source.pairings.single));
        source.pairings = <AppsPairing>[];
        return Future<void>.value();
      };
      final AppsSettingsBinding binding = source.bind();
      final AppsActionOutcome outcome = await binding.disconnectPairing(
        source.pairings.single,
        source.captureView(),
      );
      expect(outcome.status, AppsActionStatus.completed);
      expect(binding.read().pairings, isEmpty);
      expect(binding.read().sessionCount, 1);
      expect(binding.read().connections.last.identity, 'fixture-session');
    },
  );

  test('snapshots detach granted accounts and labels from mutable input', () {
    final List<String> accounts = <String>['original'];
    final Map<String, String> labels = <String, String>{'original': 'Original'};
    final AppsConnection row = AppsConnection(
      identity: 'id',
      incarnation: Object(),
      kind: AppsConnectionKind.webApp,
      site: 'Example',
      accounts: accounts,
    );
    final List<AppsConnection> rows = <AppsConnection>[row];
    final AppsSnapshot snapshot = AppsSnapshot(
      webAppsAvailable: true,
      walletConnectAvailable: true,
      connections: rows,
      labels: labels,
    );
    accounts.add('replacement');
    labels.clear();
    rows.clear();
    expect(snapshot.connections.single.accounts, <String>['original']);
    expect(snapshot.labels, <String, String>{'original': 'Original'});
    expect(() => row.accounts.add('other'), throwsUnsupportedError);
    expect(snapshot.labels.clear, throwsUnsupportedError);
  });

  test('only the exact selected valid barcode is admitted', () {
    final Uri? selected = selectWalletConnectLink(<String?>[
      null,
      'https://example.invalid',
      'wc:invalid',
      validPairingLink,
    ]);
    expect('$selected', validPairingLink);
  });

  final List<String> invalidLinks = <String>[
    '',
    'https://example.invalid',
    'wc:invalid',
    validPairingLink.replaceFirst('@2', '@1'),
    '$validPairingLink&symKey=${List<String>.filled(64, 'c').join()}',
    '$validPairingLink#fragment',
    validPairingLink.replaceFirst('relay-protocol=irn', 'relay-protocol=other'),
    '$validPairingLink&expiryTimestamp=-1',
  ];
  for (int index = 0; index < invalidLinks.length; index++) {
    final String invalid = invalidLinks[index];
    test(
      'invalid pairing input ${index + 1} is refused before persistence',
      () async {
        expect(parseWalletConnectLink(invalid), isNull);
        final AppsSettingsBinding binding = source.bind();
        final AppsActionOutcome outcome = await binding.pair(
          Uri.parse(invalid),
          source.captureView(),
        );
        expect(outcome.status, AppsActionStatus.refused);
        expect(source.writes, isEmpty);
        expect(source.actions, isEmpty);
      },
    );
  }
}
