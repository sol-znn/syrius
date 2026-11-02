import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:zenon_syrius_wallet_flutter/services/contacts_store.dart';
import 'package:zenon_syrius_wallet_flutter/utils/constants.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

/// A real address, checksum and all, different for each [n].
String _address(int n) => Address(
  'z',
  <int>[0, n ~/ 256, n % 256, ...List<int>.filled(17, 7)],
).toString();

final String _alice = _address(1);
final String _bob = _address(2);
final String _carol = _address(3);
final String _me = _address(100);
final String _meToo = _address(101);

/// What an address-poisoning copy of [address] looks like: its ends, and a
/// middle of its own. Not a valid address, which the checks do not ask for:
/// they compare what a person would compare.
String _copyOf(String address, {int lead = 4, int tail = 4}) {
  final String middle = address
      .substring(2 + lead, address.length - tail)
      .split('')
      .map((String char) => char == 'x' ? 'y' : 'x')
      .join();
  return address.substring(0, 2 + lead) +
      middle +
      address.substring(address.length - tail);
}

Matcher _refuses(ContactError error) => throwsA(
  isA<ContactsException>().having(
    (ContactsException e) => e.error,
    'error',
    error,
  ),
);

/// A clock that moves a minute at each reading, so order is never a tie.
DateTime Function() _clock() {
  DateTime now = DateTime(2026, 10, 13, 12);
  return () => now = now.add(const Duration(minutes: 1));
}

