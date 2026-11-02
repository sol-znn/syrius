import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:flutter/gestures.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:layout/layout.dart';
import 'package:local_notifier/local_notifier.dart';
import 'package:logging/logging.dart';
import 'package:material_ui/material_ui.dart';
import 'package:nested/nested.dart';
import 'package:overlay_support/overlay_support.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:retry/retry.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';
import 'package:zenon_syrius_wallet_flutter/blocs/auto_unlock_htlc_worker.dart';
import 'package:zenon_syrius_wallet_flutter/blocs/blocs.dart';
import 'package:zenon_syrius_wallet_flutter/blocs/wallet_connect/chains/i_chain.dart';
import 'package:zenon_syrius_wallet_flutter/blocs/wallet_connect/chains/nom_service.dart';
import 'package:zenon_syrius_wallet_flutter/blocs/wallet_connect/wallet_connect_pairings_bloc.dart';
import 'package:zenon_syrius_wallet_flutter/blocs/wallet_connect/wallet_connect_sessions_bloc.dart';
import 'package:zenon_syrius_wallet_flutter/handlers/htlc_swaps_handler.dart';
import 'package:zenon_syrius_wallet_flutter/hive/hive_registrar.g.dart';
import 'package:zenon_syrius_wallet_flutter/l10n/app_localizations.dart';
import 'package:zenon_syrius_wallet_flutter/l10n/l10n.dart';
import 'package:zenon_syrius_wallet_flutter/model/model.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/features.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/utils.dart';
import 'package:zenon_syrius_wallet_flutter/screens/screens.dart';
import 'package:zenon_syrius_wallet_flutter/services/htlc_swaps_service.dart';
import 'package:zenon_syrius_wallet_flutter/services/i_web3wallet_service.dart';
import 'package:zenon_syrius_wallet_flutter/services/shared_prefs_service.dart';
import 'package:zenon_syrius_wallet_flutter/services/web3wallet_service.dart';
import 'package:zenon_syrius_wallet_flutter/utils/font_licences.dart';
import 'package:zenon_syrius_wallet_flutter/utils/functions.dart';
import 'package:zenon_syrius_wallet_flutter/utils/motion_binding.dart';
import 'package:zenon_syrius_wallet_flutter/utils/utils.dart';
import 'package:zenon_syrius_wallet_flutter/utils/window_chrome.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/widgets.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/window_frame.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

/// The current process SDK; owned operations retain their original instance.
Zenon? zenon;

/// Process preferences remain distinct from captured original Box receipts.
SharedPrefsService? sharedPrefsService;

/// The initialized encrypted swap service, not a name-based replacement lookup.
HtlcSwapsService? htlcSwapsService;

/// The existing WalletConnect owner shared by the application entrypoint.
IWeb3WalletService? web3WalletService;

/// Process service registry; asynchronous actions must capture before waiting.
final GetIt sl = GetIt.instance;

/// The root navigator used by explicit application routes and owned overlays.
final GlobalKey<NavigatorState> globalNavigatorKey =
    GlobalKey<NavigatorState>();

