import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show PointerDeviceKind;

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mocktail/mocktail.dart';
import 'package:zenon_syrius_wallet_flutter/blocs/notifications_bloc.dart';
import 'package:zenon_syrius_wallet_flutter/l10n/app_localizations.dart';
import 'package:zenon_syrius_wallet_flutter/l10n/l10n.dart';
import 'package:zenon_syrius_wallet_flutter/main.dart' as app;
import 'package:zenon_syrius_wallet_flutter/model/database/wallet_notification.dart';
import 'package:zenon_syrius_wallet_flutter/model/new_token_data.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/create_token_stepper/create_token_stepper.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/registration_success/registration_confirmation.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/token_favorite/token_favorite.dart';
import 'package:zenon_syrius_wallet_flutter/screens/stepper_screen.dart';
import 'package:zenon_syrius_wallet_flutter/utils/app_theme.dart';
import 'package:zenon_syrius_wallet_flutter/utils/global.dart';
import 'package:zenon_syrius_wallet_flutter/utils/wallet_action_context.dart';
import 'package:zenon_syrius_wallet_flutter/utils/wallet_flight_registry.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/accelerator_widgets/accelerator_action_controller.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/accelerator_widgets/accelerator_action_stepper.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/accelerator_widgets/project_creation_stepper.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/reusable_widgets/buttons/primary_pill.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/reusable_widgets/modals/frosted_route.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/shell/rail.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/shell/tabs.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

import '../../harness/app/agent.dart';
import '../../harness/app/fixtures/seed_policy.dart';
import '../../harness/app/fixtures/seed_project_presentation.dart';
import '../../harness/app/fixtures/seed_token_presentation.dart';
import '../../harness/app/seed_project_presentation_binding.dart';
import '../../harness/app/seed_token_presentation_binding.dart';
import '../../harness/bin/ci_wallet_reopen.dart' as reopen;
import '../../harness/bin/harness.dart' as cli;
import '../../harness/home_preparation_observation.dart';
import '../../harness/seed/restored_seed_workflow.dart';
import '../../harness/seed_preparation_failure.dart';
import '../../harness/wallet_address_context.dart';
import '../accelerator_project_redesign/support.dart';
import '../create_token_redesign/support.dart';

WalletAddressContext _context({
  int count = 2, int revision = 20, int owner = 1,
}) =>
    WalletAddressContext.parse(<String, dynamic>{
      'members': List<String>.generate(count, (int i) => 'synthetic-member-$i'),
      'selected': 'synthetic-member-1', 'saved': 'synthetic-member-1',
      'revision': revision, 'owner': owner,
    });

String _hash(int value) => List<String>.filled(64, '$value').join();

final class _Session {
  final WalletAddressContext original = _context();
  WalletAddressContext current = _context();
  final List<String> started = <String>[];
  bool alive = true;
  int preparations = 0;
  Future<void> Function()? duringRecipe;
  bool wrongDerivation = false;
  bool dieDuringPreparation = false;
  bool duplicateHash = false;
  Map<String, Object?> receiptChange = <String, Object?>{};

  RestoredSeedWorkflow workflow() => RestoredSeedWorkflow(
    original: original, parentAlive: () => alive,
    observe: () async => current,
    prepareAddress: (WalletAddressContext before) async {
      expect(before.same(original), isTrue);
      preparations++;
      current = _context(count: 3,
        revision: wrongDerivation ? 22 : 21);
      if (dieDuringPreparation) alive = false;
      return current;
    },
    recipe: (String id, Future<void> Function() check) async {
      await check();
      started.add(id);
      await duringRecipe?.call();
      return <String, dynamic>{
        'ok': true, 'confirmed': true, 'recipe': id,
        'hash': _hash(duplicateHash ? 1 : started.length), ...receiptChange,
      };
    },
  );
}

class _UnprintableSeedError implements Exception {
  @override
  String toString() => throw StateError('synthetic-private-value');
}

SeedProjectPresentation _projectPresentation({
  required Future<Object?> route,
  bool Function()? current,
  bool Function(String)? submitted,
  Future<void> Function(void Function())? tap,
  Duration timeout = const Duration(seconds: 5),
}) => SeedProjectPresentation(
  originalCurrent: current ?? () => true,
  submittedCurrent: submitted ?? (String hash) => hash == _hash(9),
  tapOriginalExit: tap ?? (void Function() admission) async => admission(),
  originalRouteCompleted: route, closeTimeout: timeout,
);




SeedTokenPresentation _tokenPresentation({
  required Future<Object?> route,
  bool Function()? current,
  bool Function(String)? submitted,
  Future<void> Function(void Function())? tap,
  Duration timeout = const Duration(seconds: 5),
}) => SeedTokenPresentation(
  originalCurrent: current ?? () => true,
  submittedCurrent: submitted ?? (String hash) => hash == _hash(9),
  tapOriginalExit: tap ?? (void Function() admission) async => admission(),
  originalRouteCompleted: route, closeTimeout: timeout,
);




// Only decoration loading is held. The actual Project view, route, original
// source controller and pointer input remain in use; artwork is not qualified.
class _ProjectFilmBundle extends CachingAssetBundle {
  final Completer<ByteData> _film = Completer<ByteData>();

  @override
  Future<ByteData> load(String key) =>
      key.startsWith('assets/lottie/ic_anim_zts')
          ? _film.future : rootBundle.load(key);
}

Future<void> _projectFrame(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
  await tester.pump();
}

Future<void> _projectClose(WidgetTester tester, Future<void> original) async {
  bool settled = false;
  Object? error;
  StackTrace? trace;
  unawaited(original.then((_) { settled = true; },
    onError: (Object value, StackTrace stack) {
      error = value;
      trace = stack;
      settled = true;
    },
  ));
  for (int frame = 0; frame < 80 && !settled; frame++) {
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump(const Duration(milliseconds: 40));
  }
  expect(settled, isTrue);
  if (error != null) Error.throwWithStackTrace(error!, trace!);
}

Future<(SeedProjectPresentation, ModalRoute<dynamic>)> _submittedProject(
  WidgetTester tester, ActionSource source, VoidCallback exited,
) async {
  ModalRoute<dynamic>? originalRoute;
  await tester.pumpWidget(DefaultAssetBundle(
    bundle: _ProjectFilmBundle(),
    child: MaterialApp(
      locale: const Locale('en'), theme: AppTheme.darkTheme,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: appLocalizationsDelegates,
      home: Scaffold(body: Builder(builder: (BuildContext context) => Center(
        child: OutlinedButton(
          key: const Key('project_original_home'),
          onPressed: () {
            unawaited(showFrostedDialog<void>(context: context,
              builder: (BuildContext dialog) {
                originalRoute = ModalRoute.of(dialog);
                return Center(child: SizedBox(width: 1000, height: 700,
                  child: Material(child: ProjectCreationStepper(
                    source: source,
                  )),
                ));
              },
            ));
          },
          child: const Text('Open original Project'),
        ),
      ))),
    ),
  ));
  await tester.tap(find.byKey(const Key('project_original_home')));
  await _projectFrame(tester);
  expect(originalRoute, isA<FrostedDialogRoute<void>>());
  expect(find.byKey(const Key('project_original_home')).hitTestable(),
      findsNothing);
  Future<void> continueOriginal() async {
    final Finder button = find.widgetWithText(PrimaryPill, 'Continue');
    await tester.ensureVisible(button);
    await tester.tap(button);
    await _projectFrame(tester);
  }
  await continueOriginal();
  final Finder fields = find.byType(TextField);
  expect(fields, findsNWidgets(5));
  const List<String> values = <String>[
    'Synthetic project', 'Synthetic project description',
    'https://example.test/project', '1', '0',
  ];
  for (int index = 0; index < values.length; index++) {
    await tester.ensureVisible(fields.at(index));
    await tester.enterText(fields.at(index), values[index]);
  }
  await _projectFrame(tester);
  await continueOriginal();
  final Finder submit = find.widgetWithText(PrimaryPill, 'Submit');
  await tester.ensureVisible(submit);
  final SeedProjectPresentation presentation = captureSeedProjectPresentation(
    tester.element(submit),
    tapOriginal: (Element element, VoidCallback admission) async {
      admission();
      final Finder button = find.byElementPredicate(
        (Element candidate) => identical(candidate, element),
      );
      expect(button.hitTestable(), findsOneWidget);
      final Offset point = tester.getCenter(button);
      final TestGesture pointer = await tester.createGesture(
        kind: PointerDeviceKind.mouse,
      );
      await pointer.addPointer(location: point);
      admission();
      await pointer.down(point);
      admission();
      await pointer.up();
      await pointer.removePointer();
      exited();
    },
  );
  expect(presentation.requireCaptured, returnsNormally);
  expect(source.publications, 0);
  await tester.tap(submit);
  await _projectFrame(tester);
  expect(source.publications, 1);
  expect(source.confirmedReads, isEmpty);
  final AcceleratorActionPresentationSource original = tester
      .state<State<AcceleratorActionStepper>>(
        find.byType(AcceleratorActionStepper),
      ) as AcceleratorActionPresentationSource;
  expect(original.actionPresentation.submittedWith(listHash(901)), isTrue);
  expect(find.byKey(const Key('acc_stepper_leave')).hitTestable(),
      findsOneWidget);
  return (presentation, originalRoute!);
}

