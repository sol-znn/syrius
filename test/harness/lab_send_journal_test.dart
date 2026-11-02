import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/send/model/send_intent.dart';
import 'package:zenon_syrius_wallet_flutter/utils/zts_utils.dart';

import '../../harness/app/fixtures/lab_seed_binding.dart';
import '../../harness/app/fixtures/seed_policy.dart';
import '../settings_addresses_redesign/support.dart';

SeedEnvironment _environment() => SeedEnvironment(
  profile: 'lab-send-fixture', isolated: true, unlocked: true,
  initialized: true, booted: true, ws: seedWsOrigin, http: seedHttpOrigin,
  nodeChain: 321, signingChain: 321, selectedIndex: 1,
  owner: fixtureAddress(2),
  members: <String>[fixtureAddress(1), fixtureAddress(2)],
);

SendIntent _intent({String? owner, String? recipient, String amount = '1'}) =>
    SendIntent.capture(fromAddress: owner ?? fixtureAddress(2),
      recipient: recipient ?? fixtureAddress(1),
      amount: amount, token: kZnnCoin,
    );

void main() {
  late Directory home;
  late ProfileSeedJournal journal;
  File record(String state) =>
      File('${home.path}/seed-$labSendRecipeId-$state.json');
  setUp(() async {
    // Small, newly owned controller-test files only; no wallet is opened.
    home = await Directory.systemTemp.createTemp('lab-send-journal-');
    journal = ProfileSeedJournal.forLabSend(home.path,
      environment: _environment(), intent: _intent());
  });
  tearDown(() => home.delete(recursive: true));

  test('restored records match the old profile and exact original hash', () {
    final String hash = fixtureHash(9);
    journal
      ..claim(labSendRecipeId)
      ..accepted(labSendRecipeId, hash)
      ..confirmed(labSendRecipeId, hash);
    final List<List<int>> before = <List<int>>[
      for (final String state in <String>['attempt', 'accepted', 'confirmed'])
        record(state).readAsBytesSync(),
    ];
    ProfileSeedJournal(home.path).requireRestoredLabSend(
      originalProfile: 'lab-send-fixture', owner: fixtureAddress(2),
      recipient: fixtureAddress(1), hash: hash,
    );
    expect(<List<int>>[
      for (final String state in <String>['attempt', 'accepted', 'confirmed'])
        record(state).readAsBytesSync(),
    ], before);
    expect(() => ProfileSeedJournal(home.path).requireLabSendConfirmed(hash),
      throwsA(isA<SeedRefused>()));
  });

  test('a restored profile cannot borrow another hash or review owner', () {
    final String hash = fixtureHash(9);
    journal
      ..claim(labSendRecipeId)
      ..accepted(labSendRecipeId, hash)
      ..confirmed(labSendRecipeId, hash);
    for (final (String, String, String) values in <(String, String, String)>[
      ('another-profile', fixtureAddress(2), hash),
      ('lab-send-fixture', fixtureAddress(3), hash),
      ('lab-send-fixture', fixtureAddress(2), fixtureHash(8)),
    ]) {
      expect(() => ProfileSeedJournal(home.path).requireRestoredLabSend(
        originalProfile: values.$1, owner: values.$2,
        recipient: fixtureAddress(1), hash: values.$3,
      ), throwsA(isA<SeedRefused>()));
    }
  });

  test('restored observation keeps unknown send and F06 attempts held', () {
    journal.claim(labSendRecipeId);
    void observe() => ProfileSeedJournal(home.path).requireRestoredLabSend(
      originalProfile: 'lab-send-fixture', owner: fixtureAddress(2),
      recipient: fixtureAddress(1), hash: fixtureHash(9),
    );
    expect(observe, throwsA(isA<SeedRefused>()));
    journal
      ..accepted(labSendRecipeId, fixtureHash(9))
      ..confirmed(labSendRecipeId, fixtureHash(9));
    ProfileSeedJournal(home.path).claim('stake');
    expect(observe, throwsA(isA<SeedRefused>()));
  });

  test('the exclusive attempt retains the exact immutable fixed review', () {
    journal.claim(labSendRecipeId);
    final Map<String, dynamic> value =
        jsonDecode(record('attempt').readAsStringSync())
            as Map<String, dynamic>;
    expect(value['recipe'], labSendRecipeId);
    expect(value['chain'], 321);
    expect(value['review'], <String, Object>{
      'profile': 'lab-send-fixture',
      'from': fixtureAddress(2), 'to': fixtureAddress(1),
      'recipientInput': fixtureAddress(1), 'amountInput': '1',
      'token': kZnnCoin.tokenStandard.toString(), 'amount': '100000000',
      'decimals': 8, 'symbol': 'ZNN', 'chain': 321,
    });
    expect(record('attempt').lengthSync(), lessThanOrEqualTo(2048));
  });

  test('an unknown P09 attempt blocks every F06 recipe after restart', () {
    journal.claim(labSendRecipeId);
    final ProfileSeedJournal restarted = ProfileSeedJournal(home.path);
    for (final String recipe in seedRecipeIds) {
      expect(
        () => restarted.requireAvailable(recipe), throwsA(isA<SeedRefused>()),
      );
    }
    expect(
      () => restarted.requireAvailable(labSendRecipeId),
      throwsA(isA<SeedRefused>()),
    );
    expect(record('attempt').existsSync(), isTrue);
  });

  test('an unresolved original F06 attempt also blocks P09', () {
    ProfileSeedJournal(home.path).claim('stake');
    expect(() => journal.claim(labSendRecipeId), throwsA(isA<SeedRefused>()));
    expect(record('attempt').existsSync(), isFalse);
  });

  test('a consistent confirmed P09 releases F06 but never a second P09', () {
    final String hash = fixtureHash(9);
    journal
      ..claim(labSendRecipeId)
      ..accepted(labSendRecipeId, hash)
      ..confirmed(labSendRecipeId, hash);
    final ProfileSeedJournal restarted = ProfileSeedJournal(home.path)
      ..requireAvailable('stake');
    expect(
      () => restarted.requireAvailable(labSendRecipeId),
      throwsA(isA<SeedRefused>()),
    );
    final Map<String, dynamic> confirmed =
        jsonDecode(record('confirmed').readAsStringSync())
            as Map<String, dynamic>;
    expect(confirmed['hash'], hash);
  });

  test('a different accepted hash never replaces the original record', () {
    journal
      ..claim(labSendRecipeId)
      ..accepted(labSendRecipeId, fixtureHash(9));
    final String original = record('accepted').readAsStringSync();
    expect(
      () => journal.accepted(labSendRecipeId, fixtureHash(10)),
      throwsA(isA<SeedRefused>()),
    );
    expect(record('accepted').readAsStringSync(), original);
    expect(
      () => ProfileSeedJournal(home.path).requireAvailable('stake'),
      throwsA(isA<SeedRefused>()),
    );
  });

  test(
    'review mutation or unknown fields cannot release a claimed attempt',
    () {
      journal
        ..claim(labSendRecipeId)
        ..accepted(labSendRecipeId, fixtureHash(9));
      final Map<String, dynamic> accepted =
          jsonDecode(record('accepted').readAsStringSync())
              as Map<String, dynamic>;
      final Map<String, dynamic> changed = Map<String, dynamic>.of(accepted);
      changed['review'] = <String, dynamic>{
        ...accepted['review'] as Map<String, dynamic>,
        'from': fixtureAddress(3),
      };
      record('accepted').writeAsStringSync(jsonEncode(changed), flush: true);
      expect(
        () => ProfileSeedJournal(home.path).requireAvailable('stake'),
        throwsA(isA<SeedRefused>()),
      );
      changed['review'] = <String, dynamic>{
        ...accepted['review'] as Map<String, dynamic>, 'unexpected': true,
      };
      record('accepted').writeAsStringSync(jsonEncode(changed), flush: true);
      expect(
        () => ProfileSeedJournal(home.path).requireAvailable('stake'),
        throwsA(isA<SeedRefused>()),
      );
    },
  );

  test('the fixed journal refuses a different owner, recipient or amount', () {
    for (final SendIntent intent in <SendIntent>[
      _intent(owner: fixtureAddress(3)), _intent(recipient: fixtureAddress(3)),
      _intent(amount: '2'), _intent(amount: '1.0'),
    ]) {
      expect(() => ProfileSeedJournal.forLabSend(home.path,
        environment: _environment(), intent: intent,
      ), throwsA(isA<SeedRefused>()));
    }
    expect(home.listSync(), isEmpty);
  });

  test('an ordinary seed journal cannot create or replace a P09 review', () {
    expect(
      () => ProfileSeedJournal(home.path).claim(labSendRecipeId),
      throwsA(isA<SeedRefused>()),
    );
    expect(record('attempt').existsSync(), isFalse);
    journal.claim(labSendRecipeId);
    final String original = record('attempt').readAsStringSync();
    expect(() => journal.claim(labSendRecipeId), throwsA(isA<SeedRefused>()));
    expect(record('attempt').readAsStringSync(), original);
  });

  test('the original confirmed review can be checked without journal writes',
      () {
    final String hash = fixtureHash(9);
    journal
      ..claim(labSendRecipeId)
      ..accepted(labSendRecipeId, hash)
      ..confirmed(labSendRecipeId, hash);
    final Map<String, String> before = <String, String>{
      for (final String state in <String>['attempt', 'accepted', 'confirmed'])
        state: record(state).readAsStringSync(),
    };
    journal.requireLabSendConfirmed(hash);
    for (final String state in before.keys) {
      expect(record(state).readAsStringSync(), before[state]);
    }
    expect(() => ProfileSeedJournal(home.path).requireLabSendConfirmed(hash),
      throwsA(isA<SeedRefused>()));
  });

  test('a missing, different or extended confirmation stays held', () {
    final String hash = fixtureHash(9);
    journal.claim(labSendRecipeId);
    expect(() => journal.requireLabSendConfirmed(hash),
      throwsA(isA<SeedRefused>()));
    journal.accepted(labSendRecipeId, hash);
    expect(() => journal.requireLabSendConfirmed(hash),
      throwsA(isA<SeedRefused>()));
    journal.confirmed(labSendRecipeId, hash);
    expect(() => journal.requireLabSendConfirmed(fixtureHash(10)),
      throwsA(isA<SeedRefused>()));
    final Map<String, dynamic> value =
        jsonDecode(record('confirmed').readAsStringSync())
            as Map<String, dynamic>;
    value['unexpected'] = true;
    record('confirmed').writeAsStringSync(jsonEncode(value), flush: true);
    expect(() => journal.requireLabSendConfirmed(hash),
      throwsA(isA<SeedRefused>()));
  });

  test('an existing F06 attempt cannot become the original-send baseline', () {
    final String hash = fixtureHash(9);
    journal
      ..claim(labSendRecipeId)
      ..accepted(labSendRecipeId, hash)
      ..confirmed(labSendRecipeId, hash);
    ProfileSeedJournal(home.path).claim('fuse');
    expect(() => journal.requireLabSendConfirmed(hash),
      throwsA(isA<SeedRefused>()));
    expect(File('${home.path}/seed-fuse-attempt.json').existsSync(), isTrue);
    expect(record('confirmed').existsSync(), isTrue);
  });
}