Future<void> main() async {
  // Not the SDK's binding: this one keeps every animation at full length when
  // the system asks for reduced motion. It must be the first binding the
  // process creates, so anything that wraps this main installs it too.
  MotionBinding.ensureInitialized();
  registerBundledFontLicences();
  Bloc.observer = CustomBlocObserver();
  if (Platform.isWindows) {
    registerProtocolHandler(kDeepLinkingUrlScheme);
  }
  // Init hydrated bloc storage
  HydratedBloc.storage = await HydratedStorage.build(
    storageDirectory: kIsWeb
        ? HydratedStorageDirectory.web
        : HydratedStorageDirectory((await getTemporaryDirectory()).path),
  );
  Provider.debugCheckInvalidValueType = null;

  ensureDirectoriesExist();
  Hive.init(znnDefaultPaths.cache.path);

  // Setup logger
  final Directory syriusLogDir = Directory(
    path.join(znnDefaultCacheDirectory.path, 'log'),
  );
  if (!syriusLogDir.existsSync()) {
    syriusLogDir.createSync(recursive: true);
  }
  final String logName = 'syrius-${DateTime.now().millisecondsSinceEpoch}.log';
  final File logFile = File(path.join(syriusLogDir.path, logName));
  Logger.root.level = Level.ALL;
  Logger.root.onRecord.listen((LogRecord record) {
    if (kDebugMode) {
      print(
        '${record.level.name} ${record.loggerName} ${record.message} '
        '${record.time}: '
        '${record.error} ${record.stackTrace}\n',
      );
    }
    unawaited(
      logFile.writeAsString(
        '${record.level.name} ${record.loggerName} ${record.message} '
        '${record.time}: '
        '${record.error} ${record.stackTrace}\n',
        mode: FileMode.append,
        flush: true,
      ),
    );
  });

  await windowManager.ensureInitialized();
  await configureAppWindowChrome();
  await windowManager.setPreventClose(true);

  web3WalletService = Web3WalletService();
  await web3WalletService!.create();

  // Setup services
  setup();

  unawaited(
    retry(
      () => web3WalletService!.init(),
      retryIf: (Exception e) => e is SocketException || e is TimeoutException,
      maxAttempts: 0x7FFFFFFFFFFFFFFF,
    ),
  );

  // Setup local_notifier
  await localNotifier.setup(
    appName: 's y r i u s',
  );

  // Setup tray manager
  await _setupTrayManager();

  // Load default community nodes from assets
  await _loadDefaultCommunityNodes();

  // Register Hive adapters
  Hive.registerAdapters();

  if (sharedPrefsService == null) {
    sharedPrefsService = await sl.getAsync<SharedPrefsService>();
  } else {
    await sharedPrefsService!.checkIfBoxIsOpen();
  }

  htlcSwapsService ??= sl.get<HtlcSwapsService>();

  // The channel a web page reaches this wallet through. It answers nothing
  // about the wallet until the person approves the page's origin.
  unawaited(DappBridge.instance.start());

  unawaited(
    windowManager.waitUntilReadyToShow().then((_) async {
      await windowManager.setTitle('s y r i u s');
      await windowManager.setMinimumSize(const Size(1200, 600));
      await windowManager.show();

      if (sharedPrefsService != null) {
        final double? windowSizeWidth = sharedPrefsService!.get(
          kWindowSizeWidthKey,
        );
        final double? windowSizeHeight = sharedPrefsService!.get(
          kWindowSizeHeightKey,
        );
        if (windowSizeWidth != null &&
            windowSizeWidth >= 1200 &&
            windowSizeHeight != null &&
            windowSizeHeight >= 600) {
          await windowManager.setSize(Size(windowSizeWidth, windowSizeHeight));
        } else {
          await windowManager.setSize(const Size(1200, 600));
        }

        double? windowPositionX = sharedPrefsService!.get(kWindowPositionXKey);
        double? windowPositionY = sharedPrefsService!.get(kWindowPositionYKey);
        if (windowPositionX != null && windowPositionY != null) {
          windowPositionX = windowPositionX >= 0 ? windowPositionX : 100;
          windowPositionY = windowPositionY >= 0 ? windowPositionY : 100;
          await windowManager.setPosition(
            Offset(windowPositionX, windowPositionY),
          );
        }

        final bool? windowMaximized = sharedPrefsService!.get(
          kWindowMaximizedKey,
        );
        if (windowMaximized == true) {
          await windowManager.maximize();
        }
      }
    }),
  );

  runApp(
    const MyApp(),
  );
}

Future<void> _setupTrayManager() async {
  await trayManager.setIcon(
    Platform.isWindows
        ? 'assets/images/tray_app_icon.ico'
        : 'assets/images/tray_app_icon.png',
  );
  if (Platform.isMacOS) {
    await trayManager.setToolTip('s y r i u s');
  }
  final List<MenuItem> items = <MenuItem>[
    MenuItem(
      key: 'show_wallet',
      label: 'Show wallet',
    ),
    MenuItem(
      key: 'hide_wallet',
      label: 'Hide wallet',
    ),
    MenuItem.separator(),
    MenuItem(
      key: 'exit',
      label: 'Exit wallet',
    ),
  ];
  await trayManager.setContextMenu(Menu(items: items));
}

