import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:zenon_syrius_wallet_flutter/main.dart' as app;
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/blocs/address_owned_fetch_cubit.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/blocs/fetch_bloc/fetch_bloc.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/exceptions/exceptions.dart';
import 'package:zenon_syrius_wallet_flutter/utils/global.dart';
import 'package:zenon_syrius_wallet_flutter/utils/wallet_context_revision.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

class _Client extends Mock implements Zenon {}

class _Reader extends AddressOwnedFetchCubit<List<String>> {
  _Reader({required super.zenon});

  final List<Completer<List<String>>> replies = <Completer<List<String>>>[];
  final List<Address> requests = <Address>[];

  @override
  Future<List<String>> getData({required Address address}) {
    requests.add(address);
    final Completer<List<String>> reply = Completer<List<String>>();
    replies.add(reply);
    return reply.future;
  }

  @override
  bool accepts(List<String> data, Address address) =>
      data.every((String owner) => owner == address.toString());
}

void main() {
  late _Reader reader;
  late Zenon? previousClient;
  late String? previousSelection;
  late String? previousNode;
  late int? previousNodeChain;
  late int previousChain;
  final Address owner = emptyAddress;

  setUp(() {
    previousClient = app.zenon;
    previousSelection = kSelectedAddress;
    previousNode = kCurrentNode;
    previousNodeChain = kNodeChainId;
    previousChain = getChainIdentifier();
    app.zenon = _Client();
    kSelectedAddress = owner.toString();
    kCurrentNode = 'isolated-node';
    kNodeChainId = 321;
    setChainIdentifier(chainIdentifier: 321);
    reader = _Reader(zenon: app.zenon!);
  });

  tearDown(() async {
    await reader.close();
    app.zenon = previousClient;
    kSelectedAddress = previousSelection;
    kCurrentNode = previousNode;
    kNodeChainId = previousNodeChain;
    setChainIdentifier(chainIdentifier: previousChain);
    WalletContextRevision.invalidate();
  });

  void request() => reader.add(FetchRequestData(address: owner));
  Future<void> drain() => Future<void>.delayed(Duration.zero);

  test('only a completed matching read supplies an opaque owner', () async {
    request();
    expect(reader.readOwner, isNull);
    expect(reader.isCurrentFor(owner.toString()), isFalse);
    reader.replies.single.complete(<String>[owner.toString()]);
    await drain();
    final Object ticket = reader.readOwner!;
    expect(reader.state, isA<FetchPopulated<List<String>>>());
    expect(reader.ownsRead(ticket, owner.toString()), isTrue);
    expect(reader.ownsRead(Object(), owner.toString()), isFalse);
    expect(reader.ownsRead(ticket, 'another-address'), isFalse);
  });

  test('a proven empty answer is distinct from loading', () async {
    request();
    reader.replies.single.complete(<String>[]);
    await drain();
    expect(reader.state, const FetchPopulated<List<String>>(data: <String>[]));
    expect(reader.isCurrentFor(owner.toString()), isTrue);
  });

  for (final bool staleFailure in <bool>[false, true]) {
    test(
      'superseded ${staleFailure ? 'failure' : 'empty answer'} is ignored',
      () async {
        request();
        request();
        reader.replies.last.complete(<String>[owner.toString()]);
        await drain();
        final Object ticket = reader.readOwner!;
        if (staleFailure) {
          reader.replies.first.completeError(StateError('old read'));
        } else {
          reader.replies.first.complete(<String>[]);
        }
        await drain();
        expect(reader.ownsRead(ticket, owner.toString()), isTrue);
        expect((reader.state as FetchPopulated<List<String>>).data, <String>[
          owner.toString(),
        ]);
      },
    );
  }

  final Map<String, void Function()> changes = <String, void Function()>{
    'selection': () => kSelectedAddress = 'replacement-selection',
    'node': () => kCurrentNode = 'replacement-node',
    'node chain': () => kNodeChainId = 1,
    'chain': setChainIdentifier,
    'client': () => app.zenon = _Client(),
    'context round trip': WalletContextRevision.invalidate,
  };
  for (final MapEntry<String, void Function()> change in changes.entries) {
    test('${change.key} revokes a waiting read', () async {
      request();
      change.value();
      reader.replies.single.complete(<String>[owner.toString()]);
      await drain();
      expect(reader.state, isA<FetchInitial<List<String>>>());
      expect(reader.readOwner, isNull);
      expect(reader.isCurrentFor(owner.toString()), isFalse);
    });

    test('${change.key} revokes an already displayed answer', () async {
      request();
      reader.replies.single.complete(<String>[owner.toString()]);
      await drain();
      final Object ticket = reader.readOwner!;
      change.value();
      expect(reader.ownsRead(ticket, owner.toString()), isFalse);
    });
  }

  test(
    'a request immediately revokes the preceding completed ticket',
    () async {
      request();
      reader.replies.single.complete(<String>[owner.toString()]);
      await drain();
      final Object ticket = reader.readOwner!;
      request();
      expect(reader.state, isA<FetchInitial<List<String>>>());
      expect(reader.ownsRead(ticket, owner.toString()), isFalse);
      reader.replies.last.complete(<String>[owner.toString()]);
      await drain();
      expect(reader.ownsRead(ticket, owner.toString()), isFalse);
      expect(reader.isCurrentFor(owner.toString()), isTrue);
    },
  );

  test('foreign owner data fails without becoming an empty answer', () async {
    request();
    reader.replies.single.complete(<String>['foreign-owner']);
    await drain();
    expect(reader.state, isA<FetchFailure<List<String>>>());
    expect(reader.isCurrentFor(owner.toString()), isTrue);
  });

  test('non-Exception failures settle as failures', () async {
    request();
    reader.replies.single.completeError(StateError('read unavailable'));
    await drain();
    expect(reader.state, isA<FetchFailure<List<String>>>());
    expect(
      (reader.state as FetchFailure<List<String>>).exception,
      isA<FailureException>(),
    );
  });

  test(
    'explicit invalidation rejects late failure and later same-context reuse',
    () async {
      request();
      reader.invalidateReadContext();
      reader.replies.single.completeError(StateError('invalidated read'));
      await drain();
      expect(reader.state, isA<FetchInitial<List<String>>>());
      request();
      reader.replies.last.complete(<String>[]);
      await drain();
      expect(reader.isCurrentFor(owner.toString()), isTrue);
    },
  );

  test('close rejects a late answer without waiting for the RPC', () async {
    request();
    await reader.close();
    reader.replies.single.complete(<String>[owner.toString()]);
    await drain();
    expect(reader.readOwner, isNull);
    expect(reader.isCurrentFor(owner.toString()), isFalse);
    request();
    expect(reader.requests, hasLength(1));
  });
}