// Inert replies exercise the original CLI call sequence without a process,
// filesystem, wallet, network, clock override or added navigation operation.
final class _HomeReplies extends cli.Instance {
  _HomeReplies(this._replies) : super('synthetic-home');

  final List<Object> _replies;
  final List<Map<String, Object?>> _commands = <Map<String, Object?>>[];

  @override
  Future<Map<String, dynamic>> send(Map<String, Object?> command, {
    Duration timeout = const Duration(seconds: 120),
  }) async {
    _commands.add(Map<String, Object?>.unmodifiable(command));
    final Object reply = _replies[_commands.length - 1];
    if (reply is Map<String, dynamic>) return reply;
    if (reply is Exception) throw reply;
    throw StateError('synthetic reply type');
  }
}

Map<String, dynamic> _homeState({String target = 'home'}) =>
    <String, dynamic>{
      'ok': true, 'booted': true, 'walletUnlocked': true,
      'walletInitCompleted': true, 'tab': target, 'tabs': <String>[target],
      'private': _UnprintableSeedError(),
    };

List<Object> _homeReplies({String target = 'home', bool expanded = false}) =>
    <Object>[
      _homeState(target: target), _homeState(target: target),
      <String, dynamic>{'ok': true}, _homeState(target: target),
      _homeState(target: target), <String, dynamic>{'ok': true},
      <String, dynamic>{'ok': expanded},
      if (expanded) ...<Map<String, dynamic>>[
        <String, dynamic>{'ok': true}, <String, dynamic>{'ok': true},
      ],
      _homeState(target: target),
    ];

List<Map<String, Object?>> _homeCommands({
  String target = 'home', bool expanded = false,
}) => <Map<String, Object?>>[
  <String, Object?>{'cmd': 'state'}, <String, Object?>{'cmd': 'state'},
  <String, Object?>{'cmd': 'tap', 'tab': target},
  <String, Object?>{'cmd': 'state'}, <String, Object?>{'cmd': 'state'},
  <String, Object?>{'cmd': 'wait', 'key': 'rail_toggle', 'timeoutMs': 0},
  <String, Object?>{
    'cmd': 'wait', 'key': 'rail_label_dashboard', 'timeoutMs': 0,
  },
  if (expanded) ...<Map<String, Object?>>[
    <String, Object?>{'cmd': 'tap', 'key': 'rail_toggle'},
    <String, Object?>{
      'cmd': 'wait', 'key': 'rail_label_dashboard', 'gone': true,
    },
  ],
  <String, Object?>{'cmd': 'state'},
];

cli.SeedOperationTrace _homeTrace({String recipe = 'deposit'}) =>
    cli.SeedOperationTrace(recipe)
      ..at(cli.SeedOperationAction.home, cli.SeedOperationStep.navigation);


class _TokenIssueBloc extends MockBloc<IssueTokenEvent, IssueTokenState>
    implements IssueTokenBloc {}

class _TokenFavorites extends Mock implements FavoriteTokensRepository {}

class _TokenOwner extends Mock implements WalletActionContext {}

/// Real Token listener, receipt, StepperScreen and route; all I/O is inert.
class _TokenRoute {
  _TokenRoute() {
    when(() => owner.ownerAddress).thenReturn(emptyAddress.toString());
    when(() => owner.isCurrent).thenAnswer((_) => ownerCurrent);
    registry = WalletFlightRegistry(
      currentChainId: () => 321,
      lookup: (_, _) async { confirmationReads++; return true; },
    );
    confirmation = newConfirmation();
    displayedConfirmation = confirmation;
    displayedFixture = fixture;
    when(() => bloc.state).thenReturn(const IssueTokenInitial());
    when(() => bloc.stream).thenAnswer((_) => states.stream);
    when(() => bloc.add(any())).thenAnswer((_) { issues++; });
    when(() => favorites.add(znnZts)).thenAnswer((_) async {
      favoritesSaved++;
    });
  }

  final WalletNotification? previousNotification = kLastNotification;
  final WalletNotification? previousDismissed = kLastDismissedNotification;
  final TokenCreateFixture fixture = TokenCreateFixture();
  final _TokenIssueBloc bloc = _TokenIssueBloc();
  final _TokenFavorites favorites = _TokenFavorites();
  final _TokenOwner owner = _TokenOwner();
  final StreamController<IssueTokenState> states =
      StreamController<IssueTokenState>.broadcast();
  final RailCollapse collapse = RailCollapse();
  final ValueNotifier<int> revision = ValueNotifier<int>(0);
  final List<Tabs> opened = <Tabs>[];
  final List<RegistrationConfirmation> replacements =
      <RegistrationConfirmation>[];
  final List<TokenCreateFixture> replacementFixtures = <TokenCreateFixture>[];
  late final WalletFlightRegistry registry;
  late final RegistrationConfirmation confirmation;
  late RegistrationConfirmation displayedConfirmation;
  late TokenCreateFixture displayedFixture;
  ModalRoute<dynamic>? route;
  Object viewKey = const ValueKey<String>('original_token_view');
  bool ownerCurrent = true;
  int issues = 0;
  int favoritesSaved = 0;
  int confirmationReads = 0;
  int exits = 0;
  int notificationCalls = 0;

  late final NotificationsBloc notifications = NotificationsBloc(
    openStore: () {
      notificationCalls++;
      throw StateError('Unexpected store');
    },
    ownsStore: (_) => false,
    desktopNotificationsEnabled: false,
    showDesktop: (_, _) async {
      notificationCalls++; throw StateError('Unexpected native notification');
    },
  );

  RegistrationConfirmation newConfirmation() => RegistrationConfirmation(
    context: owner, chainId: 321,
    walletAddresses: <String>[emptyAddress.toString()], registry: registry,
  );

