import 'dart:async';

import 'package:hive_ce/hive_ce.dart';
import 'package:zenon_syrius_wallet_flutter/services/contacts_store.dart';
import 'package:zenon_syrius_wallet_flutter/utils/address_utils.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/settings_widgets/addresses_settings_binding.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/settings_widgets/addresses_settings_presenter.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

String fixtureAddress(int number) => Address('z', <int>[
  0,
  number ~/ 256,
  number % 256,
  ...List<int>.filled(17, 7),
]).toString();

String fixtureHash(int number) => number.toRadixString(16).padLeft(64, '0');

class PendingBoxWrite {
  PendingBoxWrite(this.key, this.value, this.commit);
  final Object key;
  final Object? value;
  final void Function() commit;
  final Completer<void> reply = Completer<void>();

  void complete() {
    commit();
    reply.complete();
  }
}

/// A finite fake, including Hive's early cache update when requested.
class MemoryContactsBox implements Box<dynamic> {
  final Map<Object, Object?> entries = <Object, Object?>{};
  final List<PendingBoxWrite> writes = <PendingBoxWrite>[];
  bool deferred = false;
  bool optimistic = false;
  bool open = true;

  @override
  bool get isOpen => open;

  @override
  Iterable<dynamic> get keys => entries.keys;

  @override
  Iterable<dynamic> get values => entries.values;

  @override
  dynamic get(dynamic key, {dynamic defaultValue}) =>
      entries[key] ?? defaultValue;

  @override
  bool containsKey(dynamic key) => entries.containsKey(key);

  @override
  Future<void> put(dynamic key, dynamic value) {
    final PendingBoxWrite write = PendingBoxWrite(
      key as Object,
      value,
      () => entries[key] = value,
    );
    writes.add(write);
    if (optimistic) entries[key] = value;
    if (!deferred) write.complete();
    return write.reply.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnsupportedError(
    'The fixture does not implement ${invocation.memberName}',
  );
}

class AddressesFixture {
  AddressesFixture() {
    contacts = ContactsStore(
      box: contactBox,
      clock: () => DateTime(2026, 10, 22),
    );
    for (int index = 0; index < members.length; index++) {
      labels[members[index]] = 'Address ${index + 1}';
      accounts[members[index]] = AddressesAccount(
        address: members[index],
        height: index == 0 ? 3 : 0,
        znn: BigInt.from(120450000000),
        qsr: BigInt.from(12000000000),
      );
    }
    blocks = List<AddressesChainBlock>.generate(
      3,
      (int index) => AddressesChainBlock(
        address: members.first,
        chain: chain,
        height: index + 1,
        hash: fixtureHash(index + 1),
        previousHash: fixtureHash(index),
        type: 2,
      ),
    );
  }

  final Object labelIdentity = Object();
  Object wallet = Object();
  Object client = Object();
  Object transport = Object();
  String path = 'fixture-wallet';
  String node = 'fixture-node';
  int revision = 0;
  int chain = 321;
  bool ready = true;
  bool visible = true;
  int viewEpoch = 0;
  final List<String> members = <String>[fixtureAddress(1), fixtureAddress(2)];
  final Map<String, String> labels = <String, String>{};
  final Map<String, AddressesAccount> accounts = <String, AddressesAccount>{};
  final MemoryContactsBox contactBox = MemoryContactsBox();
  late final ContactsStore contacts;
  late List<AddressesChainBlock> blocks;
  final List<(String, String, Completer<void>)> labelWrites =
      <(String, String, Completer<void>)>[];
  final List<String> selections = <String>[];
  bool delayLabels = false;
  Future<AddressesAccount> Function(String)? accountRead;
  Future<List<AddressesChainBlock>?> Function(String, int, int)? blockRead;
  Future<AddressesChainBlock?> Function(String)? frontierRead;
  AddressGenerationBinding? Function(bool Function())? generationCapture;

  bool Function() captureView() {
    final int epoch = viewEpoch;
    return () => visible && epoch == viewEpoch;
  }

  void leaveAndReturn() {
    viewEpoch++;
    visible = true;
  }

  AddressesSettingsBinding bind({bool Function()? sourceIsCurrent}) {
    final AddressesSettingsResources resources = AddressesSettingsResources(
      identities: () => <Object?>[wallet, client, transport, labelIdentity],
      values: () => <Object?>[path, node, revision, chain, ...members],
      ready: () => ready,
    );
    return AddressesSettingsBinding(
      identity: labelIdentity,
      members: members,
      selected: members.first,
      chainId: chain,
      contacts: contacts,
      labels: () => labels,
      ownsResources: () =>
          resources.isCurrent && (sourceIsCurrent?.call() ?? true),
      readAccount: (String address) =>
          accountRead?.call(address) ??
          Future<AddressesAccount>.value(accounts[address]!),
      readFrontier: (String address) =>
          frontierRead?.call(address) ??
          Future<AddressesChainBlock?>.value(
            blocks.isEmpty ? null : blocks.last,
          ),
      readBlocks: (String address, int start, int count) =>
          blockRead?.call(address, start, count) ??
          Future<List<AddressesChainBlock>?>.value(
            blocks.skip(start - 1).take(count).toList(),
          ),
      writeLabel: (String address, String label) {
        final Completer<void> reply = Completer<void>();
        labelWrites.add((address, label, reply));
        // An optimistic cache must not make a remounted row show this yet.
        labels[address] = label;
        if (!delayLabels) reply.complete();
        return reply.future;
      },
      publishLabel: (String address, String label) => labels[address] = label,
      writeSelection: (String address) async {},
      applySelection: (String address, bool Function() current) {
        if (current() && resources.isCurrent) selections.add(address);
      },
      generation: (bool Function() current) => generationCapture?.call(current),
    );
  }
}
