import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:zenon_syrius_wallet_flutter/main.dart' as app;
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/send/bloc/send_transaction/send_transaction_bloc.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/sentinels_by_owner/bloc/sentinels_by_owner_bloc.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/blocs/fetch_bloc/fetch_bloc.dart';
import 'package:zenon_syrius_wallet_flutter/utils/account_block_utils.dart';
import 'package:zenon_syrius_wallet_flutter/utils/address_utils.dart';
import 'package:zenon_syrius_wallet_flutter/utils/global.dart';
import 'package:zenon_syrius_wallet_flutter/utils/wallet_context_revision.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/shell/tabs.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

import '../publication_session/support.dart';

/// Advances only a bounded widget clock, including queued sender dispatch.
Future<void> pumpSentinelUntil(
  WidgetTester tester,
  bool Function() completed, {
  required String reason,
}) async {
  for (int pump = 0; pump < 50 && !completed(); pump++) {
    await tester.pump(const Duration(milliseconds: 20));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
  }
  expect(completed(), isTrue, reason: reason);
}

/// Observes a fixture-owned boundary before pumping its original future.
Future<T> pumpSentinelFuture<T>(
  WidgetTester tester,
  Future<T> future, {
  required String reason,
}) async {
  bool completed = false;
  unawaited(
    future.then<void>(
      (T _) {
        completed = true;
      },
      onError: (Object _, StackTrace _) {
        completed = true;
      },
    ),
  );
  await pumpSentinelUntil(tester, () => completed, reason: reason);
  return future;
}

/// Observes the original outcome before any widget-clock work is advanced.
class PendingSentinelPublication {
  /// Retains the sender's same future, accepted block and failure.
  PendingSentinelPublication(this.future)
    : outcome = PublicationOutcome(future);

  /// The original owner publisher's response, never a substituted outcome.
  final Future<AccountBlockTemplate> future;

  /// Both success and error completion are observed before pumping.
  final PublicationOutcome outcome;

  /// Fails finitely if the original operation does not settle.
  Future<AccountBlockTemplate> settle(WidgetTester tester) async {
    await pumpSentinelUntil(
      tester,
      () => outcome.settled,
      reason: 'The original owner publication must settle within one second',
    );
    return future;
  }
}

class _Client extends Mock implements Zenon {}

class _Embedded extends Mock implements EmbeddedApi {}

class _Api extends Mock implements SentinelApi {}

class _Blocks extends Mock implements AccountBlockUtils {}

class _Balances extends Mock implements ZenonAddressUtils {}

/// A concrete, synthetic SDK record without any node or wallet execution.
SentinelInfo sentinelOwnerRecord({
  Address? owner,
  bool active = true,
  bool revocable = true,
  int cooldown = 3600,
}) => SentinelInfo.fromJson(<String, dynamic>{
  'owner': (owner ?? emptyAddress).toString(),
  'registrationTimestamp': 1625132800,
  'isRevocable': revocable,
  'revokeCooldown': cooldown,
  'active': active,
});

/// The real owner reader and shared sender, with all transport in memory.
class SentinelOwnerFixture {
  /// Builds synthetic account and sender subscriptions on the widget clock.
  SentinelOwnerFixture() {
    when(() => client.embedded).thenReturn(embedded);
    when(() => embedded.sentinel).thenReturn(api);
    when(() => api.getByOwner(any())).thenAnswer((Invocation call) {
      ownershipReads++;
      requestedOwners.add(
        (call.positionalArguments.single as Address).toString(),
      );
      return read();
    });
    when(api.revoke).thenReturn(AccountBlockTemplate(blockType: 1));
    when(balances.refreshBalance).thenAnswer((_) {});
    when(
      () => blocks.createAccountBlock(
        any(),
        any(),
        address: any(named: 'address'),
        waitForRequiredPlasma: any(named: 'waitForRequiredPlasma'),
        canPublish: any(named: 'canPublish'),
      ),
    ).thenAnswer((Invocation call) {
      final bool Function()? canPublish =
          call.namedArguments[#canPublish] as bool Function()?;
      if (canPublish != null && !canPublish()) {
        throw StateError('Original owner authority expired');
      }
      publications++;
      publishedFrom = (call.namedArguments[#address] as Address).toString();
      return publish(call.positionalArguments.first as AccountBlockTemplate);
    });
    app.zenon = client;
    kWalletFile = MockPublicationFile();
    kWalletInitCompleted = true;
    kWalletPath = 'isolated-sentinel-owner';
    kCurrentNode = 'isolated-node';
    kNodeChainId = 321;
    kSelectedAddress = emptyAddress.toString();
    kDefaultAddressList = <String?>[emptyAddress.toString()];
    kCurrentPage = Tabs.sentinels;
    setChainIdentifier(chainIdentifier: 321);
    reader = SentinelsByOwnerBloc(zenon: client);
    sender = SendTransactionBloc(
      accountBlockUtilsHelper: blocks,
      zenonAddressUtils: balances,
    );
  }

  final PublicationGlobals _globals = PublicationGlobals();
  final List<void Function()> _cleanups = <void Function()>[];

  /// The original mocked SDK transport.
  final Zenon client = _Client();

  /// The original embedded transport.
  final EmbeddedApi embedded = _Embedded();

  /// The mocked owner lookup and revoke encoder.
  final SentinelApi api = _Api();

  /// The only observed publication entry point.
  final AccountBlockUtils blocks = _Blocks();

  /// Balance refresh has no global service or RPC dependency.
  final ZenonAddressUtils balances = _Balances();

  /// The real completed-read and context-ticket behavior.
  late final SentinelsByOwnerBloc reader;

  /// The real shared admission and retained-result behavior.
  late final SendTransactionBloc sender;

  /// Each case controls the next fresh owner response.
  Future<SentinelInfo?> Function() read = () async => null;

  /// Each case controls the original publication's completion.
  Future<AccountBlockTemplate> Function(AccountBlockTemplate) publish =
      (AccountBlockTemplate block) async => block;

  /// Every fresh and displayed ownership lookup.
  int ownershipReads = 0;

  /// Every publication admitted after the owner guard.
  int publications = 0;

  /// The explicit originating address passed to publication.
  String? publishedFrom;

  /// All requested owner addresses, including fresh verification.
  final List<String> requestedOwners = <String>[];

  /// Completes the displayed read on the same clock as the widget interaction.
  Future<void> load(WidgetTester tester, SentinelInfo? owned) async {
    read = () async => owned;
    reader.add(FetchRequestData(address: emptyAddress));
    await pumpSentinelUntil(
      tester,
      () => reader.readOwner != null,
      reason: 'The displayed owner read must complete before interaction',
    );
    expect(reader.state, isA<FetchPopulated<List<SentinelInfo>>>());
  }

  /// Releases a controlled reply after a failed test without inventing success.
  void addCleanup(void Function() cleanup) => _cleanups.add(cleanup);

  /// Closes on the owning widget clock and always restores the process globals.
  Future<void> dispose(WidgetTester tester) async {
    try {
      for (final void Function() cleanup in _cleanups) {
        cleanup();
      }
      await pumpSentinelFuture<void>(
        tester,
        reader.close(),
        reason: 'The owned reader must close on its widget clock',
      );
      await pumpSentinelFuture<void>(
        tester,
        sender.close(),
        reason: 'The original sender must drain and close on its widget clock',
      );
    } finally {
      _globals.restore();
      WalletContextRevision.invalidate();
    }
  }
}