  Future<void> mount(WidgetTester tester) async {
    expect(app.sl.isRegistered<NotificationsBloc>(), isFalse);
    app.sl.registerSingleton<NotificationsBloc>(notifications);
    kLastNotification = null;
    kLastDismissedNotification = null;
    await tester.pumpWidget(DefaultAssetBundle(
      bundle: _ProjectFilmBundle(),
      child: RepositoryProvider<FavoriteTokensRepository>.value(
        value: favorites,
        child: BlocProvider<IssueTokenBloc>.value(
          value: bloc,
          child: MaterialApp(
            locale: const Locale('en'), theme: AppTheme.darkTheme,
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: appLocalizationsDelegates,
            home: Scaffold(body: Row(children: <Widget>[
              ShellRail(collapse: collapse, selected: Tabs.tokens,
                locked: false, onSelected: opened.add),
              Expanded(child: Builder(builder: (BuildContext context) =>
                Center(child: OutlinedButton(
                  key: const Key('open_original_token'),
                  onPressed: () {
                    Navigator.push<void>(context,
                      MaterialPageRoute<void>(builder: (BuildContext screen) {
                        route = ModalRoute.of(screen);
                        return ValueListenableBuilder<int>(
                          valueListenable: revision,
                          builder: (_, _, _) => StepperScreen(
                            onStepperNotificationSeeMorePressed: () {},
                            stepper: CreateTokenStepperView(
                              key: ValueKey<Object>(viewKey),
                              preflight: displayedFixture.preflight,
                              confirmation: displayedConfirmation,
                            ),
                          ),
                        );
                      }),
                    );
                  },
                  child: const Text('Open original Token'),
                )),
              )),
            ])),
          ),
        ),
      ),
    ));
    await _projectFrame(tester);
    await tester.tap(find.byKey(const Key('open_original_token')));
    await _projectFrame(tester);
    expect(route, isA<MaterialPageRoute<void>>());
    expect(find.byType(StepperScreen), findsOneWidget);
  }

  Future<SeedTokenPresentation> submit(WidgetTester tester) async {
    await tester.enterText(find.byKey(const Key('token_name_field')),
        'SyntheticToken');
    await tester.enterText(find.byKey(const Key('token_symbol_field')), 'SYN');
    await tester.pump();
    Future<void> next(String step) async {
      final Finder control = find.descendant(
        of: find.byKey(Key('token_create_$step')),
        matching: find.byType(OutlinedButton),
      );
      await tester.ensureVisible(control);
      await tester.tap(control);
      await _projectFrame(tester);
    }
    await next('details');
    await tester.enterText(find.byKey(const Key('token_total_supply_field')),
        '10');
    await tester.pump();
    await next('supply');
    await next('options');
    final Finder control = find.descendant(
      of: find.byKey(const Key('token_create_issue')),
      matching: find.byType(OutlinedButton),
    );
    await tester.ensureVisible(control);
    final SeedTokenPresentation original = captureSeedTokenPresentation(
      tester.element(control), expectedOwner: emptyAddress.toString(),
      tapOriginal: (Element element, VoidCallback admission) async {
        admission();
        final Finder exact = find.byElementPredicate(
          (Element observed) => identical(observed, element),
        );
        expect(exact.hitTestable(), findsOneWidget);
        admission();
        exits++;
        await tester.tap(exact);
      },
    );
    expect(issues, 0);
    expect(confirmation.publication, isNull);
    original.requireCaptured();
    await tester.tap(control);
    await _projectFrame(tester);
    expect(issues, 1);
    final AccountBlockTemplate accepted = AccountBlockTemplate(
      blockType: BlockTypeEnum.userSend.index,
    )..address = emptyAddress
      ..chainIdentifier = 321
      ..hash = Hash.parse(_hash(9));
    states.add(IssueTokenDone(accountBlock: accepted,
        newTokenStandard: znnZts));
    await _projectFrame(tester);
    expect(confirmation.isConfirmed, isTrue);
    expect(find.byKey(const Key('token_registration_confirmed')),
        findsOneWidget);
    expect(favoritesSaved, 1);
    expect(exits, 0);
    return original;
  }

  Future<void> dispose(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
    if (app.sl.isRegistered<NotificationsBloc>() &&
        identical(app.sl<NotificationsBloc>(), notifications)) {
      await app.sl.unregister<NotificationsBloc>(instance: notifications);
    }
    notifications.dispose();
    kLastNotification = previousNotification;
    kLastDismissedNotification = previousDismissed;
    await states.close();
    await bloc.close();
    for (final RegistrationConfirmation value in replacements) {
      value.dispose();
    }
    confirmation.dispose();
    registry.dispose();
    for (final TokenCreateFixture value in replacementFixtures) {
      value.dispose();
    }
    fixture.dispose();
    collapse.dispose();
    revision.dispose();
    expect(notificationCalls, 0);
  }
}

