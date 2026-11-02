import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:zenon_syrius_wallet_flutter/services/contacts_store.dart';
import 'package:zenon_syrius_wallet_flutter/utils/zts_utils.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/settings_widgets/addresses_settings_binding.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/settings_widgets/addresses_settings_presenter.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

import 'support.dart';

Future<void> flush() async {
  for (int index = 0; index < 12; index++) {
    await Future<void>.value();
  }
}

void main() {
  test('resource departure and revision ABA cannot revive a capture', () {
    Object resource = Object();
    final Object original = resource;
    int revision = 1;
    final AddressesSettingsResources source = AddressesSettingsResources(
      identities: () => <Object>[resource],
      values: () => <int>[revision],
      ready: () => true,
    );
    resource = Object();
    expect(source.isCurrent, isFalse);
    resource = original;
    expect(source.isCurrent, isFalse);
    final AddressesSettingsResources generation = AddressesSettingsResources(
      identities: () => <Object>[resource],
      values: () => <int>[revision],
      ready: () => true,
    );
    revision++;
    expect(generation.isCurrent, isFalse);
    revision--;
    expect(generation.isCurrent, isFalse);
  });

  test('a returning resource proof retains nested revocation', () {
    final Object identity = Object();
    bool ready = true;
    bool reenter = false;
    final List<bool> nested = <bool>[];
    late final AddressesSettingsResources source;
    source = AddressesSettingsResources(
      identities: () => <Object>[identity],
      values: () => <int>[1],
      ready: () {
        final bool accepted = ready;
        if (reenter) {
          reenter = false;
          ready = false;
          nested.add(source.isCurrent);
          ready = true;
        }
        return accepted;
      },
    );
    expect(source.isCurrent, isTrue);
    reenter = true;
    expect(source.isCurrent, isFalse);
    expect(nested, <bool>[false]);
    expect(ready, isTrue);
    expect(source.isCurrent, isFalse);
  });

  test(
    'a returning binding proof cannot authorize reads after nested loss',
    () async {
      final AddressesFixture source = AddressesFixture();
      bool current = true;
      bool reenter = false;
      int reads = 0;
      final List<bool> nested = <bool>[];
      late final AddressesSettingsBinding binding;
      source.accountRead = (String address) {
        reads++;
        return Future<AddressesAccount>.value(source.accounts[address]!);
      };
      binding = source.bind(
        sourceIsCurrent: () {
          final bool accepted = current;
          if (reenter) {
            reenter = false;
            current = false;
            nested.add(binding.ownsResources);
            current = true;
          }
          return accepted;
        },
      );
      expect(binding.ownsResources, isTrue);
      reenter = true;
      expect(binding.ownsResources, isFalse);
      expect(nested, <bool>[false]);
      expect(current, isTrue);
      expect(binding.ownsResources, isFalse);
      await expectLater(
        binding.readBalances(),
        throwsA(isA<AddressesSettingsRefused>()),
      );
      expect(reads, 0);
    },
  );

  test(
    'balances require complete matching account and native-token facts',
    () async {
      final AddressesFixture source = AddressesFixture();
      final AddressesSettingsBinding binding = source.bind();
      expect((await binding.readBalances()).keys, source.members);
      source.accountRead = (String address) async => AddressesAccount(
        address: source.members.last,
        height: 0,
        znn: BigInt.zero,
        qsr: BigInt.zero,
      );
      await expectLater(binding.readBalances(), throwsFormatException);
      expect(
        () => addressesAccountFromSdk(
          AccountInfo(address: source.members.first, blockCount: 0),
          source.members.first,
        ),
        throwsFormatException,
      );
      expect(
        () => addressesAccountFromSdk(
          AccountInfo(
            address: source.members.first,
            blockCount: 1,
            balanceInfoList: <BalanceInfoListItem>[
              BalanceInfoListItem(token: kZnnCoin, balance: BigInt.one),
              BalanceInfoListItem(token: kZnnCoin, balance: BigInt.one),
            ],
          ),
          source.members.first,
        ),
        throwsFormatException,
      );
    },
  );

  test('a newer read wins and disposal discards pending paint', () async {
    final AddressesFixture source = AddressesFixture();
    final List<Completer<AddressesAccount>> pending =
        <Completer<AddressesAccount>>[];
    source.accountRead = (String address) {
      if (address == source.members.last) {
        return Future<AddressesAccount>.value(source.accounts[address]!);
      }
      final Completer<AddressesAccount> reply = Completer<AddressesAccount>();
      pending.add(reply);
      return reply.future;
    };
    final AddressesSettingsPresenter presenter = AddressesSettingsPresenter(
      binding: source.bind(),
    );
    final Future<void> old = presenter.refresh();
    final Future<void> latest = presenter.refresh();
    pending[1].complete(source.accounts[source.members.first]!);
    await latest;
    expect(presenter.state.balances, hasLength(2));
    pending[0].completeError(StateError('old failure'));
    await old;
    expect(presenter.state.balancesFailed, isFalse);
    final Future<void> last = presenter.refresh();
    await presenter.close();
    pending.last.complete(source.accounts[source.members.first]!);
    await last;
    expect(presenter.isClosed, isTrue);
  });

  test(
    'chain statistics require every linked page and a stable frontier',
    () async {
      final AddressesFixture source = AddressesFixture();
      final AddressesSettingsBinding binding = source.bind();
      final AddressesChainSnapshot complete = await binding.readChain();
      expect(complete.height, 3);
      expect(complete.counts, <int, int>{2: 3});
      source.blockRead = (_, _, _) async => source.blocks.take(2).toList();
      await expectLater(binding.readChain(), throwsFormatException);
      source.blockRead = (_, _, _) async => <AddressesChainBlock>[
        source.blocks.first,
        source.blocks.first,
        source.blocks.last,
      ];
      await expectLater(binding.readChain(), throwsFormatException);
      source.blockRead = null;
      int frontiers = 0;
      source.frontierRead = (_) async {
        frontiers++;
        return frontiers == 1 ? source.blocks.last : source.blocks.first;
      };
      await expectLater(binding.readChain(), throwsFormatException);
    },
  );

  test('an exact empty chain is distinct from missing pages', () async {
    final AddressesFixture source = AddressesFixture();
    source.accounts[source.members.first] = AddressesAccount(
      address: source.members.first,
      height: 0,
      znn: BigInt.zero,
      qsr: BigInt.zero,
    );
    source.blocks = <AddressesChainBlock>[];
    expect((await source.bind().readChain()).height, 0);
  });

  test(
    'pending labels stay committed across a remount and retain original Future',
    () async {
      final AddressesFixture source = AddressesFixture()..delayLabels = true;
      final AddressesSettingsBinding original = source.bind();
      final Future<AddressesWriteOutcome> pending = original.rename(
        source.members.first,
        'Savings',
        isCurrent: source.captureView(),
      );
      await flush();
      expect(original.labels[source.members.first], 'Address 1');
      final AddressesSettingsBinding remount = source.bind();
      expect(remount.labels[source.members.first], 'Address 1');
      expect(remount.busy, isTrue);
      final AddressesSettingsPresenter disposed = AddressesSettingsPresenter(
        binding: original,
      );
      await disposed.close();
      source.labelWrites.single.$3.complete();
      final AddressesWriteOutcome result = await pending;
      expect(result.committed, isTrue);
      expect(result.write, same(source.labelWrites.single.$3.future));
      expect(remount.labels[source.members.first], 'Savings');
      expect(remount.outcomes.single, same(result));
    },
  );

  test(
    'failed writes retain exact errors and never paint an optimistic label',
    () async {
      final AddressesFixture source = AddressesFixture()..delayLabels = true;
      final AddressesSettingsBinding binding = source.bind();
      final Future<AddressesWriteOutcome> pending = binding.rename(
        source.members.first,
        'Savings',
        isCurrent: source.captureView(),
      );
      await flush();
      final StateError original = StateError('original write failure');
      source.labelWrites.single.$3.completeError(original);
      final AddressesWriteOutcome result = await pending;
      expect(result.error, same(original));
      expect(result.committed, isFalse);
      expect(binding.labels[source.members.first], 'Address 1');
    },
  );

  test('queued edits refuse an old view after leave and return', () async {
    final AddressesFixture source = AddressesFixture()..delayLabels = true;
    final AddressesSettingsBinding binding = source.bind();
    final bool Function() current = source.captureView();
    final Future<AddressesWriteOutcome> first = binding.rename(
      source.members.first,
      'Savings',
      isCurrent: current,
    );
    final Future<AddressesWriteOutcome> queued = binding.rename(
      source.members.last,
      'Other',
      isCurrent: current,
    );
    await flush();
    source.leaveAndReturn();
    source.labelWrites.single.$3.complete();
    expect((await first).committed, isTrue);
    expect((await queued).error, isA<AddressesSettingsRefused>());
    expect(source.labelWrites, hasLength(1));
  });

  test('contact edits publish only successful original writes', () async {
    final AddressesFixture source = AddressesFixture();
    source.contactBox.deferred = true;
    final Future<Contact> add = source.contacts.add(
      name: 'Alice',
      address: fixtureAddress(8),
    );
    await flush();
    expect(source.contacts.contacts, isEmpty);
    final StateError original = StateError('contact write failure');
    final Future<void> checked = expectLater(add, throwsA(same(original)));
    source.contactBox.writes.single.reply.completeError(original);
    await checked;
    expect(source.contacts.contacts, isEmpty);
    expect(source.contacts.writeOutcomes.single.error, same(original));
    expect(
      source.contacts.writeOutcomes.single.write,
      same(source.contactBox.writes.single.reply.future),
    );
  });

  test(
    'same-Box contact additions serialize without losing another store',
    () async {
      final MemoryContactsBox box = MemoryContactsBox()..deferred = true;
      final ContactsStore one = ContactsStore(box: box);
      final ContactsStore two = ContactsStore(box: box);
      final Future<Contact> first = one.add(
        name: 'Alice',
        address: fixtureAddress(8),
      );
      final Future<Contact> second = two.add(
        name: 'Bob',
        address: fixtureAddress(9),
      );
      await flush();
      expect(box.writes, hasLength(1));
      box.writes.first.complete();
      await first;
      await flush();
      expect(box.writes, hasLength(2));
      box.writes.last.complete();
      await second;
      expect(two.contacts.map((Contact contact) => contact.name), <String>[
        'Alice',
        'Bob',
      ]);
    },
  );

  test(
    'a remount does not read an optimistic contact as a saved contact',
    () async {
      final MemoryContactsBox box = MemoryContactsBox()
        ..deferred = true
        ..optimistic = true;
      final ContactsStore one = ContactsStore(box: box);
      final Future<Contact> pending = one.add(
        name: 'Alice',
        address: fixtureAddress(8),
      );
      await flush();
      final ContactsStore remount = ContactsStore(box: box);
      expect(remount.contacts, isEmpty);
      box.writes.single.complete();
      await pending;
      expect(one.contacts.single.name, 'Alice');
    },
  );

  test(
    'incomplete saved contacts stay unreadable to editors without rewriting',
    () async {
      final MemoryContactsBox box = MemoryContactsBox();
      box.entries['contacts'] = '{damaged';
      final ContactsStore contacts = ContactsStore(box: box);
      expect(contacts.contacts, isEmpty);
      expect(contacts.contactsReadComplete, isFalse);
      await expectLater(
        contacts.add(name: 'Alice', address: fixtureAddress(8)),
        throwsA(isA<ContactsException>()),
      );
      expect(box.entries['contacts'], '{damaged');
      expect(box.writes, isEmpty);
    },
  );

  test(
    'a label receipt cannot revive after a value changes and returns',
    () async {
      final AddressesFixture source = AddressesFixture();
      final AddressesSettingsBinding binding = source.bind();
      final String address = source.members.first;
      final Object original = binding.labelOwner(address)!;
      await binding.rename(address, 'Savings', isCurrent: () => true);
      await binding.rename(address, 'Address 1', isCurrent: () => true);
      final AddressesWriteOutcome result = await binding.rename(
        address,
        'Other',
        isCurrent: () => true,
        expectedOwner: original,
      );
      expect(result.error, isA<AddressesSettingsRefused>());
      expect(binding.labels[address], 'Address 1');
      expect(source.labelWrites, hasLength(2));
    },
  );

  test(
    'an accepted send stays known when its original history write fails',
    () async {
      final MemoryContactsBox box = MemoryContactsBox()..deferred = true;
      final ContactsStore contacts = ContactsStore(box: box);
      final Future<void> pending = contacts.noteSent(
        fixtureAddress(1),
        fixtureAddress(8),
      );
      await flush();
      final StateError original = StateError('original history storage');
      final Future<void> checked = expectLater(
        pending,
        throwsA(same(original)),
      );
      box.writes.single.reply.completeError(original);
      await checked;
      expect(
        contacts.lastSent(fixtureAddress(8), from: fixtureAddress(1)),
        isNotNull,
      );
      expect(contacts.writeOutcomes.single.error, same(original));
    },
  );
}
