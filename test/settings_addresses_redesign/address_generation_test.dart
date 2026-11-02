import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:zenon_syrius_wallet_flutter/utils/address_utils.dart';

import 'support.dart';

Future<void> _flush() async {
  for (int index = 0; index < 12; index++) {
    await Future<void>.value();
  }
}

class _GenerationFixture {
  final Object identity = Object();
  final Object originalWallet = Object();
  final List<String> members = <String>[fixtureAddress(1)];
  final List<String> calls = <String>[];
  final Completer<Object> acquisition = Completer<Object>();
  final Completer<void> label = Completer<void>();
  final Completer<int> member = Completer<int>();
  final Completer<void> release = Completer<void>();
  int revision = 0;
  int expectedRevision = 0;
  bool current = true;
  bool publish = true;

  AddressGenerationBinding bind() => AddressGenerationBinding(
    identity: identity,
    members: members,
    owns: () => current && revision == expectedRevision,
    acquire: () {
      calls.add('acquire');
      return acquisition.future;
    },
    release: () {
      calls.add('release');
      return release.future;
    },
    derive: (Object wallet, int index) async {
      expect(wallet, same(originalWallet));
      expect(index, 1);
      calls.add('derive');
      return fixtureAddress(2);
    },
    defaultLabel: (int number) => 'Address $number',
    writeLabel: (String address, String text) {
      expect(text, 'Address 2');
      calls.add('label');
      return label.future;
    },
    writeMember: (String address) {
      calls.add('member');
      return member.future;
    },
    publish: (String address, String text) {
      calls.add('publish');
      if (!current || !publish) return false;
      members.add(address);
      // Production changes membership before it synchronously invalidates.
      expectedRevision++;
      revision++;
      calls.add('invalidate');
      return true;
    },
  );
}

void main() {
  test(
    'positive membership waits for label then member and invalidates once',
    () async {
      final _GenerationFixture source = _GenerationFixture();
      final AddressGenerationBinding binding = source.bind();
      final Future<AddressGenerationOutcome> pending = binding.generate();
      expect(binding.generate(), same(pending));
      source.acquisition.complete(source.originalWallet);
      await _flush();
      expect(source.calls, <String>['acquire', 'derive', 'label']);
      expect(source.members, hasLength(1));
      source.label.complete();
      await _flush();
      expect(source.calls.last, 'member');
      expect(source.revision, 0);
      source.member.complete(1);
      await _flush();
      expect(source.calls, <String>[
        'acquire',
        'derive',
        'label',
        'member',
        'publish',
        'invalidate',
        'release',
      ]);
      expect(source.members, hasLength(2));
      expect(binding.pending, same(pending));
      source.release.complete();
      final AddressGenerationOutcome result = await pending;
      expect(result.committed, isTrue);
      expect(result.published, isTrue);
      expect(result.labelWrites.single, same(source.label.future));
      expect(result.memberWrites.single, same(source.member.future));
      expect(result.acquisition, same(source.acquisition.future));
      expect(result.release, same(source.release.future));
      expect(binding.outcomes.single, same(result));
    },
  );

  test(
    'replacement while acquiring releases only the original and never derives',
    () async {
      final _GenerationFixture source = _GenerationFixture();
      final AddressGenerationBinding binding = source.bind();
      final Future<AddressGenerationOutcome> pending = binding.generate();
      source.current = false;
      source.acquisition.complete(source.originalWallet);
      await _flush();
      expect(source.calls, <String>['acquire', 'release']);
      source.release.complete();
      final AddressGenerationOutcome result = await pending;
      expect(result.error, isA<AddressGenerationRefused>());
      expect(result.labelWrites, isEmpty);
      expect(result.committed, isFalse);
    },
  );

  test(
    'an acquisition failure is retained without releasing another owner',
    () async {
      final _GenerationFixture source = _GenerationFixture();
      final AddressGenerationBinding binding = source.bind();
      final StateError original = StateError('original acquisition');
      final Future<AddressGenerationOutcome> pending = binding.generate();
      source.acquisition.completeError(original);
      final AddressGenerationOutcome result = await pending;
      expect(result.error, same(original));
      expect(source.calls, <String>['acquire']);
      expect(result.release, isNull);
    },
  );

  test(
    'a failed label cannot append a member and retains the original error',
    () async {
      final _GenerationFixture source = _GenerationFixture();
      final AddressGenerationBinding binding = source.bind();
      final StateError original = StateError('original label write');
      final Future<AddressGenerationOutcome> pending = binding.generate();
      source.acquisition.complete(source.originalWallet);
      await _flush();
      source.label.completeError(original);
      await _flush();
      source.release.complete();
      final AddressGenerationOutcome result = await pending;
      expect(result.error, same(original));
      expect(result.labelWrites.single, same(source.label.future));
      expect(result.memberWrites, isEmpty);
      expect(source.members, hasLength(1));
      expect(source.revision, 0);
    },
  );

  test(
    'a late member commit is retained but never published into a replacement',
    () async {
      final _GenerationFixture source = _GenerationFixture();
      final AddressGenerationBinding binding = source.bind();
      final Future<AddressGenerationOutcome> pending = binding.generate();
      source.acquisition.complete(source.originalWallet);
      await _flush();
      source.label.complete();
      await _flush();
      source.current = false;
      source.member.complete(1);
      await _flush();
      source.release.complete();
      final AddressGenerationOutcome result = await pending;
      expect(result.committed, isTrue);
      expect(result.published, isFalse);
      expect(result.addresses, <String>[fixtureAddress(2)]);
      expect(source.members, hasLength(1));
      expect(source.revision, 0);
    },
  );

  test(
    'release failure does not erase a positive original member commit',
    () async {
      final _GenerationFixture source = _GenerationFixture();
      final AddressGenerationBinding binding = source.bind();
      final Future<AddressGenerationOutcome> pending = binding.generate();
      source.acquisition.complete(source.originalWallet);
      await _flush();
      source.label.complete();
      await _flush();
      source.member.complete(1);
      await _flush();
      final StateError original = StateError('original release');
      source.release.completeError(original);
      final AddressGenerationOutcome result = await pending;
      expect(result.committed, isTrue);
      expect(result.published, isTrue);
      expect(result.releaseError, same(original));
    },
  );

  test(
    'a returned wallet with a later context revision cannot resume derivation',
    () async {
      final _GenerationFixture source = _GenerationFixture();
      final Future<AddressGenerationOutcome> pending = source.bind().generate();
      source.revision += 2;
      source.acquisition.complete(source.originalWallet);
      await _flush();
      source.release.complete();
      expect((await pending).error, isA<AddressGenerationRefused>());
      expect(source.calls, <String>['acquire', 'release']);
    },
  );

  test(
    'an admitted member-write failure retains its exact uncertain Future',
    () async {
      final _GenerationFixture source = _GenerationFixture();
      final Future<AddressGenerationOutcome> pending = source.bind().generate();
      source.acquisition.complete(source.originalWallet);
      await _flush();
      source.label.complete();
      await _flush();
      final StateError original = StateError('original member storage');
      source.member.completeError(original);
      await _flush();
      source.release.complete();
      final AddressGenerationOutcome result = await pending;
      expect(result.error, same(original));
      expect(result.memberWrites.single, same(source.member.future));
      expect(result.committed, isFalse);
      expect(source.revision, 0);
    },
  );
}