void main() {
  late ContactsStore store;

  setUp(() => store = ContactsStore(clock: _clock()));

  group('contacts', () {
    test('are listed by name, whatever the case and the order added', () async {
      await store.add(name: 'carol', address: _carol);
      await store.add(name: 'Alice', address: _alice, note: ' rent ');
      await store.add(name: 'Bob', address: _bob);

      expect(
        store.contacts.map((Contact c) => c.name),
        <String>['Alice', 'Bob', 'carol'],
      );
      expect(store.byAddress(_alice)!.note, 'rent');
      expect(store.byAddress(_bob)!.note, isNull);
      expect(store.byAddress(_address(9)), isNull);
      expect(store.byAddress('not an address'), isNull);
      expect(store.isPersistent, isFalse);
    });

    test('take a name trimmed and an address in any case', () async {
      final Contact added = await store.add(
        name: '  Alice  ',
        address: ' ${_alice.toUpperCase()} ',
      );
      expect(added.name, 'Alice');
      expect(added.address, _alice);
      expect(store.byAddress(_alice.toUpperCase()), added);
    });

    test('refuse what is not a z1 address', () async {
      for (final String bad in <String>[
        '',
        'alice',
        _alice.substring(0, 39),
        // The right length and alphabet, the wrong checksum.
        '${_alice.substring(0, 39)}${_alice.endsWith('q') ? 'p' : 'q'}',
        // A valid bech32 string of another network.
        Address('x', <int>[0, ...List<int>.filled(19, 7)]).toString(),
      ]) {
        await expectLater(
          store.add(name: 'Alice', address: bad),
          _refuses(ContactError.invalidAddress),
          reason: bad,
        );
      }
      expect(store.contacts, isEmpty);
    });

    test('refuse an empty, an overlong and a taken name', () async {
      await expectLater(
        store.add(name: '   ', address: _alice),
        _refuses(ContactError.emptyName),
      );
      await expectLater(
        store.add(name: 'a' * (kContactNameMaxLength + 1), address: _alice),
        _refuses(ContactError.nameTooLong),
      );
      await store.add(name: 'a' * kContactNameMaxLength, address: _carol);

      await store.add(name: 'Alice', address: _alice);
      await expectLater(
        store.add(name: ' ALICE', address: _bob),
        _refuses(ContactError.nameTaken),
      );
      await expectLater(
        store.add(name: 'Alice again', address: _alice),
        _refuses(ContactError.addressTaken),
      );
      expect(store.contacts, hasLength(2));
    });

    test('are renamed, keeping address, note and time', () async {
      final Contact alice = await store.add(
        name: 'Alice',
        address: _alice,
        note: 'rent',
      );
      await store.add(name: 'Bob', address: _bob);

      final Contact renamed = await store.rename(_alice, ' Alicia ');
      expect(renamed.name, 'Alicia');
      expect(renamed.address, _alice);
      expect(renamed.note, 'rent');
      expect(renamed.added, alice.added);
      expect(store.byAddress(_alice), renamed);

      // Its own name in another case is a change, not a clash.
      expect((await store.rename(_alice, 'ALICIA')).name, 'ALICIA');

      await expectLater(
        store.rename(_alice, 'bob'),
        _refuses(ContactError.nameTaken),
      );
      await expectLater(
        store.rename(_alice, ' '),
        _refuses(ContactError.emptyName),
      );
      await expectLater(
        store.rename(_carol, 'Carol'),
        _refuses(ContactError.notFound),
      );
      expect(store.byAddress(_alice)!.name, 'ALICIA');
    });

    test('have a note that can be set and removed', () async {
      await store.add(name: 'Alice', address: _alice);
      expect((await store.setNote(_alice, ' rent ')).note, 'rent');
      expect((await store.setNote(_alice, '  ')).note, isNull);
      await expectLater(
        store.setNote(_bob, 'x'),
        _refuses(ContactError.notFound),
      );
    });

    test('are removed, and the name is free again', () async {
      await store.add(name: 'Alice', address: _alice);
      await store.remove(_alice);
      expect(store.contacts, isEmpty);
      await expectLater(store.remove(_alice), _refuses(ContactError.notFound));
      await store.add(name: 'alice', address: _bob);
      expect(store.byAddress(_bob)!.name, 'alice');
    });

    test('are found by a piece of the name or of the address', () async {
      await store.add(name: 'Alice', address: _alice);
      await store.add(name: 'Malice Ltd', address: _bob);
      await store.add(name: 'Carol', address: _carol);

      expect(
        store.search('ALIC').map((Contact c) => c.name),
        <String>['Alice', 'Malice Ltd'],
      );
      expect(
        store.search(_carol.substring(3, 12)).map((Contact c) => c.name),
        <String>['Carol'],
      );
      expect(store.search('  '), hasLength(3));
      expect(store.search('nobody'), isEmpty);
    });

    test('tell listeners when admitted operations settle', () async {
      final List<ContactsWriteOutcome> settled = <ContactsWriteOutcome>[];
      final List<bool> pendingAtNotification = <bool>[];
      store.addListener(() {
        settled.add(store.writeOutcomes.last);
        pendingAtNotification.add(store.hasPendingWrite);
      });

      await store.add(name: 'Alice', address: _alice);
      await store.rename(_alice, 'Alicia');
      await store.setNote(_alice, 'rent');
      await store.noteSent(_me, _alice);
      await store.remove(_alice);
      expect(settled, hasLength(5));
      expect(settled, store.writeOutcomes);
      for (final ContactsWriteOutcome outcome in settled) {
        expect(outcome.committed, isTrue);
        expect(outcome.write, isNull);
        expect(outcome.error, isNull);
      }
      final List<Contact> contacts = List<Contact>.of(store.contacts);
      final List<RecentRecipient> recent = List<RecentRecipient>.of(
        store.recent(_me),
      );

      await expectLater(
        store.add(name: '', address: _alice),
        _refuses(ContactError.emptyName),
      );
      expect(settled, hasLength(6));
      expect(settled, store.writeOutcomes);
      final ContactsWriteOutcome refusal = settled.last;
      expect(refusal.committed, isFalse);
      expect(refusal.write, isNull);
      expect(
        refusal.error,
        isA<ContactsException>().having(
          (ContactsException error) => error.error,
          'error',
          ContactError.emptyName,
        ),
      );
      expect(refusal.stackTrace, isNotNull);
      expect(store.contacts, contacts);
      expect(store.recent(_me), recent);
      expect(pendingAtNotification, List<bool>.filled(6, false));
      expect(store.hasPendingWrite, isFalse);

      final List<ContactsWriteOutcome> beforeIgnored =
          List<ContactsWriteOutcome>.of(settled);
      await store.noteSent(_me, 'nowhere');
      expect(settled, beforeIgnored);
      expect(store.writeOutcomes, beforeIgnored);
      expect(store.contacts, contacts);
      expect(store.recent(_me), recent);
      expect(pendingAtNotification, List<bool>.filled(6, false));
      expect(store.hasPendingWrite, isFalse);
    });
  });

  group('recent recipients', () {
    test('are newest first, each once, five shown', () async {
      for (int i = 1; i <= 7; i++) {
        await store.noteSent(_me, _address(i));
      }
      // Sent to again: it moves to the front and is not there twice.
      await store.noteSent(_me, _address(4));

      expect(
        store.recent(_me).map((RecentRecipient r) => r.address),
        <String>[
          _address(4),
          _address(7),
          _address(6),
          _address(5),
          _address(3),
        ],
      );
      expect(store.recent(_me, limit: kRecentRecipientsKept), hasLength(7));
      expect(store.recent(_me, limit: 2), hasLength(2));
    });

    test('are kept for each sending address apart', () async {
      await store.noteSent(_me, _alice);
      await store.noteSent(_meToo, _bob);

      expect(store.recent(_me).single.address, _alice);
      expect(store.recent(_meToo).single.address, _bob);
      expect(store.recent(_address(102)), isEmpty);
    });

    test('are capped, the oldest going first', () async {
      for (int i = 1; i <= kRecentRecipientsKept + 20; i++) {
        await store.noteSent(_me, _address(i));
      }
      final List<RecentRecipient> all = store.recent(_me, limit: 100000);
      expect(all, hasLength(kRecentRecipientsKept));
      expect(all.first.address, _address(kRecentRecipientsKept + 20));
      expect(all.last.address, _address(21));
      expect(store.isFirstTime(_me, _address(20)), isTrue);
      expect(store.isFirstTime(_me, _address(21)), isFalse);
    });

    test('carry the time of the last send', () async {
      expect(store.lastSent(_alice), isNull);
      await store.noteSent(_me, _alice);
      final DateTime first = store.lastSent(_alice)!;
      await store.noteSent(_meToo, _alice);
      final DateTime second = store.lastSent(_alice)!;

      expect(second.isAfter(first), isTrue);
      expect(store.lastSent(_alice, from: _me), first);
      expect(store.lastSent(_alice, from: _meToo), second);
      expect(store.lastSent(_bob, from: _me), isNull);
    });

    test('ignore what is not an address, and never throw', () async {
      await store.noteSent(_me, 'nowhere');
      await store.noteSent('nobody', _alice);
      expect(store.recent(_me), isEmpty);
      expect(store.recent('nobody'), isEmpty);
    });

    test('outlive the contact they were sent to', () async {
      await store.add(name: 'Alice', address: _alice);
      await store.noteSent(_me, _alice);
      await store.remove(_alice);
      expect(store.recent(_me).single.address, _alice);
    });
  });

  group('first time', () {
    test('is true until this address has sent there', () async {
      expect(store.isFirstTime(_me, _alice), isTrue);

      await store.noteSent(_me, _alice);
      expect(store.isFirstTime(_me, _alice), isFalse);
      expect(store.isFirstTime(_me, ' ${_alice.toUpperCase()}'), isFalse);
      expect(store.isFirstTime(_me, _bob), isTrue);
      // Another of the wallet's addresses has not.
      expect(store.isFirstTime(_meToo, _alice), isTrue);
    });

    test('is about sends, not about the address book', () async {
      await store.add(name: 'Alice', address: _alice);
      expect(store.isFirstTime(_me, _alice), isTrue);
    });

    test('as a function over a list', () {
      expect(isFirstTimeAmong(_alice, <String>[]), isTrue);
      expect(isFirstTimeAmong(_alice, <String>[_bob, _alice]), isFalse);
      expect(isFirstTimeAmong(_alice, <String>[_bob]), isTrue);
    });
  });

  group('look-alike', () {
    test('the differing positions are the ones that differ', () {
      expect(differingPositions('abcdef', 'abcdef'), isEmpty);
      expect(differingPositions('abcdef', 'abXdeY'), <int>[2, 5]);
      expect(differingPositions('abc', 'abcde'), <int>[3, 4]);
      expect(differingPositions('abcde', 'aXc'), <int>[1, 3, 4]);
    });

    test('is the same four after z1 and the same last four', () {
      final String copy = _copyOf(_alice);
      expect(resembles(copy, _alice), isTrue);
      expect(resembles(_alice, copy), isTrue);
      expect(resembles(_alice, _alice), isFalse);
      expect(resembles(' ${_alice.toUpperCase()} ', _alice), isFalse);

      // One character short at either end is not one.
      expect(resembles(_copyOf(_alice, lead: 3), _alice), isFalse);
      expect(resembles(_copyOf(_alice, tail: 3), _alice), isFalse);
      // A longer match is still one.
      expect(resembles(_copyOf(_alice, lead: 9, tail: 9), _alice), isTrue);
      // And the lengths can be asked for.
      expect(
        resembles(_copyOf(_alice), _alice, lead: 6, tail: 6),
        isFalse,
      );
      expect(
        resembles(_copyOf(_alice, lead: 6, tail: 6), _alice, lead: 6, tail: 6),
        isTrue,
      );
      // Too short to have two ends.
      expect(resembles('z1qqqq', 'z1qqqp'), isFalse);
    });

    test('names the contact a typed address copies, and where', () async {
      final Contact alice = await store.add(name: 'Alice', address: _alice);
      await store.add(name: 'Bob', address: _bob);
      final String copy = _copyOf(_alice);

      final LookAlike found = store.lookAlike(copy)!;
      expect(found.address, _alice);
      expect(found.known.kind, KnownAddressKind.contact);
      expect(found.known.contact, alice);
      // The middle and nothing else: the ends are what was matched.
      expect(found.differing, isNotEmpty);
      expect(found.differing.first, greaterThanOrEqualTo(2 + kLookAlikeLead));
      expect(
        found.differing.last,
        lessThan(_alice.length - kLookAlikeTail),
      );
      for (int i = 0; i < _alice.length; i++) {
        expect(found.differing.contains(i), copy[i] != _alice[i], reason: '$i');
      }
    });

    test('finds a copy of an own address and of a past recipient', () async {
      final LookAlike own = store.lookAlike(
        _copyOf(_meToo),
        ownAddresses: <String>[_me, _meToo],
      )!;
      expect(own.address, _meToo);
      expect(own.known.kind, KnownAddressKind.own);
      expect(own.known.contact, isNull);
      // Not without being told which addresses are the wallet's.
      expect(store.lookAlike(_copyOf(_meToo)), isNull);

      // Sent to from another of the wallet's addresses.
      await store.noteSent(_meToo, _carol);
      final LookAlike past = store.lookAlike(_copyOf(_carol))!;
      expect(past.address, _carol);
      expect(past.known.kind, KnownAddressKind.recipient);
    });

    test('says contact before own before recipient', () {
      final Contact alice = Contact(
        name: 'Alice',
        address: _alice,
        added: DateTime(2026),
      );
      final LookAlike found = findLookAlike(_copyOf(_alice), <KnownAddress>[
        KnownAddress(_alice, KnownAddressKind.recipient),
        KnownAddress(_alice, KnownAddressKind.own),
        KnownAddress(_alice, KnownAddressKind.contact, contact: alice),
      ])!;
      expect(found.known.kind, KnownAddressKind.contact);
      expect(found.known.contact, alice);
    });

    test('is silent for the address itself', () async {
      await store.add(name: 'Alice', address: _alice);
      await store.noteSent(_me, _carol);

      expect(store.lookAlike(_alice), isNull);
      expect(store.lookAlike(' ${_alice.toUpperCase()} '), isNull);
      expect(store.lookAlike(_carol), isNull);
      expect(store.lookAlike(_me, ownAddresses: <String>[_me]), isNull);
    });

    test('is silent for an unrelated address and an empty book', () async {
      expect(store.lookAlike(_copyOf(_alice)), isNull);

      await store.add(name: 'Alice', address: _alice);
      // Real addresses that share z1q and little else.
      expect(store.lookAlike(_bob), isNull);
      expect(
        store.lookAlike('z1qxemdeddedxplasmaxxxxxxxxxxxxxxxxsctrp'),
        isNull,
      );
      expect(store.lookAlike(''), isNull);
      expect(store.lookAlike('z1'), isNull);
    });

    test('is silent for a known address that resembles another', () async {
      // The person saved both, or has paid both: neither is a surprise.
      final String twin = _copyOf(_alice);
      await store.add(name: 'Alice', address: _alice);
      expect(
        findLookAlike(twin, <KnownAddress>[
          ...store.known(),
          KnownAddress(twin, KnownAddressKind.recipient),
        ]),
        isNull,
      );
    });
  });

  group('kept on disk', () {
    late Directory dir;

    // Whatever a test opens lands in a folder of its own, never in the
    // wallet's.
    setUp(() {
      dir = Directory.systemTemp.createTempSync('syrius_contacts_');
      Hive.init(dir.path);
      ContactsStore.resetInstance();
    });

    tearDown(() async {
      await Hive.close();
      ContactsStore.resetInstance();
      dir.deleteSync(recursive: true);
    });

    /// Closes every box and makes a new store, which is what quitting and
    /// starting the wallet does.
    Future<ContactsStore> restart() async {
      await Hive.close();
      final ContactsStore next = ContactsStore(clock: _clock());
      await next.open();
      return next;
    }

    test('a refused opening stays distinct from an empty saved book', () async {
      await store.add(name: 'Alice', address: _alice);
      final Directory obstacle = Directory('${dir.path}/contacts_box.hive')
        ..createSync();
      await expectLater(store.open(), throwsA(isA<Object>()));
      expect(store.readFailed, isTrue);
      expect(store.isPersistent, isFalse);
      expect(store.byAddress(_alice)?.name, 'Alice');
      obstacle.deleteSync();
      await store.open();
      expect(store.readFailed, isFalse);
      expect(store.isPersistent, isTrue);
      expect((await restart()).byAddress(_alice)?.name, 'Alice');
    });

    test('contacts and recipients are there after a restart', () async {
      await store.open();
      expect(store.isPersistent, isTrue);
      final Contact alice = await store.add(
        name: 'Alice',
        address: _alice,
        note: 'rent',
      );
      await store.add(name: 'Bob', address: _bob);
      await store.add(name: 'Carol', address: _carol);
      await store.rename(_bob, 'Robert');
      await store.remove(_carol);
      await store.noteSent(_me, _bob);
      await store.noteSent(_me, _alice);
      await store.noteSent(_meToo, _carol);
      final List<RecentRecipient> sent = store.recent(_me);

      final ContactsStore next = await restart();
      expect(next.contacts, <Contact>[
        alice,
        Contact(name: 'Robert', address: _bob, added: next.contacts[1].added),
      ]);
      expect(next.recent(_me), sent);
      expect(next.recent(_meToo).single.address, _carol);
      expect(next.isFirstTime(_me, _alice), isFalse);
      expect(next.lookAlike(_copyOf(_alice))!.known.contact, alice);
    });

    test('what was added before the box opened is written to it', () async {
      await store.open();
      await store.add(name: 'Alice', address: _alice);
      await store.noteSent(_me, _alice);
      await Hive.close();

      // Before unlock: no box yet, and the store works all the same.
      final ContactsStore early = ContactsStore(clock: _clock());
      await early.add(name: 'Bob', address: _bob);
      // The box has this name already, for another address.
      await early.add(name: 'alice', address: _carol);
      await early.noteSent(_me, _bob);
      expect(early.isPersistent, isFalse);

      await early.open();
      expect(
        early.contacts.map((Contact c) => c.name),
        <String>['Alice', 'Bob'],
      );
      expect(
        early.recent(_me).map((RecentRecipient r) => r.address),
        <String>[_bob, _alice],
      );

      final ContactsStore next = await restart();
      expect(
        next.contacts.map((Contact c) => c.name),
        <String>['Alice', 'Bob'],
      );
      expect(
        next.recent(_me).map((RecentRecipient r) => r.address),
        <String>[_bob, _alice],
      );
    });

    test('the instance is one store, over the box once it is open', () async {
      expect(ContactsStore.instance, same(ContactsStore.instance));
      expect(ContactsStore.instance.isPersistent, isFalse);

      await ContactsStore.instance.open();
      await ContactsStore.instance.add(name: 'Alice', address: _alice);
      ContactsStore.resetInstance();
      expect(ContactsStore.instance.isPersistent, isTrue);
      expect(ContactsStore.instance.byAddress(_alice)!.name, 'Alice');
    });

    test('the boxes closed under it, it goes on in memory', () async {
      await store.open();
      await store.add(name: 'Alice', address: _alice);
      await Hive.close();

      expect(store.isPersistent, isFalse);
      await store.add(name: 'Bob', address: _bob);
      await store.noteSent(_me, _bob);
      expect(store.contacts, hasLength(2));

      await store.open();
      expect(store.isPersistent, isTrue);
      expect(
        (await restart()).contacts.map((Contact c) => c.name),
        <String>['Alice', 'Bob'],
      );
    });

    test('a damaged entry reads as none', () async {
      final Box<dynamic> box = await Hive.openBox<dynamic>(kContactsBox);
      await box.put('contacts', '{not json');
      await box.put('recent:$_me', 42);
      await box.put('recent:$_meToo', '[["$_alice", "then"], 7, ["$_bob", 5]]');

      await store.open();
      expect(store.contacts, isEmpty);
      expect(store.recent(_me), isEmpty);
      expect(store.recent(_meToo).single.address, _bob);

      await box.put(
        'contacts',
        '[{"name": "Alice", "address": "$_alice"}, {"name": 3}, "x"]',
      );
      expect((await restart()).contacts.single.name, 'Alice');
    });

    test('is not one of the boxes "Delete cache" deletes', () async {
      expect(kCacheBoxesToBeDeleted, isNot(contains(kContactsBox)));

      await store.open();
      await store.add(name: 'Alice', address: _alice);
      // What `SplashScreen._deleteCache` does.
      await Hive.close();
      for (final String name in kCacheBoxesToBeDeleted) {
        await Hive.deleteBoxFromDisk(name);
      }
      await store.open();
      expect(store.byAddress(_alice)!.name, 'Alice');
    });
  });
}