Future<void> _loadDefaultCommunityNodes() async {
  try {
    final List<dynamic> nodes =
        await loadJsonFromAssets('assets/community-nodes.json')
            as List<dynamic>;
    kDefaultCommunityNodes = nodes
        .map((dynamic node) => node.toString())
        .where((String node) => InputValidators.node(node) == null)
        .toList();
  } on Object catch (e, stackTrace) {
    Logger(
      'main',
    ).log(Level.WARNING, '_loadDefaultCommunityNodes', e, stackTrace);
  }
}

/// Installs the production process owners without reopening a wallet file.
void setup() {
  sl.registerSingleton<Zenon>(Zenon());
  zenon = sl<Zenon>();
  sl.registerLazySingletonAsync<SharedPrefsService>(
    () => SharedPrefsService.getInstance().then(
      (SharedPrefsService? value) => value!,
    ),
  );
  sl.registerSingleton<HtlcSwapsService>(HtlcSwapsService.shared());

  // Initialize WalletConnect service
  sl.registerSingleton<IWeb3WalletService>(web3WalletService!);
  sl.registerSingleton<IChain>(
    NoMService(reference: NoMChainId.mainnet),
    instanceName: NoMChainId.mainnet.chain(),
  );

  sl.registerSingleton<LatestTransactionsBloc>(
    LatestTransactionsBloc(
      zenon: zenon!,
    ),
  );
  sl.registerSingleton<PendingTransactionsBloc>(
    PendingTransactionsBloc(
      zenon: zenon!,
    ),
  );
  sl
    ..registerSingleton<MultipleBalanceBloc>(MultipleBalanceBloc(zenon: zenon!))
    ..registerSingleton<AutoReceiveTxWorker>(AutoReceiveTxWorker.shared())
    ..registerSingleton<AutoUnlockHtlcWorker>(AutoUnlockHtlcWorker.shared());

  sl
    ..registerSingleton<HtlcSwapsHandler>(HtlcSwapsHandler.shared())
    ..registerSingleton<ReceivePort>(
      ReceivePort(),
      instanceName: 'embeddedStoppedPort',
    )
    ..registerSingleton<Stream<dynamic>>(
      sl<ReceivePort>(instanceName: 'embeddedStoppedPort').asBroadcastStream(),
      instanceName: 'embeddedStoppedStream',
    );

  sl
    ..registerSingleton<BalanceBloc>(BalanceBloc())
    ..registerSingleton<NotificationsBloc>(NotificationsBloc())
    ..registerSingleton<AcceleratorBalanceBloc>(AcceleratorBalanceBloc())
    ..registerSingleton<PowGeneratingStatusBloc>(PowGeneratingStatusBloc())
    ..registerSingleton<WalletConnectPairingsBloc>(WalletConnectPairingsBloc())
    ..registerSingleton<WalletConnectSessionsBloc>(WalletConnectSessionsBloc());
}

Route<dynamic>? _buildErrorRoute(RouteSettings settings) {
  if (settings.name != SyriusErrorWidget.route) return null;
  final CustomSyriusErrorWidgetArguments args =
      settings.arguments! as CustomSyriusErrorWidgetArguments;
  return MaterialPageRoute<dynamic>(
    builder: (BuildContext context) => SyriusErrorWidget(args.errorText),
  );
}

/// The production application shell and its process-level desktop listeners.
class MyApp extends StatefulWidget {
  /// Builds routes without accessing a wallet from this widget constructor.
  const MyApp({super.key});

  @override
  State<StatefulWidget> createState() {
    return _MyAppState();
  }
}

class _MyAppState extends State<MyApp> with WindowListener, TrayListener {
  @override
  void initState() {
    windowManager.addListener(this);
    trayManager.addListener(this);
    unawaited(initPlatformState());
    super.initState();
  }

