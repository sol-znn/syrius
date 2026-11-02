/// The address book, and the addresses each account has sent to.
///
/// Send offers both, and checks a recipient against both before it lets the
/// transfer go: address poisoning works by leaving a dust transfer from an
/// address whose ends match one the person uses, and waiting for it to be
/// copied out of the history in place of the real one. People check the ends
/// of a `z1` address and nothing between.
///
/// Neither list is secret and neither belongs to one wallet file: a friend's
/// address is the same from any of them. So this is one plain box, as the
/// extension keeps one plain key (`services/utils/storage.js`), and not the
/// encrypted per-wallet storage the swaps have.
///
/// The box is not in `kCacheBoxesToBeDeleted`, and must stay out of it: a
/// cache is what can be fetched again, and a name given to an address
/// cannot.
///
/// No text for a person is made here. A refusal is a [ContactError], and the
/// screen that shows it chooses the words.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

/// The box the address book is kept in. Named here and not in
/// `constants.dart` so that nothing can add it to a list by habit.
const String kContactsBox = 'contacts_box';

/// The longest name, as in the extension: a name is a label beside an
/// address, in a column that does not grow.
const int kContactNameMaxLength = 32;

/// How many recipients Send offers.
const int kRecentRecipientsShown = 5;

/// How many recipients are remembered for each sending address. Five are
/// shown; the rest are what "first time" and "looks like" are judged
/// against.
const int kRecentRecipientsKept = 300;

/// The characters after `z1` that a look-alike shares with the address it
/// copies.
///
/// Four and four is what MetaMask blocks on, and the rule the research names
/// (`docs/research/qol-ideas.md`, idea 4). A longer match would let through
/// the copy that matched only four, which is the cheaper one to grind and so
/// the commoner.
const int kLookAlikeLead = 4;

/// The characters at the end that a look-alike shares.
const int kLookAlikeTail = 4;

const String _contactsKey = 'contacts';
const String _recentKeyPrefix = 'recent:';
const int _hrpLength = 2;

/// Why the address book refused.
enum ContactError {
  /// Not a `z1` address.
  invalidAddress,

  /// Nothing left of the name once trimmed.
  emptyName,

  /// Longer than [kContactNameMaxLength].
  nameTooLong,

  /// Another contact has the name, in any case.
  nameTaken,

  /// The address is already a contact.
  addressTaken,

  /// No contact has that address.
  notFound,

  /// The captured editor or original storage attachment left before admission.
  sourceChanged,
}

/// A refusal of the address book, for a screen to put into words.
class ContactsException implements Exception {
  /// Creates the refusal.
  const ContactsException(this.error);

  /// What was wrong.
  final ContactError error;

  @override
  String toString() => 'ContactsException(${error.name})';
}

/// The original persistence attempt, retained independently of any editor.
class ContactsWriteOutcome {
  /// A null write denotes a refused or in-memory-only operation.
  const ContactsWriteOutcome({
    required this.key,
    required this.committed,
    this.write,
    this.error,
    this.stackTrace,
  });

  /// The original storage key.
  final String key;

  /// Whether the original write completed successfully.
  final bool committed;

  /// The identical backend Future, when persistence was admitted.
  final Future<void>? write;

  /// The unchanged original refusal or backend error.
  final Object? error;

  /// Its original trace.
  final StackTrace? stackTrace;
}

class _ContactsLane {
  Future<void> tail = Future<void>.value();
  final List<ContactsWriteOutcome> outcomes = <ContactsWriteOutcome>[];
  Map<String, Contact>? committedContacts;
  bool contactsComplete = true;
  int pending = 0;
}

/// A name for an address.
@immutable
class Contact {
  /// Creates a contact. [ContactsStore.add] is what checks one.
  const Contact({
    required this.name,
    required this.address,
    required this.added,
    this.note,
  });

