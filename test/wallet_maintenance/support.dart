import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mocktail/mocktail.dart';
import 'package:zenon_syrius_wallet_flutter/l10n/app_localizations.dart';
import 'package:zenon_syrius_wallet_flutter/l10n/l10n.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/send/send.dart';
import 'package:zenon_syrius_wallet_flutter/utils/app_theme.dart';
import 'package:zenon_syrius_wallet_flutter/utils/wallet_maintenance.dart';
import 'package:zenon_syrius_wallet_flutter/utils/wallet_maintenance_binding.dart';

class MaintenanceSender extends Mock implements SendTransactionBloc {}

class MaintenanceFixture implements WalletMaintenanceSession {
  MaintenanceFixture() {
    resources = WalletMaintenanceResources(
      originalIdentities: List<Object?>.of(identities),
      originalValues: List<Object?>.of(values),
      identities: () => identities,
      values: () => values,
      ready: () => ready,
    );
    owner = WalletMaintenanceOwner(
      capture: (WalletMaintenanceKind kind, SendTransactionBloc original) {
        capturedSender = original;
        capturedKind = kind;
        return this;
      },
    );
    drains = <WalletMaintenanceAction>[
      WalletMaintenanceAction(
        name: 'original-writer',
        run: () {
          drainCalls++;
          return writer.future;
        },
      ),
    ];
    actions = <WalletMaintenanceAction>[
      WalletMaintenanceAction(
        name: 'original-cache',
        run: () {
          firstCalls++;
          return first.future;
        },
      ),
      WalletMaintenanceAction(
        name: 'original-file',
        run: () {
          secondCalls++;
          return second.future;
        },
      ),
      WalletMaintenanceAction(
        name: 'original-cleared-state',
        run: () {
          cleared = true;
          return clearedFuture;
        },
      ),
    ];
  }

  final MaintenanceSender sender = MaintenanceSender();
  final List<Object?> identities = <Object?>[
    Object(),
    Object(),
    Object(),
    Object(),
    Object(),
  ];
  final List<Object?> values = <Object?>[
    'selected.enc',
    'fixture-node',
    321,
    'fixture-api',
  ];
  late final WalletMaintenanceResources resources;
  late final WalletMaintenanceOwner owner;
  final GlobalKey<NavigatorState> navigator = GlobalKey<NavigatorState>();
  final Completer<bool> writer = Completer<bool>();
  final Completer<Object?> first = Completer<Object?>();
  final Completer<Object?> second = Completer<Object?>();
  final Future<bool> clearedFuture = Future<bool>.value(true);
  SendTransactionBloc? capturedSender;
  WalletMaintenanceKind? capturedKind;
  WalletMaintenanceRequest? request;
  Future<WalletMaintenanceOutcome>? filmFuture;
  bool ready = true;
  bool available = true;
  bool acknowledge = true;
  bool disposed = false;
  bool cleared = false;
  int sourceEpoch = 0;
  int drainCalls = 0;
  int firstCalls = 0;
  int secondCalls = 0;
  int disposals = 0;
  MaintenanceTransition? transition;

  @override
  int revision = 7;

  @override
  int get capturedRevision => 7;

  @override
  bool get ownsResources => resources.isCurrent;

  @override
  bool get cleanupAvailable => available;

  @override
  bool get resetCleared => cleared && resources.isCurrent;

  @override
  late final List<WalletMaintenanceAction> drains;

  @override
  late final List<WalletMaintenanceAction> actions;

  @override
  WalletMaintenanceTransition? beginTransition() {
    if (transition != null) {
      return null;
    }
    revision++;
    return transition = MaintenanceTransition(this, revision);
  }

  Widget host({bool light = false, bool rtl = false, double scale = 1}) =>
      MaterialApp(
        navigatorKey: navigator,
        theme: light ? AppTheme.lightTheme : AppTheme.darkTheme,
        locale: const Locale('en'),
        localizationsDelegates: appLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (BuildContext context, Widget? child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(scale),
          ),
          child: Directionality(
            textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
            child: child!,
          ),
        ),
        home: _MaintenanceMain(source: this),
      );

  Widget film(WalletMaintenanceRequest original) {
    request = original;
    return Builder(
      builder: (BuildContext context) => Scaffold(
        body: TextButton(
          key: const Key('maintenance_original_film_done'),
          onPressed: () {
            final Future<WalletMaintenanceOutcome> originalFuture = original
                .filmDone(ModalRoute.of(context));
            filmFuture ??= originalFuture;
            expect(originalFuture, same(filmFuture));
          },
          child: const Text('Finish original film'),
        ),
      ),
    );
  }
}

class MaintenanceTransition implements WalletMaintenanceTransition {
  MaintenanceTransition(this.source, this.revision);

  final MaintenanceFixture source;

  @override
  final int revision;
  bool held = true;

  @override
  bool get isOwner => held && identical(source.transition, this);

  @override
  bool complete() {
    if (!isOwner) {
      return false;
    }
    held = false;
    source.revision++;
    return true;
  }
}

class _MaintenanceMain extends StatefulWidget {
  const _MaintenanceMain({required this.source});

  final MaintenanceFixture source;

  @override
  State<_MaintenanceMain> createState() => _MaintenanceMainState();
}

class _MaintenanceMainState extends State<_MaintenanceMain> {
  MaintenanceFixture get source => widget.source;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    source.owner.attach(
      navigator: Navigator.of(context, rootNavigator: true),
      route: ModalRoute.of(context),
      sender: source.sender,
      isCurrent: () => mounted,
    );
  }

  @override
  Widget build(BuildContext context) {
    final int epoch = source.sourceEpoch;
    return Scaffold(
      body: TextButton(
        key: const Key('maintenance_open'),
        onPressed: () => unawaited(
          openWalletMaintenance(
            context: context,
            owner: source.owner,
            kind: WalletMaintenanceKind.reset,
            sourceIsCurrent: () => mounted && epoch == source.sourceEpoch,
            splashBuilder: source.film,
          ),
        ),
        child: const Text('Reset wallet'),
      ),
    );
  }

  @override
  void dispose() {
    source.disposed = true;
    source.disposals++;
    if (source.acknowledge) {
      source.owner.beforeDispose();
      source.revision++;
      source.owner.afterDispose();
    }
    super.dispose();
  }
}

Future<void> maintenanceUntil(
  WidgetTester tester,
  bool Function() done,
) async {
  for (int frame = 0; frame < 120 && !done(); frame++) {
    await tester.pump(const Duration(milliseconds: 10));
  }
  expect(done(), isTrue, reason: 'owned route settles within 120 frames');
}

Future<VoidCallback> confirmMaintenance(
  WidgetTester tester,
  MaintenanceFixture source,
) async {
  await tester.tap(find.byKey(const Key('maintenance_open')));
  await maintenanceUntil(
    tester,
    () => find
        .byKey(const Key('reset_wallet_confirm'))
        .hitTestable()
        .evaluate()
        .isNotEmpty,
  );
  final VoidCallback confirm = tester
      .widget<OutlinedButton>(
        find.byKey(const Key('reset_wallet_confirm')),
      )
      .onPressed!;
  expect(source.capturedSender, same(source.sender));
  confirm();
  await maintenanceUntil(
    tester,
    () =>
        source.disposed &&
        find
            .byKey(const Key('maintenance_original_film_done'))
            .hitTestable()
            .evaluate()
            .isNotEmpty,
  );
  return confirm;
}