  // Platform messages are asynchronous, so we initialize in an async method
  Future<void> initPlatformState() async {
    kLocalIpAddress = await NetworkUtils.getLocalIpAddress(
      InternetAddressType.IPv4,
    );

    if (!mounted) return;
  }

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: <SingleChildWidget>[
        BlocProvider<LatestTransactionsBloc>(
          create: (_) => sl.get<LatestTransactionsBloc>()
            ..add(
              InfiniteListRequested(
                address: Address.parse(kSelectedAddress!),
              ),
            ),
        ),
        BlocProvider<PendingTransactionsBloc>(
          create: (_) => sl.get<PendingTransactionsBloc>()
            ..add(
              InfiniteListRequested(
                address: Address.parse(kSelectedAddress!),
              ),
            ),
        ),
        BlocProvider<SendTransactionBloc>(
          create: (_) => SendTransactionBloc(),
        ),
        BlocProvider<MultipleBalanceBloc>(
          create: (_) => sl.get<MultipleBalanceBloc>(),
        ),
        BlocProvider<AllTokensBloc>(
          create: (_) => AllTokensBloc(zenon: zenon!)
            ..add(
              const AllTokensRequested(),
            ),
        ),
        BlocProvider<PlasmaStatsBloc>(
          create: (_) => PlasmaStatsBloc(zenon: zenon!)
            ..add(
              const InfiniteListRequested(),
            ),
        ),
      ],
      child: MultiProvider(
        providers: <SingleChildWidget>[
          ChangeNotifierProvider<SelectedAddressNotifier>(
            create: (_) => SelectedAddressNotifier(),
          ),
          BlocProvider<PlasmaBeneficiaryAddressCubit>(
            create: (_) => PlasmaBeneficiaryAddressCubit(),
          ),
          ChangeNotifierProvider<PlasmaGeneratedNotifier>(
            create: (_) => PlasmaGeneratedNotifier(),
          ),
          ChangeNotifierProvider<TextScalingNotifier>(
            create: (_) => TextScalingNotifier(),
          ),
          ChangeNotifierProvider<AppThemeNotifier>(
            create: (_) => AppThemeNotifier(),
          ),
          // Starts in the saved language: the preferences are open before
          // runApp, and waiting for InitUtils.initApp would show the first
          // frames in the system's language and direction.
          ChangeNotifierProvider<LocaleNotifier>(
            create: (_) => LocaleNotifier(WidgetUtils.savedLanguage()),
          ),
          ChangeNotifierProvider<ValueNotifier<List<String>>>(
            create: (_) => ValueNotifier<List<String>>(
              <String>[],
            ),
          ),
          Provider<LockBloc>(
            create: (_) => LockBloc(),
            builder: (BuildContext context, Widget? child) {
              return Consumer2<AppThemeNotifier, LocaleNotifier>(
                builder:
                    (
                      _,
                      AppThemeNotifier appThemeNotifier,
                      LocaleNotifier localeNotifier,
                      _,
                    ) {
                      final LockBloc lockBloc = Provider.of<LockBloc>(
                        context,
                        listen: false,
                      );
                      return OverlaySupport(
                        child: Listener(
                          onPointerSignal: (PointerSignalEvent event) {
                            if (event is PointerScrollEvent) {
                              lockBloc.addEvent(LockEvent.resetTimer);
                            }
                          },
                          onPointerCancel: (_) =>
                              lockBloc.addEvent(LockEvent.resetTimer),
                          onPointerDown: (_) =>
                              lockBloc.addEvent(LockEvent.resetTimer),
                          onPointerHover: (_) =>
                              lockBloc.addEvent(LockEvent.resetTimer),
                          onPointerMove: (_) =>
                              lockBloc.addEvent(LockEvent.resetTimer),
                          onPointerUp: (_) =>
                              lockBloc.addEvent(LockEvent.resetTimer),
                          child: MouseRegion(
                            onEnter: (_) =>
                                lockBloc.addEvent(LockEvent.resetTimer),
                            onExit: (_) =>
                                lockBloc.addEvent(LockEvent.resetTimer),
                            child: KeyboardListener(
                              focusNode: FocusNode(),
                              onKeyEvent: (KeyEvent event) {
                                lockBloc.addEvent(LockEvent.resetTimer);
                              },
                              child: Layout(
                                child: MaterialApp(
                                  title: 's y r i u s',
                                  navigatorKey: globalNavigatorKey,
                                  debugShowCheckedModeBanner: false,
                                  theme: AppTheme.lightTheme,
                                  darkTheme: AppTheme.darkTheme,
                                  themeMode: appThemeNotifier.currentThemeMode,
                                  initialRoute: SplashScreen.route,
                                  scrollBehavior: RemoveOverscrollEffect(),
                                  // The app is on material_ui; window_manager,
                                  // lottie and expandable still build on the
                                  // SDK's Material, which looks up its own
                                  // Theme. The bridge hands them this one.
                                  builder:
                                      (BuildContext context, Widget? child) =>
                                          // Unmigrated dependencies still read
                                          // the SDK theme via this bridge.
                                          // ignore: deprecated_member_use
                                          MaterialUiCompatibilityBridge(
                                            child: AppWindowFrame(
                                              child: child!,
                                            ),
                                          ),
                                  // Null follows the system; the callback maps
                                  // either to one of the five, else English.
                                  // The delegates carry the framework's own
                                  // strings and right-to-left for Arabic.
                                  locale: localeNotifier.locale,
                                  localeListResolutionCallback:
                                      resolveAppLocale,
                                  localizationsDelegates:
                                      appLocalizationsDelegates,
                                  supportedLocales:
                                      AppLocalizations.supportedLocales,
                                  routes: <String, WidgetBuilder>{
                                    AccessWalletScreen.route:
                                        (BuildContext context) =>
                                            const AccessWalletScreen(),
                                    SplashScreen.route:
                                        (BuildContext context) =>
                                            const SplashScreen(),
                                    MainAppContainer.route:
                                        (BuildContext context) =>
                                            const MainAppContainer(),
                                    NodeManagementScreen.route: (_) =>
                                        const NodeManagementScreen(),
                                  },
                                  onGenerateRoute: _buildErrorRoute,
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
              );
            },
          ),
        ],
      ),
    );
  }

  @override
  Future<void> onWindowClose() async {
    final bool windowMaximized = await windowManager.isMaximized();
    await sharedPrefsService!.put(
      kWindowMaximizedKey,
      windowMaximized,
    );

    if (!windowMaximized) {
      final Size windowSize = await windowManager.getSize();
      await sharedPrefsService!.put(
        kWindowSizeWidthKey,
        windowSize.width,
      );
      await sharedPrefsService!.put(
        kWindowSizeHeightKey,
        windowSize.height,
      );

      final Offset windowPosition = await windowManager.getPosition();
      await sharedPrefsService!.put(
        kWindowPositionXKey,
        windowPosition.dx,
      );
      await sharedPrefsService!.put(
        kWindowPositionYKey,
        windowPosition.dy,
      );
    }

    sl<Zenon>().wsClient.stop();
    unawaited(
      Future<void>.delayed(const Duration(seconds: 60)).then((_) => exit(0)),
    );
    await NodeUtils.closeEmbeddedNode();
    await sl.reset();
    super.onWindowClose();
    deactivate();
    dispose();
    exit(0);
  }

  @override
  void onTrayIconMouseDown() {
    unawaited(trayManager.popUpContextMenu());
  }

  @override
  void onTrayIconRightMouseDown() {}

  @override
  void onTrayIconRightMouseUp() {}

  @override
  Future<void> onTrayMenuItemClick(MenuItem menuItem) async {
    switch (menuItem.key) {
      case 'show_wallet':
        await windowManager.show();
      case 'hide_wallet':
        if (!await windowManager.isMinimized()) {
          await windowManager.minimize();
        }
      case 'exit':
        await windowManager.destroy();
      default:
        break;
    }
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    trayManager.removeListener(this);
    super.dispose();
  }
}