  /// Reads a stored contact, or null when the entry is not one.
  static Contact? fromJson(Object? json) {
    if (json is! Map) return null;
    final Object? name = json['name'];
    final Object? address = json['address'];
    final Object? note = json['note'];
    final Object? added = json['added'];
    if (name is! String || address is! String) return null;
    return Contact(
      name: name,
      address: address,
      note: note is String && note.isNotEmpty ? note : null,
      added: DateTime.fromMillisecondsSinceEpoch(added is int ? added : 0),
    );
  }

  /// The name, trimmed.
  final String name;

  /// The `z1` address, as the SDK writes it.
  final String address;

  /// Anything the person wanted to remember about it.
  final String? note;

  /// When it was added.
  final DateTime added;

  /// The stored form.
  Map<String, dynamic> toJson() => <String, dynamic>{
    'name': name,
    'address': address,
    if (note != null) 'note': note,
    'added': added.millisecondsSinceEpoch,
  };

  @override
  bool operator ==(Object other) =>
      other is Contact &&
      other.name == name &&
      other.address == address &&
      other.note == note &&
      other.added == added;

  @override
  int get hashCode => Object.hash(name, address, note, added);

  @override
  String toString() => 'Contact($name, $address)';
}

/// An address that was sent to, and when last.
@immutable
class RecentRecipient {
  /// Creates the entry.
  const RecentRecipient(this.address, this.at);

  /// The `z1` address.
  final String address;

  /// The last send to it.
  final DateTime at;

  @override
  bool operator ==(Object other) =>
      other is RecentRecipient && other.address == address && other.at == at;

  @override
  int get hashCode => Object.hash(address, at);

  @override
  String toString() => 'RecentRecipient($address, $at)';
}

/// What a known address is to the person.
///
/// In the order a look-alike is reported: a copy of a contact is named by
/// the contact, which says more than "one of yours" or "sent to before".
enum KnownAddressKind {
  /// In the address book.
  contact,

  /// One of the wallet's own.
  own,

  /// Sent to before.
  recipient,
}

/// An address the person has reason to trust.
@immutable
class KnownAddress {
  /// Creates the entry.
  const KnownAddress(this.address, this.kind, {this.contact});

  /// The `z1` address.
  final String address;

  /// Why it is known.
  final KnownAddressKind kind;

  /// The contact, when [kind] is [KnownAddressKind.contact].
  final Contact? contact;
}

/// A known address that the typed one resembles and is not.
@immutable
class LookAlike {
  /// Creates the finding.
  const LookAlike({required this.known, required this.differing});

  /// The address that was probably meant.
  final KnownAddress known;

  /// Where the two differ, as indexes into either address, ascending. For
  /// drawing both with the difference marked.
  final List<int> differing;

  /// The address that was probably meant.
  String get address => known.address;
}

/// The indexes at which [a] and [b] differ, ascending. Where one is longer,
/// every index past the shorter one differs.
List<int> differingPositions(String a, String b) {
  final int shared = a.length < b.length ? a.length : b.length;
  final int longest = a.length > b.length ? a.length : b.length;
  return <int>[
    for (int i = 0; i < longest; i++)
      if (i >= shared || a.codeUnitAt(i) != b.codeUnitAt(i)) i,
  ];
}

/// Whether [to] is a copy of [known] made to pass a glance: another address
/// with the same [lead] characters after `z1` and the same last [tail].
///
/// The same address is not a copy of itself.
bool resembles(
  String to,
  String known, {
  int lead = kLookAlikeLead,
  int tail = kLookAlikeTail,
}) {
  final String a = _plain(to);
  final String b = _plain(known);
  if (a == b) return false;
  // Shorter than the two ends together, the ends overlap and say nothing.
  final int ends = _hrpLength + lead + tail;
  if (a.length < ends || b.length < ends) return false;
  return a.substring(0, _hrpLength + lead) ==
          b.substring(0, _hrpLength + lead) &&
      a.substring(a.length - tail) == b.substring(b.length - tail);
}