void main() {
  setUpAll(() {
    registerFallbackValue(IssueTokenRequested(
      tokenData: NewTokenData.initial(address: emptyAddress.toString()),
    ));
  });
  test('Home observations copy finite flags and freeze private input safely',
      () {
    final HomePreparationTrace trace = HomePreparationTrace();
    final Map<String, dynamic> state = _homeState()
      ..['booted'] = 1
      ..['walletUnlocked'] = false
      ..['tab'] = _UnprintableSeedError();
    trace.observe(HomePreparationStep.initialReadiness, state: state);
    final Map<String, Object> first = trace.snapshot!;
    final Map<String, Object> copied = first['state']! as Map<String, Object>;
    expect(copied, <String, Object>{
      'at': 'initialReadiness', 'booted': 'unknown', 'unlocked': 'no',
      'initialized': 'yes', 'tab': 'unknown',
    });
    state['booted'] = true;
    trace.observe(HomePreparationStep.resolveTarget, target: 'home');
    expect(copied['booted'], 'unknown');
    expect(() => copied['tab'] = 'home', throwsUnsupportedError);
    expect(() => first['stage'] = 'private', throwsUnsupportedError);
    expect(jsonEncode(first), isNot(contains('private')));
    for (final Object? offered in <Object?>[
      null, true, <String, Object>{},
      <String, Object>{'stage': 'private'},
      <String, Object>{'stage': 'initialState', 'target': 'home'},
      <String, Object>{'stage': 'initialState', 'state': copied},
      <String, Object>{...first, 'path': 'private'},
      <String, Object>{...first, 'state': <String, Object>{
        ...copied, 'tab': 'private',
      }},
      <String, Object>{...first, 'state': <String, Object>{
        ...copied, 'booted': true,
      }},
    ]) {
      expect(homePreparationProjection(offered), isNull);
    }
    final Map<String, HomeTapReply> codes = <String, HomeTapReply>{
      'nothing matches': HomeTapReply.targetMissing,
      'disabled': HomeTapReply.targetDisabled,
      'covered by something else': HomeTapReply.targetCovered,
      'expected one owned Flutter view': HomeTapReply.viewAmbiguous,
    };
    for (final MapEntry<String, HomeTapReply> code in codes.entries) {
      expect(classifyHomeTapReply(code.key), code.value);
    }
    for (final Object? private in <Object?>[
      null, true, _UnprintableSeedError(), 'synthetic-private',
    ]) {
      expect(classifyHomeTapReply(private), HomeTapReply.unknown);
    }
    final Map<String, Object> tap = <String, Object>{
      'stage': 'gotoTap', 'target': 'dashboard',
      'state': <String, Object>{
        'at': 'gotoTarget', 'booted': 'yes', 'unlocked': 'yes',
        'initialized': 'yes', 'tab': 'other',
      },
    };
    for (final HomeTapReply code in HomeTapReply.values) {
      final Map<String, Object> observed = homePreparationProjection(
        <String, Object>{...tap, 'reply': code.name},
      )!;
      expect(observed['reply'], code.name);
      expect(() => observed['reply'] = 'private', throwsUnsupportedError);
    }
    for (final Map<String, Object> offered in <Map<String, Object>>[
      <String, Object>{...tap, 'reply': 'private'},
      <String, Object>{...tap, 'reply': true},
      <String, Object>{...tap, 'reply': 'targetCovered', 'stage': 'gotoWait'},
      <String, Object>{...first, 'reply': 'targetCovered'},
      <String, Object>{'stage': 'gotoTap', 'reply': 'targetCovered'},
    ]) {
      expect(homePreparationProjection(offered), isNull);
    }
    trace.clear();
    expect(trace.snapshot, isNull);
    expect(copied['booted'], 'unknown');
  });

  test('Home detail stays before command one and clears at each boundary', () {
    final cli.SeedOperationTrace trace = _homeTrace()
      ..homeObserved(HomePreparationStep.initialReadiness, state: _homeState());
    final cli.SeedOperationFailure first =
        trace.failure(_UnprintableSeedError());
    final Map<String, Object> home =
        first.diagnostic['home']! as Map<String, Object>;
    expect(home['stage'], 'initialReadiness');
    expect(trace.failure(cli.Fail('synthetic-private',
      homeTapReply: HomeTapReply.targetCovered)).diagnostic['home'], home);
    trace
      ..at(cli.SeedOperationAction.prepare, cli.SeedOperationStep.owner,
          commandIndex: 1)
      ..homeObserved(HomePreparationStep.railWait);
    expect(trace.failure(_UnprintableSeedError()).diagnostic,
        isNot(contains('home')));
    trace.at(cli.SeedOperationAction.home, cli.SeedOperationStep.navigation,
        commandIndex: 0);
    expect(trace.failure(_UnprintableSeedError()).diagnostic,
        isNot(contains('home')));
    trace
      ..publicationCallEntered()
      ..homeObserved(HomePreparationStep.railWait);
    expect(trace.failure(_UnprintableSeedError()).diagnostic,
        isNot(contains('home')));
    final cli.SeedOperationTrace foreign = _homeTrace(recipe: 'private')
      ..homeObserved(HomePreparationStep.railWait);
    expect(foreign.failure(_UnprintableSeedError()).diagnostic,
        isNot(contains('home')));
    expect(home['stage'], 'initialReadiness');
    expect(trace.failure(cli.Fail('synthetic-private',
      homeTapReply: HomeTapReply.targetCovered)).diagnostic,
        isNot(contains('home')));
    expect(() => home['target'] = 'dashboard', throwsUnsupportedError);
    expect(jsonEncode(first.diagnostic), isNot(contains('private')));
  });

  test('Home observer preserves both aliases and exact original rail calls',
      () async {
    for (final String target in <String>['home', 'dashboard']) {
      for (final bool expanded in <bool>[false, true]) {
        final _HomeReplies observed = _HomeReplies(
          _homeReplies(target: target, expanded: expanded),
        );
        final _HomeReplies legacy = _HomeReplies(
          _homeReplies(target: target, expanded: expanded),
        );
        final cli.SeedOperationTrace trace = _homeTrace();
        await cli.prepareScreenHome(observed, observe: trace.homeObserved);
        await cli.prepareScreenHome(legacy);
        expect(observed._commands,
          _homeCommands(target: target, expanded: expanded));
        expect(observed._commands, legacy._commands);
        final Map<String, Object> home = trace
            .failure(_UnprintableSeedError()).diagnostic['home']!
                as Map<String, Object>;
        expect(home['stage'], 'finalReadiness');
        expect(home['target'], target);
        expect(home['state'], <String, Object>{
          'at': 'finalReadiness', 'booted': 'yes', 'unlocked': 'yes',
          'initialized': 'yes', 'tab': target,
        });
      }
    }
  });

  test('Home transport failures identify only the original entered call',
      () async {
    const List<String> stages = <String>[
      'initialState', 'gotoState', 'gotoTap', 'gotoWait', 'railState',
      'railTogglePresence', 'railLabelPresence', 'railToggle', 'railWait',
      'finalState',
    ];
    const List<String?> lastStates = <String?>[
      null, 'initialReadiness', 'gotoTarget', 'gotoTarget', 'gotoWait',
      'railReadiness', 'railReadiness', 'railReadiness', 'railReadiness',
      'railReadiness',
    ];
    for (int index = 0; index < stages.length; index++) {
      final List<Object> replies = _homeReplies(expanded: true);
      replies[index] = _UnprintableSeedError();
      final _HomeReplies original = _HomeReplies(replies);
      final cli.SeedOperationTrace trace = _homeTrace();
      await expectLater(cli.prepareScreenHome(original,
        observe: trace.homeObserved), throwsA(isA<_UnprintableSeedError>()));
      expect(original._commands,
        _homeCommands(expanded: true).take(index + 1).toList());
      final Map<String, Object> home = trace
          .failure(_UnprintableSeedError()).diagnostic['home']!
              as Map<String, Object>;
      expect(home['stage'], stages[index]);
      expect((home['state'] as Map<String, Object>?)?['at'], lastStates[index]);
      expect(jsonEncode(home), isNot(contains('private')));
    }
    final Map<String, HomeTapReply> replies = <String, HomeTapReply>{
      'nothing matches': HomeTapReply.targetMissing,
      'disabled': HomeTapReply.targetDisabled,
      'covered by something else': HomeTapReply.targetCovered,
      'expected one owned Flutter view': HomeTapReply.viewAmbiguous,
      'synthetic-private': HomeTapReply.unknown,
    };
    for (final MapEntry<String, HomeTapReply> reply in replies.entries) {
      final List<Object> packets = _homeReplies();
      packets[2] = <String, dynamic>{
        'ok': false, 'error': reply.key,
        'detail': <String, String>{'private': 'synthetic-private'},
        'stack': 'synthetic-private',
      };
      final _HomeReplies original = _HomeReplies(packets);
      final cli.SeedOperationTrace trace = _homeTrace();
      cli.Fail? failed;
      try {
        await cli.prepareScreenHome(original, observe: trace.homeObserved);
      } on cli.Fail catch (error) {
        failed = error;
      }
      expect(failed, isNotNull);
      final cli.Fail originalFailure = failed!;
      expect(originalFailure.message,
        'tap: ${reply.key} {"private":"synthetic-private"}'
        '\nsynthetic-private');
      expect(original._commands, _homeCommands().take(3).toList());
      final cli.SeedOperationFailure observed = trace.failure(originalFailure);
      final Map<String, Object> detail =
          observed.diagnostic['home']! as Map<String, Object>;
      expect(detail['stage'], 'gotoTap');
      expect(detail['target'], 'home');
      expect(detail['reply'], reply.value.name);
      expect(jsonEncode(observed.diagnostic),
        isNot(contains('synthetic-private')));
      trace.at(cli.SeedOperationAction.prepare, cli.SeedOperationStep.owner,
        commandIndex: 1);
      expect(trace.failure(originalFailure).diagnostic,
        isNot(contains('home')));
      expect(detail['reply'], reply.value.name);
    }
  });

  test('Home validation refusals preserve original state and stop immediately',
      () async {
    final List<(int, Map<String, dynamic>, String)> refusals =
        <(int, Map<String, dynamic>, String)>[
      (0, _homeState()..['walletUnlocked'] = false, 'initialReadiness'),
      (0, _homeState()..['tabs'] = true, 'resolveTarget'),
      (1, _homeState()..['tabs'] = <String>['staking'], 'gotoTarget'),
      (4, _homeState()..['walletInitCompleted'] = false, 'railReadiness'),
      (5, <String, dynamic>{'ok': false}, 'railTogglePresence'),
      (7, _homeState()..['tab'] = 'staking', 'finalReadiness'),
    ];
    for (final (int index, Map<String, dynamic> reply, String stage)
        in refusals) {
      final List<Object> replies = _homeReplies();
      replies[index] = reply;
      final _HomeReplies original = _HomeReplies(replies);
      final cli.SeedOperationTrace trace = _homeTrace();
      await expectLater(cli.prepareScreenHome(original,
        observe: trace.homeObserved), throwsA(stage == 'resolveTarget'
          ? isA<TypeError>() : isA<cli.Fail>()));
      expect(original._commands, _homeCommands().take(index + 1).toList());
      final Map<String, Object> home = trace
          .failure(_UnprintableSeedError()).diagnostic['home']!
              as Map<String, Object>;
      expect(home['stage'], stage);
      expect(jsonEncode(home), isNot(contains('private')));
    }
  });

  test('one derived member precedes six exact ordered original receipts',
      () async {
    final _Session session = _Session();
    final Map<String, Object> result = await session.workflow().run(
      'synthetic-external-member',
    );
    expect(session.preparations, 1);
    expect(session.started, seedRecipeIds.toList());
    expect(result['members'], 3);
    expect(result['receipts'], hasLength(6));
    expect(result.toString(), isNot(contains('synthetic-member')));
  });

  test('a replaced initial owner receives no Settings or recipe input',
      () async {
    final _Session session = _Session()..current = _context(owner: 2);
    await expectLater(session.workflow().run('synthetic-external-member'),
      throwsA(isA<SeedRefused>()));
    expect(session.preparations, 0);
    expect(session.started, isEmpty);
  });

  test('an unrelated generation cannot admit the first seed recipe', () async {
    final _Session session = _Session()..wrongDerivation = true;
    await expectLater(session.workflow().run('synthetic-external-member'),
      throwsA(isA<SeedRefused>()));
    expect(session.started, isEmpty);
  });

  test('parent EOF during derivation admits no seed publication', () async {
    final _Session session = _Session()..dieDuringPreparation = true;
    await expectLater(session.workflow().run('synthetic-external-member'),
      throwsA(isA<SeedRefused>()));
    expect(session.started, isEmpty);
  });

  test('wrong recipe, unknown outcome and invalid hash hold later recipes',
      () async {
    for (final Map<String, Object?> change in <Map<String, Object?>>[
      <String, Object?>{'recipe': 'fuse'},
      <String, Object?>{'confirmed': false},
      <String, Object?>{'hash': _hash(0)},
    ]) {
      final _Session session = _Session()..receiptChange = change;
      await expectLater(session.workflow().run('synthetic-external-member'),
        throwsA(isA<SeedRefused>()));
      expect(session.started, <String>['stake']);
    }
  });

  test('the same accepted hash cannot qualify two different seed effects',
      () async {
    final _Session session = _Session()..duplicateHash = true;
    await expectLater(session.workflow().run('synthetic-external-member'),
      throwsA(isA<SeedRefused>()));
    expect(session.started, <String>['stake', 'fuse']);
  });

  test('a failed original is retained without another recipe or retry',
      () async {
    final _Session session = _Session()
      ..duringRecipe = () async { throw const FormatException('unknown'); };
    final RestoredSeedWorkflow workflow = session.workflow();
    await expectLater(workflow.run('synthetic-external-member'),
      throwsFormatException);
    session.duringRecipe = null;
    await expectLater(workflow.run('synthetic-external-member'),
      throwsA(isA<SeedRefused>()));
    expect(session.preparations, 1);
    expect(session.started, <String>['stake']);
  });

  test('a late result from a changed owner cannot start the next recipe',
      () async {
    final _Session session = _Session();
    final Completer<void> original = Completer<void>();
    session.duringRecipe = () => original.future;
    final Future<Map<String, Object>> result = session.workflow().run(
      'synthetic-external-member',
    );
    for (int turn = 0; turn < 10 && session.started.isEmpty; turn++) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(session.started, <String>['stake']);
    session.current = _context(count: 3, revision: 22);
    original.complete();
    await expectLater(result, throwsA(isA<SeedRefused>()));
    expect(session.started, <String>['stake']);
  });

  test('a successful session cannot derive or publish a second time',
      () async {
    final _Session session = _Session();
    final RestoredSeedWorkflow workflow = session.workflow();
    await workflow.run('synthetic-external-member');
    await expectLater(workflow.run('synthetic-external-member'),
      throwsA(isA<SeedRefused>()));
    expect(session.preparations, 1);
    expect(session.started, hasLength(6));
  });

  test('seed failure snapshots remain immutable after later observations', () {
    final cli.SeedOperationTrace trace = cli.SeedOperationTrace('stake')
      ..at(cli.SeedOperationAction.check, cli.SeedOperationStep.owner,
          commandIndex: 2);
    final cli.SeedOperationFailure first = trace.failure(
      cli.Fail('synthetic-private-value'),
    );
    trace.at(cli.SeedOperationAction.command, cli.SeedOperationStep.execute,
        commandIndex: 9);
    expect(first.diagnostic['action'], 'check');
    expect(first.diagnostic['command_index'], 2);
    expect(() => first.diagnostic['command_index'] = 99,
        throwsUnsupportedError);
    expect(jsonEncode(first.diagnostic),
        isNot(contains('synthetic-private-value')));
  });

  test('seed failures retain only typed families without formatting errors',
      () {
    final List<(Object, String)> errors = <(Object, String)>[
      (cli.Fail('synthetic-private-value'), 'refused'),
      (const SeedRefused('exact-chain-321-lab-required'), 'refused'),
      (TimeoutException('synthetic-private-value'), 'timeout'),
      (const FormatException('synthetic-private-value'), 'format'),
      (RangeError('synthetic-private-value'), 'type'),
      (const FileSystemException('synthetic-private-value'), 'filesystem'),
      (StateError('synthetic-private-value'), 'state'),
      (_UnprintableSeedError(), 'other'),
    ];
    for (final (Object error, String kind) in errors) {
      final cli.SeedOperationFailure observed =
          cli.SeedOperationTrace('stake').failure(error);
      expect(observed.diagnostic['kind'], kind);
      expect(jsonEncode(observed.diagnostic),
          isNot(contains('synthetic-private-value')));
    }
  });

  test('seed reply codes use exact source labels and reject unknown material',
      () {
    final String code = cli.seedOperationReplyCodes.first;
    for (final String value in <String>[code, 'Seed refused: $code']) {
      final cli.SeedOperationTrace trace = cli.SeedOperationTrace('stake')
        ..at(cli.SeedOperationAction.begin, cli.SeedOperationStep.reply)
        ..refusedReply(value);
      expect(trace.failure(cli.Fail('synthetic-private-value'))
          .diagnostic['reason'], code);
    }
    for (final Object? value in <Object?>[
      null, true, 321, 'synthetic-private-value', '$code ',
      'Seed refused: synthetic-private-value', _UnprintableSeedError(),
    ]) {
      expect(cli.seedOperationReplyCode(value), 'unknown');
    }
  });

  test('publication entry describes the original call without acceptance', () {
    final cli.SeedOperationTrace trace = cli.SeedOperationTrace('stake')
      ..at(cli.SeedOperationAction.publish, cli.SeedOperationStep.owner,
          commandIndex: 7);
    final cli.SeedOperationFailure before = trace.failure(cli.Fail('private'));
    trace
      ..publicationCallEntered()
      ..at(cli.SeedOperationAction.publish, cli.SeedOperationStep.request);
    final cli.SeedOperationFailure after = trace.failure(cli.Fail('private'));
    expect(before.diagnostic['publication_call_entered'], isFalse);
    expect(after.diagnostic['publication_call_entered'], isTrue);
    expect(after.diagnostic['command_index'], 7);
    for (final cli.SeedOperationFailure failure in <cli.SeedOperationFailure>[
      before, after,
    ]) {
      expect(failure.diagnostic.containsKey('confirmed'), isFalse);
      expect(failure.diagnostic.containsKey('hash'), isFalse);
      expect(failure.diagnostic.containsKey('retry'), isFalse);
    }
  });

  test('seed child metadata is phase-bound and never fills an older refusal',
      () {
    final cli.SeedOperationFailure failure =
        cli.SeedOperationTrace('stake').failure(cli.Fail('private'));
    final Map<String, Object?> observed =
        reopen.restoredChildFailure('seed_stake', failure)!;
    expect(observed['kind'], 'HARNESS_REFUSED');
    expect(observed['code'], isNull);
    expect(observed['recipe'], isNull);
    expect(observed['seed'], failure.diagnostic);
    expect(reopen.restoredChildFailure('unlock', failure), isNull);
    final cli.SeedOperationTrace foreign = cli.SeedOperationTrace('private')
      ..at(cli.SeedOperationAction.command, cli.SeedOperationStep.execute,
          commandIndex: 100000);
    final cli.SeedOperationFailure held = foreign.failure(cli.Fail('private'));
    expect(held.diagnostic['recipe'], 'unknown');
    expect(held.diagnostic['command_index'], 0);
    expect(reopen.restoredChildFailure('seed_stake', held), isNull);
    final Map<String, Object?> original = reopen.restoredChildFailure(
      'seed_stake', cli.Fail('private'),
    )!;
    expect(original, <String, Object?>{
      'schema': 1, 'scope': 'owned_reopen_child_failure',
      'phase': 'seed_stake', 'kind': 'HARNESS_REFUSED',
      'code': null, 'recipe': null,
    });
  });

  test('original exhausted seed counts survive as an immutable failure', () {
    final Map<String, Object> counts = <String, Object>{
      'polls': 18, 'absent': 6, 'unconfirmed': 6,
      'effect_pending': 6, 'last': 'effect_pending',
    };
    final cli.SeedOperationTrace trace = cli.SeedOperationTrace('fuse')
      ..at(cli.SeedOperationAction.publish, cli.SeedOperationStep.reply,
          commandIndex: 7)
      ..publicationCallEntered()
      ..refusedReply('exact-confirmation-or-effect-pending',
          confirmation: counts);
    final cli.SeedOperationFailure first = trace.failure(cli.Fail('private'));
    final Map<String, Object> observed =
        first.diagnostic['confirmation']! as Map<String, Object>;
    counts['absent'] = 0;
    expect(observed['absent'], 6);
    expect(() => observed['polls'] = 0, throwsUnsupportedError);
    expect(reopen.restoredChildFailure('seed_fuse', first)!['seed'],
        first.diagnostic);
    trace.at(cli.SeedOperationAction.check, cli.SeedOperationStep.owner);
    expect(trace.failure(cli.Fail('private')).diagnostic
        .containsKey('confirmation'), isFalse);
    expect(observed['absent'], 6);
    expect(reopen.restoredChildFailure('seed_stake', first), isNull);
  });

  test('seed count labels cannot move across original reply boundaries', () {
    const Map<String, Object> counts = <String, Object>{
      'polls': 18, 'absent': 6, 'unconfirmed': 6,
      'effect_pending': 6, 'last': 'effect_pending',
    };
    for (final (cli.SeedOperationAction, cli.SeedOperationStep) boundary in
        <(cli.SeedOperationAction, cli.SeedOperationStep)>[
      (cli.SeedOperationAction.publish, cli.SeedOperationStep.owner),
      (cli.SeedOperationAction.publish, cli.SeedOperationStep.request),
      (cli.SeedOperationAction.command, cli.SeedOperationStep.execute),
      (cli.SeedOperationAction.finish, cli.SeedOperationStep.reply),
    ]) {
      final cli.SeedOperationTrace trace = cli.SeedOperationTrace('fuse')
        ..at(boundary.$1, boundary.$2, commandIndex: 7)
        ..publicationCallEntered()
        ..refusedReply('exact-confirmation-or-effect-pending',
            confirmation: counts);
      expect(trace.failure(cli.Fail('private')).diagnostic
          .containsKey('confirmation'), isFalse);
    }
    final cli.SeedOperationTrace trace = cli.SeedOperationTrace('fuse')
      ..at(cli.SeedOperationAction.publish, cli.SeedOperationStep.reply,
          commandIndex: 7)
      ..publicationCallEntered()
      ..refusedReply('unknown', confirmation: counts);
    expect(trace.failure(cli.Fail('private')).diagnostic
        .containsKey('confirmation'), isFalse);
    trace.refusedReply('exact-confirmation-or-effect-pending',
        confirmation: <String, Object>{...counts, 'path': 'private'});
    expect(trace.failure(cli.Fail('private')).diagnostic
        .containsKey('confirmation'), isFalse);
    trace.refusedReply('exact-confirmation-or-effect-pending',
        confirmation: counts);
    expect(trace.failure(TimeoutException('private')).diagnostic
        .containsKey('confirmation'), isFalse);
  });

  test('the confirmed original Project exit awaits its actual route once',
      () async {
    final Completer<Object?> route = Completer<Object?>();
    int exits = 0;
    int owners = 0;
    final SeedProjectPresentation presentation = _projectPresentation(
      route: route.future,
      tap: (void Function() admission) async {
        admission();
        exits++;
        admission();
      },
    );
    expect(presentation.requireCaptured, returnsNormally);
    final Future<void> original = presentation.close(_hash(9), () => owners++);
    await Future<void>.delayed(Duration.zero);
    expect(exits, 1);
    expect(presentation.closed, isFalse);
    route.complete(null);
    await original;
    expect(presentation.closed, isTrue);
    await presentation.close(_hash(9), () => owners++);
    expect(exits, 1);
    expect(owners, greaterThanOrEqualTo(3));
    await expectLater(presentation.close(_hash(8), () {}),
        throwsA(isA<SeedRefused>()));
    expect(presentation.closed, isTrue);
    expect(exits, 1);
  });

  test('a revoked Project view or owner cannot revive its original exit',
      () async {
    for (final String phase in <String>['before', 'release', 'owner']) {
      final Completer<Object?> route = Completer<Object?>();
      bool live = phase != 'before';
      bool owner = phase != 'owner';
      int exits = 0;
      final SeedProjectPresentation presentation = _projectPresentation(
        route: route.future, current: () => live,
        tap: (void Function() admission) async {
          admission();
          if (phase == 'release') live = false;
          admission();
          exits++;
        },
      );
      void current() {
        if (!owner) throw const SeedRefused('original-context-changed');
      }
      await expectLater(presentation.close(_hash(9), current),
          throwsA(isA<SeedRefused>()));
      live = true;
      owner = true;
      await expectLater(presentation.close(_hash(9), current),
          throwsA(isA<SeedRefused>()));
      expect(exits, 0);
      route.complete(null);
      await Future<void>.delayed(Duration.zero);
      expect(presentation.closed, isFalse);
    }
  });

  test('pending or failed original Project closure never authorizes a retry',
      () async {
    for (final bool fail in <bool>[false, true]) {
      final Completer<Object?> route = Completer<Object?>();
      int exits = 0;
      final SeedProjectPresentation presentation = _projectPresentation(
        route: route.future, timeout: const Duration(milliseconds: 1),
        tap: (void Function() admission) async {
          admission();
          exits++;
          if (fail) throw StateError('synthetic private close failure');
        },
      );
      await expectLater(presentation.close(_hash(9), () {}),
          throwsA(fail ? isA<StateError>() : isA<SeedRefused>()));
      expect(exits, 1);
      expect(presentation.closed, isFalse);
      route.complete(null);
      await Future<void>.delayed(Duration.zero);
      expect(presentation.closed, isFalse);
      await expectLater(presentation.close(_hash(9), () {}),
          throwsA(isA<SeedRefused>()));
      expect(exits, 1);
    }
    for (final Duration timeout in <Duration>[
      Duration.zero, const Duration(seconds: 6),
    ]) {
      expect(() => _projectPresentation(
        route: Future<Object?>.value(), timeout: timeout,
      ), throwsArgumentError);
    }
  });

  test('Project view evidence keeps opaque identities and immutable UI hashes',
      () {
    final Object owner = Object();
    final Object source = Object();
    final Object draft = Object();
    AcceleratorActionPresentation view({
      Object? ownerChange, Object? sourceChange, Object? draftChange,
      int epoch = 1, bool current = true, bool submitted = false,
      List<String> hashes = const <String>[],
    }) => AcceleratorActionPresentation(
      owner: ownerChange ?? owner, source: sourceChange ?? source,
      draft: draftChange ?? draft, epoch: epoch,
      kind: AcceleratorActionKind.createProject, current: current,
      submitted: submitted, hashes: hashes,
    );
    final AcceleratorActionPresentation original = view();
    expect(original.prepared, isTrue);
    expect(original.current, isTrue);
    expect(view(current: false).current, isFalse);
    final List<String> hashes = <String>[_hash(9)];
    final AcceleratorActionPresentation submitted = view(
      submitted: true, hashes: hashes,
    );
    hashes[0] = _hash(8);
    expect(submitted.sameOwner(original), isTrue);
    expect(submitted.submittedWith(_hash(9)), isTrue);
    expect(submitted.submittedWith(_hash(8)), isFalse);
    expect(submitted.prepared, isFalse);
    expect(submitted.toString(), isNot(contains(_hash(9))));
    for (final AcceleratorActionPresentation replacement in
        <AcceleratorActionPresentation>[
      view(ownerChange: Object()), view(sourceChange: Object()),
      view(draftChange: Object()), view(epoch: 2),
    ]) {
      expect(replacement.sameOwner(original), isFalse);
    }
    const Object first = ValueKey<String>('same synthetic value');
    final Object second = ValueKey<String>(
      String.fromCharCodes('same synthetic value'.codeUnits),
    );
    expect(first, second);
    expect(identical(first, second), isFalse);
    expect(view(draftChange: first).sameOwner(view(draftChange: second)),
        isFalse);
    expect(view(current: false, submitted: true,
        hashes: <String>[_hash(9)]).submittedWith(_hash(9)), isFalse);
    expect(view(submitted: true, hashes: <String>[_hash(9), _hash(8)])
        .submittedWith(_hash(9)), isFalse);
    for (final String code in <String>[
      'confirmed-project-presentation-required',
      'original-project-presentation-changed',
      'original-project-presentation-close-pending',
      'original-project-presentation-held',
      'original-project-presentation-required',
    ]) {
      expect(cli.seedOperationReplyCode(code), code);
    }
  });

  testWidgets('confirmed Project exits through its original view and route',
      (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 780));
    final ActionSource source = ActionSource(scope: Object());
    int exits = 0;
    try {
      final (SeedProjectPresentation original, ModalRoute<dynamic> route) =
          await _submittedProject(tester, source, () => exits++);
      bool completed = false;
      unawaited(route.completed.then((_) { completed = true; }));
      expect(completed, isFalse);
      await _projectClose(tester, original.close(listHash(901), () {}));
      expect(original.closed, isTrue);
      expect(completed, isTrue);
      expect(exits, 1);
      expect(find.byType(ProjectCreationStepper), findsNothing);
      expect(find.byKey(const Key('project_original_home')).hitTestable(),
          findsOneWidget);
      await original.close(listHash(901), () {});
      expect(exits, 1);
      expect(source.publications, 1);
      expect(source.builders, hasLength(1));
      expect(source.confirmedReads, isEmpty);
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
      await tester.binding.setSurfaceSize(null);
    }
  });

  testWidgets('a submitted Project UI hash alone cannot replace the original',
      (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 780));
    final ActionSource source = ActionSource(scope: Object());
    int exits = 0;
    try {
      final (SeedProjectPresentation original, ModalRoute<dynamic> route) =
          await _submittedProject(tester, source, () => exits++);
      await expectLater(original.close(listHash(902), () {}),
          throwsA(isA<SeedRefused>()));
      await expectLater(original.close(listHash(901), () {}),
          throwsA(isA<SeedRefused>()));
      expect(original.closed, isFalse);
      expect(route.isCurrent, isTrue);
      expect(exits, 0);
      expect(find.byKey(const Key('acc_stepper_leave')), findsOneWidget);
      expect(find.byKey(const Key('project_original_home')).hitTestable(),
          findsNothing);
      expect(source.publications, 1);
      expect(source.confirmedReads, isEmpty);
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
      await tester.binding.setSurfaceSize(null);
    }
  });
  test('the confirmed original Token exit awaits its actual route once',
      () async {
    final Completer<Object?> route = Completer<Object?>();
    int exits = 0;
    int owners = 0;
    final SeedTokenPresentation presentation = _tokenPresentation(
      route: route.future,
      tap: (void Function() admission) async {
        admission();
        exits++;
        admission();
      },
    );
    expect(presentation.requireCaptured, returnsNormally);
    final Future<void> original = presentation.close(_hash(9), () => owners++);
    await Future<void>.delayed(Duration.zero);
    expect(exits, 1);
    expect(presentation.closed, isFalse);
    route.complete(null);
    await original;
    expect(presentation.closed, isTrue);
    await presentation.close(_hash(9), () => owners++);
    expect(exits, 1);
    expect(owners, greaterThanOrEqualTo(3));
    await expectLater(presentation.close(_hash(8), () {}),
        throwsA(isA<SeedRefused>()));
    expect(presentation.closed, isTrue);
    expect(exits, 1);
  });

  test('a revoked Token view or owner cannot revive its original exit',
      () async {
    for (final String phase in <String>['before', 'release', 'owner']) {
      final Completer<Object?> route = Completer<Object?>();
      bool live = phase != 'before';
      bool owner = phase != 'owner';
      int exits = 0;
      final SeedTokenPresentation presentation = _tokenPresentation(
        route: route.future, current: () => live,
        tap: (void Function() admission) async {
          admission();
          if (phase == 'release') live = false;
          admission();
          exits++;
        },
      );
      void current() {
        if (!owner) throw const SeedRefused('original-context-changed');
      }
      await expectLater(presentation.close(_hash(9), current),
          throwsA(isA<SeedRefused>()));
      live = true;
      owner = true;
      await expectLater(presentation.close(_hash(9), current),
          throwsA(isA<SeedRefused>()));
      expect(exits, 0);
      route.complete(null);
      await Future<void>.delayed(Duration.zero);
      expect(presentation.closed, isFalse);
    }
  });

  test('pending or failed original Token closure never authorizes a retry',
      () async {
    for (final bool fail in <bool>[false, true]) {
      final Completer<Object?> route = Completer<Object?>();
      int exits = 0;
      final SeedTokenPresentation presentation = _tokenPresentation(
        route: route.future, timeout: const Duration(milliseconds: 1),
        tap: (void Function() admission) async {
          admission();
          exits++;
          if (fail) throw StateError('synthetic private close failure');
        },
      );
      await expectLater(presentation.close(_hash(9), () {}),
          throwsA(fail ? isA<StateError>() : isA<SeedRefused>()));
      expect(exits, 1);
      expect(presentation.closed, isFalse);
      route.complete(null);
      await Future<void>.delayed(Duration.zero);
      expect(presentation.closed, isFalse);
      await expectLater(presentation.close(_hash(9), () {}),
          throwsA(isA<SeedRefused>()));
      expect(exits, 1);
    }
    for (final Duration timeout in <Duration>[
      Duration.zero, const Duration(seconds: 6),
    ]) {
      expect(() => _tokenPresentation(
        route: Future<Object?>.value(), timeout: timeout,
      ), throwsArgumentError);
    }
  });


  test('the original confirmation attempt changes only after confirmed Another',
      () async {
    final _TokenRoute fixture = _TokenRoute();
    final RegistrationConfirmation confirmation = fixture.confirmation;
    final Object attempt = confirmation.originalAttempt;
    try {
      expect(confirmation.resetForAnother(), isFalse);
      expect(confirmation.originalAttempt, same(attempt));
      final AccountBlockTemplate accepted = AccountBlockTemplate(
        blockType: BlockTypeEnum.userSend.index,
      )..address = emptyAddress
        ..chainIdentifier = 321
        ..hash = Hash.parse(_hash(9));
      confirmation.accept(RegistrationPublication(accountBlock: accepted));
      expect(confirmation.originalAttempt, same(attempt));
      await confirmation.check();
      expect(confirmation.isConfirmed, isTrue);
      final int reads = fixture.confirmationReads;
      expect(confirmation.originalAttempt, same(attempt));
      expect(confirmation.resetForAnother(), isTrue);
      final Object another = confirmation.originalAttempt;
      expect(another, isNot(same(attempt)));
      expect(confirmation.resetForAnother(), isFalse);
      expect(confirmation.originalAttempt, same(another));
      expect(fixture.confirmationReads, reads);
      expect(fixture.issues, 0);
    } finally {
      confirmation.dispose();
      fixture.registry.dispose();
      fixture.fixture.dispose();
      fixture.collapse.dispose();
      fixture.revision.dispose();
      await fixture.states.close();
      await fixture.bloc.close();
    }
    for (final String code in <String>[
      'confirmed-token-presentation-required',
      'original-token-presentation-changed',
      'original-token-presentation-close-pending',
      'original-token-presentation-held',
      'original-token-presentation-required',
    ]) {
      expect(cli.seedOperationReplyCode(code), code);
    }
  });

  testWidgets('original Token Done completes StepperScreen and restores Home',
      (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 780));
    final _TokenRoute fixture = _TokenRoute();
    try {
      await fixture.mount(tester);
      final SeedTokenPresentation original = await fixture.submit(tester);
      final HarnessAgent agent = HarnessAgent.forTest()..booted = true;
      await expectLater(agent.commandForTest(<String, dynamic>{
        'cmd': 'tap', 'tab': 'dashboard',
      }), throwsA(isA<HarnessError>().having(
        (HarnessError error) => error.toString(),
        'message', 'nothing matches')));
      expect(fixture.opened, isEmpty);
      expect(find.byKey(const Key('nav_dashboard')).hitTestable(),
          findsNothing);
      bool completed = false;
      unawaited(fixture.route!.completed.then((_) { completed = true; }));
      final int reads = fixture.confirmationReads;
      await _projectClose(tester, original.close(_hash(9), () {}));
      expect(completed, isTrue);
      expect(original.closed, isTrue);
      expect(find.byType(StepperScreen), findsNothing);
      expect(find.byKey(const Key('nav_dashboard')).hitTestable(),
          findsOneWidget);
      await _projectClose(tester, agent.commandForTest(<String, dynamic>{
        'cmd': 'tap', 'tab': 'dashboard', 'settleMs': 0,
      }).then<void>((_) {}));
      expect(fixture.opened, <Tabs>[Tabs.dashboard]);
      await original.close(_hash(9), () {});
      expect(fixture.exits, 1);
      expect(fixture.issues, 1);
      expect(fixture.confirmationReads, reads);
      expect(tester.takeException(), isNull);
    } finally {
      await fixture.dispose(tester);
      await tester.binding.setSurfaceSize(null);
    }
  });

  for (final String reason in <String>[
    'hash', 'owner', 'preflight', 'confirmation', 'state', 'another',
  ]) {
    testWidgets('an original Token exit cannot revive after $reason changes',
        (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 780));
      final _TokenRoute fixture = _TokenRoute();
      try {
        await fixture.mount(tester);
        final SeedTokenPresentation original = await fixture.submit(tester);
        final Object attempt = fixture.confirmation.originalAttempt;
        final State originalState = tester.state(
          find.byType(CreateTokenStepperView),
        );
        switch (reason) {
          case 'owner':
            fixture.ownerCurrent = false;
          case 'preflight':
            final TokenCreateFixture replacement = TokenCreateFixture();
            fixture.replacementFixtures.add(replacement);
            fixture.displayedFixture = replacement;
            fixture.revision.value++;
          case 'confirmation':
            final RegistrationConfirmation replacement =
                fixture.newConfirmation();
            fixture.replacements.add(replacement);
            fixture.displayedConfirmation = replacement;
            fixture.revision.value++;
          case 'state':
            fixture.viewKey = Object();
            fixture.revision.value++;
          case 'another':
            await tester.tap(find.byKey(const Key('registration_another')));
            await _projectFrame(tester);
            expect(tester.state(find.byType(CreateTokenStepperView)),
                same(originalState));
            expect(fixture.confirmation.originalAttempt,
                isNot(same(attempt)));
            final RegistrationPublication sameHash = RegistrationPublication(
              accountBlock: AccountBlockTemplate(
                blockType: BlockTypeEnum.userSend.index,
              )..address = emptyAddress
                ..chainIdentifier = 321
                ..hash = Hash.parse(_hash(9)),
            );
            fixture.confirmation.accept(sameHash);
            await fixture.confirmation.check();
            expect(fixture.confirmation.isConfirmed, isTrue);
          case 'hash':
            break;
        }
        await _projectFrame(tester);
        final int reads = fixture.confirmationReads;
        await expectLater(original.close(
          reason == 'hash' ? _hash(8) : _hash(9), () {},
        ), throwsA(isA<SeedRefused>()));
        fixture.ownerCurrent = true;
        fixture.displayedFixture = fixture.fixture;
        fixture.displayedConfirmation = fixture.confirmation;
        fixture.revision.value++;
        await _projectFrame(tester);
        await expectLater(original.close(_hash(9), () {}),
            throwsA(isA<SeedRefused>()));
        expect(original.closed, isFalse);
        expect(fixture.route!.isCurrent, isTrue);
        expect(fixture.exits, 0);
        expect(fixture.issues, 1);
        expect(fixture.confirmationReads, reads);
        expect(find.byKey(const Key('nav_dashboard')).hitTestable(),
            findsNothing);
        expect(tester.takeException(), isNull);
      } finally {
        await fixture.dispose(tester);
        await tester.binding.setSurfaceSize(null);
      }
    });
  }


  test('preparation UI labels remain bound to the original negative reply', () {
    for (final String code in seedPreparationUiFailureCodes) {
      final cli.SeedOperationTrace original = cli.SeedOperationTrace('stake')
        ..at(cli.SeedOperationAction.prepare, cli.SeedOperationStep.reply,
            commandIndex: 3)
        ..refusedReply(code);
      final Map<String, Object> data =
          original.failure(cli.Fail('Synthetic private failure')).diagnostic;
      expect(data['reason'], code);
      expect(data['action'], 'prepare');
      expect(data['publication_call_entered'], isFalse);
      for (final cli.SeedOperationAction action in <cli.SeedOperationAction>[
        cli.SeedOperationAction.begin,
        cli.SeedOperationAction.check,
        cli.SeedOperationAction.publish,
        cli.SeedOperationAction.finish,
      ]) {
        final cli.SeedOperationTrace other = cli.SeedOperationTrace('stake')
          ..at(action, cli.SeedOperationStep.reply, commandIndex: 3)
          ..refusedReply(code);
        expect(other.failure(cli.Fail('Synthetic private failure'))
            .diagnostic['reason'], 'unknown');
      }
      for (final bool entered in <bool>[false, true]) {
        final cli.SeedOperationTrace other = cli.SeedOperationTrace('stake')
          ..at(cli.SeedOperationAction.prepare,
              entered ? cli.SeedOperationStep.reply
                  : cli.SeedOperationStep.request, commandIndex: 3)
          ..refusedReply(code);
        if (entered) other.publicationCallEntered();
        expect(other.failure(cli.Fail('Synthetic private failure'))
            .diagnostic['reason'], 'unknown');
      }
    }
  });
}
