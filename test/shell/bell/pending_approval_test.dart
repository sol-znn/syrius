import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:zenon_syrius_wallet_flutter/services/pending_session_approval.dart';

import 'support.dart';

void main() {
  late FakeApprovalClient client;
  setUp(() => client = FakeApprovalClient());
  tearDown(() => client.controller.dispose());

  test('copies namespace lists and deduplicates proposal IDs', () {
    final List<String> mutable = <String>['zenon:1:address-a'];
    final ApprovalNamespace namespace = ApprovalNamespace(accounts: mutable);
    mutable.add('zenon:1:address-b');
    expect(namespace.accounts, <String>['zenon:1:address-a']);
    expect(() => namespace.accounts.add('another'), throwsUnsupportedError);
    final PendingSessionApproval proposal = client.add(1);
    client.controller.enqueue(proposal);
    expect(client.controller.value, hasLength(1));
  });

  test('a busy decision cannot be approved or declined twice', () async {
    client
      ..add(1)
      ..gate = Completer<void>();
    final Future<ApprovalDecision> first = client.controller.resolve(
      1,
      accept: true,
    );
    expect(client.controller.value.single.busy, isTrue);
    expect(
      await client.controller.resolve(1, accept: false),
      ApprovalDecision.unavailable,
    );
    client.gate!.complete();
    expect(await first, ApprovalDecision.approved);
    expect(client.approveCalls, 1);
    expect(client.declineCalls, 0);
    expect(client.controller.value, isEmpty);
  });

  test('expiry and missing client proposals refuse before dispatch', () async {
    client.add(1);
    client.now = client.now.add(const Duration(minutes: 6));
    expect(
      await client.controller.resolve(1, accept: true),
      ApprovalDecision.unavailable,
    );
    client.add(2);
    client.proposals.remove(2);
    expect(
      await client.controller.resolve(2, accept: false),
      ApprovalDecision.unavailable,
    );
    expect(client.approveCalls + client.declineCalls, 0);
  });

  for (final String change in <String>['wallet', 'chain', 'client', 'lock']) {
    test('$change change refuses a captured decision', () async {
      client.add(1);
      switch (change) {
        case 'wallet':
          client.scope = '1:wallet-b';
        case 'chain':
          client.scope = '2:wallet-a';
        case 'client':
          client.identity = Object();
        case 'lock':
          client.unlocked = false;
      }
      expect(
        await client.controller.resolve(1, accept: true),
        ApprovalDecision.unavailable,
      );
      expect(client.approveCalls, 0);
    });
  }

  test('a context change during transport cannot report approval', () async {
    client
      ..add(1)
      ..gate = Completer<void>();
    final Future<ApprovalDecision> decision = client.controller.resolve(
      1,
      accept: true,
    );
    client.scope = '2:wallet-a';
    client.gate!.complete();
    expect(await decision, ApprovalDecision.uncertain);
    expect(client.controller.value, isEmpty);
  });

  test(
    'uncertain transport disables the original request without retry',
    () async {
      client
        ..add(1)
        ..fail = true;
      expect(
        await client.controller.resolve(1, accept: true),
        ApprovalDecision.uncertain,
      );
      expect(client.controller.value.single.failed, isTrue);
      expect(client.controller.value.single.canDecide, isFalse);
      expect(
        await client.controller.resolve(1, accept: true),
        ApprovalDecision.unavailable,
      );
      expect(client.approveCalls, 1);
    },
  );

  test('refresh removes deleted requests and invalidate sends no answer', () {
    client.add(1);
    client.proposals.clear();
    client.controller.refresh();
    expect(client.controller.value, isEmpty);
    client.add(2);
    client.controller.invalidate();
    expect(client.controller.value, isEmpty);
    expect(client.approveCalls + client.declineCalls, 0);
  });

  test(
    'late completion after disposal is uncertain and has no notifications',
    () async {
      client
        ..add(1)
        ..gate = Completer<void>();
      final Future<ApprovalDecision> decision = client.controller.resolve(
        1,
        accept: true,
      );
      client.controller.dispose();
      client.gate!.complete();
      expect(await decision, ApprovalDecision.uncertain);
      // Give tearDown a fresh, unused owner rather than disposing twice.
      client = FakeApprovalClient();
    },
  );
}