/// The first of [known] that [to] resembles, contacts before the wallet's
/// own addresses before past recipients, or null.
///
/// Null as well when [to] is itself one of [known], whatever else it
/// resembles: the person has used that address, and a warning on an address
/// of their own book would teach them to dismiss the warning.
LookAlike? findLookAlike(
  String to,
  Iterable<KnownAddress> known, {
  int lead = kLookAlikeLead,
  int tail = kLookAlikeTail,
}) {
  final String typed = _plain(to);
  KnownAddress? found;
  for (final KnownAddress entry in known) {
    if (_plain(entry.address) == typed) return null;
    if (!resembles(typed, entry.address, lead: lead, tail: tail)) continue;
    if (found == null || entry.kind.index < found.kind.index) found = entry;
  }
  if (found == null) return null;
  return LookAlike(
    known: found,
    differing: differingPositions(typed, _plain(found.address)),
  );
}

/// Whether [to] is absent from [past], the addresses already sent to.
bool isFirstTimeAmong(String to, Iterable<String> past) {
  final String typed = _plain(to);
  return !past.any((String address) => _plain(address) == typed);
}

// bech32 is one case throughout, and a pasted address may carry a space.
String _plain(String address) => address.trim().toLowerCase();

/// The address book and the recent recipients.
///
/// Everything is held in memory and read from there, so a screen builds
/// from it without waiting. With a box attached every change is written to
/// it; without one, in a test or before [open] has been called, the store
/// works the same and forgets at exit.
class ContactsStore extends ChangeNotifier {
  /// Creates a store, over [box] when given.
  ContactsStore({Box<dynamic>? box, DateTime Function()? clock})
    : _clock = clock ?? DateTime.now {
    if (box != null) _attach(box);
  }

  static ContactsStore? _instance;

  /// The wallet's store. Made on first use, over the box if it is open by
  /// then. A store that already holds something made in memory is left to
  /// [open], which keeps it.
  // A getter and not a factory: `ContactsStore()` has to stay a new store,
  // for the tests and for anything that wants one of its own.
  // ignore: prefer_constructors_over_static_methods
  static ContactsStore get instance {
    final ContactsStore store = _instance ??= ContactsStore();
    if (store._box == null &&
        store._contacts.isEmpty &&
        store._recent.isEmpty &&
        Hive.isBoxOpen(kContactsBox)) {
      store._attach(Hive.box<dynamic>(kContactsBox));
    }
    return store;
  }

  /// Forgets [instance], so the next use makes a new one. For tests.
  @visibleForTesting
  static void resetInstance() => _instance = null;

  final DateTime Function() _clock;

  Box<dynamic>? _box;
  int _attachment = 0;
  final Object _memoryIdentity = Object();
  static final Expando<_ContactsLane> _lanes = Expando<_ContactsLane>();
  final Set<_ContactsLane> _observedLanes = <_ContactsLane>{};

  /// Captured original storage, without opening or following a replacement.
  Object get storageIdentity => isPersistent ? _box! : _memoryIdentity;

  /// Every admitted original write remains observable after an editor leaves.
  List<ContactsWriteOutcome> get writeOutcomes =>
      List<ContactsWriteOutcome>.unmodifiable(
        _observedLanes.expand((_ContactsLane lane) => lane.outcomes),
      );

  /// Remounted editors cannot issue another write while this Box is writing.
  bool get hasPendingWrite =>
      _observedLanes.any((_ContactsLane lane) => lane.pending > 0) ||
      (_lanes[storageIdentity]?.pending ?? 0) > 0;

  // By address, which is what makes a contact the same contact.
  final Map<String, Contact> _contacts = <String, Contact>{};

  // By sending address, newest first.
  final Map<String, List<RecentRecipient>> _recent =
      <String, List<RecentRecipient>>{};

  /// Whether changes are being written to disk.
  bool get isPersistent => _box?.isOpen ?? false;

  bool _readFailed = false;
  bool _contactsReadComplete = true;

  /// A failed opening cannot establish that the saved address book is empty.
  bool get readFailed => _readFailed;

  /// Convenience getters retain legacy damaged-entry behavior, while editors
  /// refuse to replace an incomplete saved book with a partial reconstruction.
  bool get contactsReadComplete => _contactsReadComplete;

  /// Opens the box and reads it. Safe to call again, and after the boxes
  /// were closed under the store, as "Delete cache" closes them.
  ///
  /// Whatever was added before this is kept and written, except a contact
  /// whose address or name the box already has: the stored one was made
  /// first.
  Future<void> open() async {
    final bool wasFailed = _readFailed;
    try {
      await _open();
      _readFailed = false;
      if (wasFailed) notifyListeners();
    } on Object {
      _readFailed = true;
      notifyListeners();
      rethrow;
    }
  }

  Future<void> _open() async {
    if (isPersistent) return;
    final Box<dynamic> box = Hive.isBoxOpen(kContactsBox)
        ? Hive.box<dynamic>(kContactsBox)
        : await Hive.openBox<dynamic>(kContactsBox);
    final List<Contact> early = _contacts.values.toList();
    final Map<String, List<RecentRecipient>> earlyRecent =
        Map<String, List<RecentRecipient>>.of(_recent);
    _attach(box);

    bool contactsChanged = false;
    for (final Contact contact in early) {
      if (_contacts.containsKey(contact.address)) continue;
      if (_nameOwner(contact.name) != null) continue;
      _contacts[contact.address] = contact;
      contactsChanged = true;
    }
    if (contactsChanged) {
      if (!_contactsReadComplete) {
        throw const ContactsException(ContactError.sourceChanged);
      }
      await _writeContacts();
    }
    for (final MapEntry<String, List<RecentRecipient>> entry
        in earlyRecent.entries) {
      final List<RecentRecipient> stored =
          _recent[entry.key] ?? <RecentRecipient>[];
      final List<RecentRecipient> merged = _mergeRecent(entry.value, stored);
      if (listEquals(merged, stored)) continue;
      _recent[entry.key] = merged;
      await _writeRecent(entry.key);
    }
    notifyListeners();
  }

  void _attach(Box<dynamic> box) {
    _attachment++;
    _box = box;
    _contacts.clear();
    _recent.clear();
    final _ContactsLane lane = _lanes[box] ??= _ContactsLane();
    _observedLanes.add(lane);
    if (lane.pending > 0 && lane.committedContacts != null) {
      _contacts.addAll(lane.committedContacts!);
      _contactsReadComplete = lane.contactsComplete;
    } else {
      final Object? raw = box.get(_contactsKey);
      _contactsReadComplete = _completeContacts(raw);
      for (final Object? entry in _decodeList(raw)) {
        final Contact? contact = Contact.fromJson(entry);
        if (contact != null) {
          final Contact? previous = lane.committedContacts?[contact.address];
          _contacts[contact.address] = previous == contact
              ? previous!
              : contact;
        }
      }
      lane
        ..committedContacts = Map<String, Contact>.of(_contacts)
        ..contactsComplete = _contactsReadComplete;
    }
    for (final Object? key in box.keys) {
      if (key is! String || !key.startsWith(_recentKeyPrefix)) continue;
      final List<RecentRecipient> list = <RecentRecipient>[
        for (final Object? entry in _decodeList(box.get(key)))
          if (entry is List &&
              entry.length == 2 &&
              entry[0] is String &&
              entry[1] is int)
            RecentRecipient(
              entry[0] as String,
              DateTime.fromMillisecondsSinceEpoch(entry[1] as int),
            ),
      ];
      _recent[key.substring(_recentKeyPrefix.length)] = list;
    }
  }

  // A damaged entry reads as an empty one: the book is a convenience, and
  // must not be what stops the wallet from starting.
  static List<dynamic> _decodeList(Object? stored) {
    if (stored is! String) return const <dynamic>[];
    try {
      final Object? decoded = jsonDecode(stored);
      return decoded is List ? decoded : const <dynamic>[];
    } on FormatException {
      return const <dynamic>[];
    }
  }

  static bool _completeContacts(Object? stored) {
    if (stored == null) return true;
    if (stored is! String) return false;
    try {
      final Object? decoded = jsonDecode(stored);
      if (decoded is! List) return false;
      final Set<String> addresses = <String>{};
      final Set<String> names = <String>{};
      for (final Object? entry in decoded) {
        final Contact? contact = Contact.fromJson(entry);
        if (contact == null ||
            normalize(contact.address) != contact.address ||
            contact.name.trim() != contact.name ||
            contact.name.isEmpty ||
            contact.name.length > kContactNameMaxLength ||
            !addresses.add(contact.address) ||
            !names.add(contact.name.toLowerCase())) {
          return false;
        }
      }
      return true;
    } on Object {
      return false;
    }
  }

  Future<void> _writeContacts() {
    final List<Contact> early = List<Contact>.of(_contacts.values);
    return _change<void>(_contactsKey, null, (Map<String, Contact> next) {
      for (final Contact contact in early) {
        if (next.containsKey(contact.address) ||
            next.values.any(
              (Contact saved) =>
                  saved.name.toLowerCase() == contact.name.toLowerCase(),
            )) {
          continue;
        }
        next[contact.address] = contact;
      }
    });
  }

  // One entry per sending address, so that a send rewrites one account's
  // list and not every account's.
  Future<void> _writeRecent(String from) => _persistRecent(
    from,
    List<RecentRecipient>.of(_recent[from] ?? const <RecentRecipient>[]),
  );

  static List<RecentRecipient> _mergeRecent(
    List<RecentRecipient> a,
    List<RecentRecipient> b,
  ) {
    final Map<String, RecentRecipient> newest = <String, RecentRecipient>{};
    for (final RecentRecipient entry in <RecentRecipient>[...a, ...b]) {
      final RecentRecipient? seen = newest[entry.address];
      if (seen == null || entry.at.isAfter(seen.at)) {
        newest[entry.address] = entry;
      }
    }
    final List<RecentRecipient> merged = newest.values.toList()
      ..sort((RecentRecipient x, RecentRecipient y) => y.at.compareTo(x.at));
    return merged.take(kRecentRecipientsKept).toList();
  }

  /// The address as the SDK writes it, or null when it is not one.
  static String? normalize(String address) {
    try {
      final Address parsed = Address.parse(_plain(address));
      // The codec takes any prefix and any payload of the right length.
      if (parsed.hrp != Address.prefix ||
          parsed.core?.length != Address.coreSize) {
        return null;
      }
      return parsed.toString();
    } on Object {
      // The SDK and the codec under it throw several unrelated types for
      // the several ways a string is not an address.
      return null;
    }
  }

  static String _require(String address) =>
      normalize(address) ??
      (throw const ContactsException(ContactError.invalidAddress));

  static String _checkedName(String name) {
    final String trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw const ContactsException(ContactError.emptyName);
    }
    if (trimmed.length > kContactNameMaxLength) {
      throw const ContactsException(ContactError.nameTooLong);
    }
    return trimmed;
  }

  static String? _checkedNote(String? note) {
    final String trimmed = note?.trim() ?? '';
    return trimmed.isEmpty ? null : trimmed;
  }

  Contact? _nameOwner(String name) {
    final String wanted = name.toLowerCase();
    for (final Contact contact in _contacts.values) {
      if (contact.name.toLowerCase() == wanted) return contact;
    }
    return null;
  }

  /// Every contact, by name without regard to case.
  List<Contact> get contacts =>
      _contacts.values.toList()..sort((Contact a, Contact b) {
        final int byName = a.name.toLowerCase().compareTo(b.name.toLowerCase());
        return byName != 0 ? byName : a.address.compareTo(b.address);
      });

  /// The contact with [address], or null. Null for a string that is not an
  /// address: a field asks this on every keystroke.
  Contact? byAddress(String address) => _contacts[_plain(address)];

  /// The contacts whose name or address contains [query], by name. All of
  /// them for an empty query.
  List<Contact> search(String query) {
    final String wanted = _plain(query);
    if (wanted.isEmpty) return contacts;
    return contacts
        .where(
          (Contact contact) =>
              contact.name.toLowerCase().contains(wanted) ||
              contact.address.contains(wanted),
        )
        .toList();
  }

  /// Adds a contact and returns it.
  ///
  /// Throws [ContactsException]: the address is not one or is in the book
  /// already, the name is empty, too long or taken.
  Future<Contact> add({
    required String name,
    required String address,
    String? note,
    bool Function()? isCurrent,
  }) => _change<Contact>(_contactsKey, isCurrent, (Map<String, Contact> next) {
    final String checkedName = _checkedName(name);
    final String checkedAddress = _require(address);
    if (next.containsKey(checkedAddress)) {
      throw const ContactsException(ContactError.addressTaken);
    }
    if (next.values.any(
      (Contact value) => value.name.toLowerCase() == checkedName.toLowerCase(),
    )) {
      throw const ContactsException(ContactError.nameTaken);
    }
    final Contact contact = Contact(
      name: checkedName,
      address: checkedAddress,
      note: _checkedNote(note),
      // To the millisecond, which is what is stored: a contact read back
      // equals the one that was added.
      added: DateTime.fromMillisecondsSinceEpoch(
        _clock().millisecondsSinceEpoch,
      ),
    );
    next[checkedAddress] = contact;
    return contact;
  });

  /// Gives the contact with [address] another name, and returns it.
  ///
  /// Throws [ContactsException]: no such contact, or the name is empty, too
  /// long or another contact's. Its own name in another case is allowed.
  Future<Contact> rename(
    String address,
    String name, {
    Contact? expected,
    bool Function()? isCurrent,
  }) => _change<Contact>(_contactsKey, isCurrent, (Map<String, Contact> next) {
    final Contact current =
        next[_plain(address)] ??
        (throw const ContactsException(ContactError.notFound));
    if (expected != null && !identical(current, expected)) {
      throw const ContactsException(ContactError.sourceChanged);
    }
    final String checkedName = _checkedName(name);
    if (next.values.any(
      (Contact value) =>
          value.address != current.address &&
          value.name.toLowerCase() == checkedName.toLowerCase(),
    )) {
      throw const ContactsException(ContactError.nameTaken);
    }
    final Contact contact = Contact(
      name: checkedName,
      address: current.address,
      note: current.note,
      added: current.added,
    );
    next[current.address] = contact;
    return contact;
  });

  /// Replaces the note of the contact with [address]; null or blank removes
  /// it.
  ///
  /// Throws [ContactsException] when there is no such contact.
  Future<Contact> setNote(String address, String? note) =>
      _change<Contact>(_contactsKey, null, (Map<String, Contact> next) {
        final Contact current =
            next[_plain(address)] ??
            (throw const ContactsException(ContactError.notFound));
        final Contact contact = Contact(
          name: current.name,
          address: current.address,
          note: _checkedNote(note),
          added: current.added,
        );
        next[current.address] = contact;
        return contact;
      });

  /// Removes the contact with [address]. What was sent to it stays in the
  /// recent recipients: that it was sent to is still true.
  ///
  /// Throws [ContactsException] when there is no such contact.
  Future<void> remove(String address, {bool Function()? isCurrent}) =>
      _change<void>(_contactsKey, isCurrent, (Map<String, Contact> next) {
        if (next.remove(_plain(address)) == null) {
          throw const ContactsException(ContactError.notFound);
        }
      });

  Future<T> _change<T>(
    String key,
    bool Function()? sourceIsCurrent,
    T Function(Map<String, Contact>) change,
  ) {
    final Box<dynamic>? box = isPersistent ? _box : null;
    final Object identity = box ?? _memoryIdentity;
    final int attachment = _attachment;
    final _ContactsLane lane = _lanes[identity] ??= _ContactsLane();
    _observedLanes.add(lane);
    final Completer<T> completion = Completer<T>();
    bool revoked = false;
    bool current() =>
        !revoked &&
        !(revoked =
            attachment != _attachment ||
            (box != null && (!identical(box, _box) || !box.isOpen)) ||
            (sourceIsCurrent?.call() == false));
    lane.pending++;
    final Future<void> previous = lane.tail;
    final Completer<void> finished = Completer<void>();
    lane.tail = finished.future;
    unawaited(() async {
      Future<void>? write;
      try {
        await previous;
        if (!current() || !_contactsReadComplete || !lane.contactsComplete) {
          throw const ContactsException(ContactError.sourceChanged);
        }
        // Another store over the same Box may have committed while queued.
        // Keep unchanged objects so an exact editor receipt remains useful.
        final Map<String, Contact> next = <String, Contact>{};
        if (box == null) {
          next.addAll(_contacts);
        } else if (lane.committedContacts != null) {
          next.addAll(lane.committedContacts!);
        } else {
          for (final Object? entry in _decodeList(box.get(_contactsKey))) {
            final Contact? saved = Contact.fromJson(entry);
            if (saved != null) {
              final Contact? held = _contacts[saved.address];
              next[saved.address] = held == saved ? held! : saved;
            }
          }
        }
        final T result = change(next);
        if (!current()) {
          throw const ContactsException(ContactError.sourceChanged);
        }
        if (box != null) {
          write = box.put(
            key,
            jsonEncode(<Map<String, dynamic>>[
              for (final Contact contact in next.values) contact.toJson(),
            ]),
          );
          await write;
        }
        lane
          ..committedContacts = Map<String, Contact>.of(next)
          ..contactsComplete = true;
        // Admission owns the original result even after its view disappears.
        // A replaced attachment must never receive that old completion.
        if (attachment == _attachment &&
            (box == null || identical(_box, box))) {
          _contacts
            ..clear()
            ..addAll(next);
        }
        lane.outcomes.add(
          ContactsWriteOutcome(
            key: key,
            committed: true,
            write: write,
          ),
        );
        completion.complete(result);
      } on Object catch (error, trace) {
        lane.outcomes.add(
          ContactsWriteOutcome(
            key: key,
            committed: false,
            write: write,
            error: error,
            stackTrace: trace,
          ),
        );
        completion.completeError(error, trace);
      } finally {
        lane.pending--;
        finished.complete();
        // A display observer cannot replace the retained storage outcome.
        try {
          notifyListeners();
        } on Object {
          /* Original already retained. */
        }
      }
    }());
    return completion.future;
  }

  /// Records that [from] sent to [to], now.
  ///
  /// Never throws for what it is given: it is called once the transfer has
  /// gone, and a failure here would be reported as a failure of the send.
  /// A string that is not an address is not recorded.
  Future<void> noteSent(String from, String to) {
    final String? sender = normalize(from);
    final String? recipient = normalize(to);
    if (sender == null || recipient == null) return Future<void>.value();
    final DateTime now = DateTime.fromMillisecondsSinceEpoch(
      _clock().millisecondsSinceEpoch,
    );
    return _persistRecent(sender, <RecentRecipient>[
      RecentRecipient(recipient, now),
    ]);
  }

  Future<void> _persistRecent(String sender, List<RecentRecipient> accepted) {
    final Box<dynamic>? box = isPersistent ? _box : null;
    final int attachment = _attachment;
    final Object identity = box ?? _memoryIdentity;
    final _ContactsLane lane = _lanes[identity] ??= _ContactsLane();
    _observedLanes.add(lane);
    final Future<void> previous = lane.tail;
    final Completer<void> finished = Completer<void>();
    final Completer<void> completion = Completer<void>();
    lane.tail = finished.future;
    lane.pending++;
    unawaited(() async {
      Future<void>? write;
      final String key = '$_recentKeyPrefix$sender';
      try {
        await previous;
        if (attachment != _attachment ||
            (box != null && (!identical(box, _box) || !box.isOpen))) {
          throw const ContactsException(ContactError.sourceChanged);
        }
        final List<RecentRecipient> saved = box == null
            ? (_recent[sender] ?? const <RecentRecipient>[])
            : <RecentRecipient>[
                for (final Object? entry in _decodeList(box.get(key)))
                  if (entry is List &&
                      entry.length == 2 &&
                      entry[0] is String &&
                      entry[1] is int)
                    RecentRecipient(
                      entry[0] as String,
                      DateTime.fromMillisecondsSinceEpoch(entry[1] as int),
                    ),
              ];
        final List<RecentRecipient> committed = _mergeRecent(accepted, saved);
        // The accepted transfer is already a fact. Keep that fact in memory
        // even if persisting its history fails; user-authored edits above
        // publish only after a successful original write.
        if (attachment == _attachment &&
            (box == null || identical(box, _box))) {
          _recent[sender] = committed;
        }
        if (box != null) {
          write = box.put(
            key,
            jsonEncode(<List<Object>>[
              for (final RecentRecipient entry in committed)
                <Object>[entry.address, entry.at.millisecondsSinceEpoch],
            ]),
          );
          await write;
        }
        lane.outcomes.add(
          ContactsWriteOutcome(
            key: key,
            committed: true,
            write: write,
          ),
        );
        completion.complete();
      } on Object catch (error, trace) {
        lane.outcomes.add(
          ContactsWriteOutcome(
            key: key,
            committed: false,
            write: write,
            error: error,
            stackTrace: trace,
          ),
        );
        completion.completeError(error, trace);
      } finally {
        lane.pending--;
        finished.complete();
        try {
          notifyListeners();
        } on Object {
          /* Original already retained. */
        }
      }
    }());
    return completion.future;
  }

  /// The addresses [from] sent to, newest first, each once, at most
  /// [limit]. Pass [kRecentRecipientsKept] for all that are remembered.
  List<RecentRecipient> recent(
    String from, {
    int limit = kRecentRecipientsShown,
  }) =>
      (_recent[_plain(from)] ?? const <RecentRecipient>[]).take(limit).toList();

  /// When [to] was last sent to: by [from], or by any address of the wallet
  /// when [from] is not given. Null when never.
  DateTime? lastSent(String to, {String? from}) {
    final String recipient = _plain(to);
    final Iterable<List<RecentRecipient>> lists = from == null
        ? _recent.values
        : <List<RecentRecipient>>[
            _recent[_plain(from)] ?? const <RecentRecipient>[],
          ];
    DateTime? last;
    for (final List<RecentRecipient> list in lists) {
      for (final RecentRecipient entry in list) {
        if (entry.address != recipient) continue;
        if (last == null || entry.at.isAfter(last)) last = entry.at;
      }
    }
    return last;
  }

  /// Whether [from] has never sent to [to], as far as is remembered here.
  ///
  /// That is the sends made since this store existed, up to
  /// [kRecentRecipientsKept] recipients for each address. It does not read
  /// the account chain, so an address sent to by an older build, or from
  /// another machine, is a first time once more.
  bool isFirstTime(String from, String to) => isFirstTimeAmong(
    to,
    (_recent[_plain(from)] ?? const <RecentRecipient>[]).map(
      (RecentRecipient entry) => entry.address,
    ),
  );

  /// Every address there is reason to trust: the contacts, [ownAddresses],
  /// and what any address of the wallet has sent to.
  ///
  /// Recipients of every sending address, not only the selected one: the
  /// dust arrives in whichever account the attacker saw, and the address it
  /// imitates is as often one that another account pays.
  List<KnownAddress> known({
    Iterable<String> ownAddresses = const <String>[],
  }) => <KnownAddress>[
    for (final Contact contact in contacts)
      KnownAddress(contact.address, KnownAddressKind.contact, contact: contact),
    for (final String address in ownAddresses)
      KnownAddress(_plain(address), KnownAddressKind.own),
    for (final List<RecentRecipient> list in _recent.values)
      for (final RecentRecipient entry in list)
        KnownAddress(entry.address, KnownAddressKind.recipient),
  ];

  /// The known address [to] resembles and is not, or null. See
  /// [findLookAlike].
  LookAlike? lookAlike(
    String to, {
    Iterable<String> ownAddresses = const <String>[],
  }) => findLookAlike(to, known(ownAddresses: ownAddresses));
}
