import 'dart:async';
import 'dart:io';

import 'package:app_links/app_links.dart';
import 'package:clipboard_watcher/clipboard_watcher.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:logging/logging.dart';
import 'package:material_ui/material_ui.dart';
import 'package:nested/nested.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';
import 'package:zenon_syrius_wallet_flutter/blocs/blocs.dart';
import 'package:zenon_syrius_wallet_flutter/handlers/htlc_swaps_handler.dart';
import 'package:zenon_syrius_wallet_flutter/main.dart';
import 'package:zenon_syrius_wallet_flutter/model/model.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/features.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/home/cubit/home_collection_controller.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/home/view/zap_sparks.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/plasma_owner/plasma_session.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/transfer/view/transfer_page.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/zap/zap.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/blocs/blocs.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/extensions/buildcontext_extension.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/go_to_palette.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/motion/motion.dart';
import 'package:zenon_syrius_wallet_flutter/seams/seam.dart';
import 'package:zenon_syrius_wallet_flutter/services/contacts_store.dart';
import 'package:zenon_syrius_wallet_flutter/utils/account_block_utils.dart';
import 'package:zenon_syrius_wallet_flutter/utils/address_utils.dart';
import 'package:zenon_syrius_wallet_flutter/utils/app_theme.dart';
import 'package:zenon_syrius_wallet_flutter/utils/clipboard_utils.dart';
import 'package:zenon_syrius_wallet_flutter/utils/constants.dart';
import 'package:zenon_syrius_wallet_flutter/utils/extensions.dart';
import 'package:zenon_syrius_wallet_flutter/utils/global.dart';
import 'package:zenon_syrius_wallet_flutter/utils/node_change.dart';
import 'package:zenon_syrius_wallet_flutter/utils/node_receive_binding.dart';
import 'package:zenon_syrius_wallet_flutter/utils/notification_utils.dart';
import 'package:zenon_syrius_wallet_flutter/utils/notifiers/balance_visibility.dart';
import 'package:zenon_syrius_wallet_flutter/utils/notifiers/default_address_notifier.dart';
import 'package:zenon_syrius_wallet_flutter/utils/notifiers/text_scaling_notifier.dart';
import 'package:zenon_syrius_wallet_flutter/utils/wallet_action_context.dart';
import 'package:zenon_syrius_wallet_flutter/utils/wallet_context_revision.dart';
import 'package:zenon_syrius_wallet_flutter/utils/wallet_flight_registry.dart';
import 'package:zenon_syrius_wallet_flutter/utils/wallet_maintenance.dart';
import 'package:zenon_syrius_wallet_flutter/utils/wallet_maintenance_binding.dart';
import 'package:zenon_syrius_wallet_flutter/utils/zts_utils.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/settings_widgets/settings_frame.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/reusable_widgets/startup_stage.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/shell/bell_panel.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/shell/go_to_catalog.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/shell/shell.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/shell/strip/peer_count.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/widgets.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

export 'package:zenon_syrius_wallet_flutter/widgets/shell/rail.dart'
    show RailCollapse, ShellRail;
export 'package:zenon_syrius_wallet_flutter/widgets/shell/tabs.dart';

/// The wallet session's pages, navigation and background status.
class MainAppContainer extends StatefulWidget {
  /// Creates the shell after unlock or completion of wallet setup.
  const MainAppContainer({
    super.key,
    this.redirectedFromWalletSuccess = false,
  });

  /// Starts the auto-lock timer when setup enters the shell directly.
  final bool redirectedFromWalletSuccess;

  /// The route retained when locking dismisses an open dialog.
  static const String route = 'main-app-container';

  @override
  State<MainAppContainer> createState() => _MainAppContainerState();
}

class _MainAppContainerState extends State<MainAppContainer>
    with ClipboardListener, WindowListener {
  late StreamSubscription<LockEvent> _lockBlockStreamSubscription;
  StreamSubscription<Uri>? _incomingLinkSubscription;
  StreamSubscription<WalletNotification>? _receiveNotificationsSubscription;
  late LockBloc _lockBloc;

  Timer? _navigateToLockTimer;
  bool _initialUriIsHandled = false;

  /// The page shown, as an index into [kTabs]. The rail and the page area
  /// listen to it, so a change of page rebuilds those two and not the shell.
  final ValueNotifier<int> _tabIndex = ValueNotifier<int>(
    kWalletInitCompleted ? 0 : kTabs.length - 1,
  );

  /// The page shown before the current one: where an unlock returns to.
  int _previousTabIndex = 0;

  /// Whether the wallet is locked, for the rail. It follows the auto-lock
  /// timer, which changes without a change of page (the countdown starting
  /// after a new wallet is made), so the rail cannot read it at build time.
  final ValueNotifier<bool> _locked = ValueNotifier<bool>(true);

  /// Zero is the cold-entry still; explicit lock or replay starts the well.
  final ValueNotifier<int> _lockReplay = ValueNotifier<int>(0);

  late final Listenable _railState = Listenable.merge(<Listenable>[
    _tabIndex,
    _locked,
    _bell,
  ]);

  final ValueNotifier<BellController?> _bell = ValueNotifier<BellController?>(
    null,
  );
  final ValueNotifier<bool> _noUnseen = ValueNotifier<bool>(false);
  final ValueNotifier<bool> _bellOpen = ValueNotifier<bool>(false);

  /// Whether the rail is collapsed to its icons. Held here and not in the
  /// rail because the shortcut that changes it is the shell's.
  final RailCollapse _railCollapse = RailCollapse();

  /// The send form's half-typed values, kept here because the page that
  /// shows them is disposed when another is opened. Cleared on a send and on
  /// lock.
  final SendDraftCubit _sendDraft = SendDraftCubit();
  final ZapDraftCubit _zapDraft = ZapDraftCubit();
  final TransferController _transfer = TransferController();
  final TokensPageController _tokensPage = TokensPageController();
  final SendTransactionBloc _sender = SendTransactionBloc();
  AutoReceiveTxWorker? _receiveWorker;
  Object? _receiveSenderLease;
  NodeReceiveBinding? _receiveFeed;
  bool _receiveReady = false;
  bool _receiveRearmQueued = false;
  final WalletMaintenanceOwner _maintenanceOwner = WalletMaintenanceOwner();
  StartupStageSession? _startup;
  bool _startupChecked = false;
  bool _startupInShell = false;
  int _pageEpoch = 0;
  final Map<(int, String, String), HomeCollectionController> _collections =
      <(int, String, String), HomeCollectionController>{};
  SelectedAddressContextListener? _selectionContext;
  final PageCommandController<NodesCommand> _nodesCommands =
      PageCommandController<NodesCommand>();
  final Map<Tabs, PageRefreshController> _pageRefresh =
      <Tabs, PageRefreshController>{};
  final Map<Tabs, PageDismissController> _pageDismiss =
      <Tabs, PageDismissController>{};

  late final PeerCount _peers = PeerCount(
    lookup: () async => (await zenon!.stats.networkInfo()).peers.length,
    isConnected: () => zenon!.wsClient.status() == WebsocketStatus.running,
  );
  StreamSubscription<NodeSyncStatusState>? _peerSyncSubscription;
  StreamSubscription<void>? _nodeChangeSubscription;

  final AppLinks _appLinks = AppLinks();
  final GlobalKey _pageContextKey = GlobalKey(
    debugLabel: 'Wallet page sources',
  );
  final NodeSyncStatusCubit _nodeSyncStatusCubit = NodeSyncStatusCubit(
    zenon: zenon!,
  );

  @override
  void initState() {
    _invalidateOwnedWork();
    _selectionContext = SelectedAddressContextListener(
      source: Provider.of<SelectedAddressNotifier>(context, listen: false),
      onChanged: _invalidateOwnedWork,
    );
    clipboardWatcher.addListener(this);
    windowManager.addListener(this);

    ClipboardUtils.toggleClipboardWatcherStatus();

    _previousTabIndex = _tabIndex.value;
    kCurrentPage = kWalletInitCompleted ? Tabs.dashboard : Tabs.lock;
    _initLockBlock();
    if (sl.isRegistered<AutoReceiveTxWorker>()) {
      final AutoReceiveTxWorker worker = sl<AutoReceiveTxWorker>();
      _receiveWorker = worker;
      final Object lease = worker.attachSender(_sender);
      _receiveSenderLease = lease;
      _receiveFeed = NodeReceiveBinding.attach(
        client: zenon!,
        worker: worker,
        senderLease: lease,
        isUnlocked: () =>
            mounted &&
            _receiveReady &&
            kWalletInitCompleted &&
            kCurrentPage != Tabs.lock &&
            !_isWalletLocked(),
      );
      WalletContextRevision.changes.addListener(_receiveContextChanged);
      _listenToAutoReceiveTxWorkerNotifications();
    }
    _handleIncomingLinks();
    unawaited(_handleInitialUri());
    _peerSyncSubscription = _nodeSyncStatusCubit.stream.listen((_) {
      unawaited(_peers.refresh());
    });
    _nodeChangeSubscription = NodeChange.stream.listen((_) {
      // Announce already revoked the context before its async event. A second
      // increment would revoke the committed transition's own receipt.
      _invalidateOwnedWork(contextAlreadyInvalidated: true);
      _bell.value?.setPrivate(value: true);
      _syncBell();
      _peers.reset();
      unawaited(_peers.refresh());
    });
    unawaited(_peers.refresh());

    super.initState();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _maintenanceOwner.attach(
      navigator: Navigator.of(context, rootNavigator: true),
      route: ModalRoute.of(context),
      sender: _sender,
      isCurrent: () => mounted,
    );
    if (_startupChecked) return;
    _startupChecked = true;
    final Object? arguments = ModalRoute.of(context)?.settings.arguments;
    if (arguments is! StartupStageSession) return;
    if (kTabs[_tabIndex.value] != Tabs.lock ||
        !arguments.claim(
          afterUnlock: _mainLockCallback,
          afterInit: _afterAppInitCallback,
          replay: _lockReplay,
        )) {
      arguments.dispose();
      return;
    }
    _startup = arguments;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !identical(_startup, arguments)) return;
      if (kTabs[_tabIndex.value] != Tabs.lock) {
        _closeStartup();
        return;
      }
      arguments.moveAuthToShell();
      setState(() => _startupInShell = true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && identical(_startup, arguments)) arguments.settle();
      });
    });
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
        BlocProvider<SendTransactionBloc>.value(value: _sender),
        BlocProvider<NodeSyncStatusCubit>.value(value: _nodeSyncStatusCubit),
        BlocProvider<SendDraftCubit>.value(value: _sendDraft),
        BlocProvider<ZapDraftCubit>.value(value: _zapDraft),
        BlocProvider<MultipleBalanceBloc>(
          create: (_) => sl.get<MultipleBalanceBloc>(),
        ),
        BlocProvider<PendingTransactionsBloc>(
          create: (_) => sl.get<PendingTransactionsBloc>()
            ..add(
              InfiniteListRequested(
                address: Address.parse(kSelectedAddress!),
              ),
            ),
        ),
        BlocProvider<PillarRewardsHistoryBloc>(
          create: (_) =>
              PillarRewardsHistoryBloc(
                zenon: zenon!,
              )..add(
                FetchRequestData(
                  address: Address.parse(kSelectedAddress!),
                ),
              ),
        ),
        BlocProvider<SentinelRewardsHistoryBloc>(
          create: (_) =>
              SentinelRewardsHistoryBloc(
                zenon: zenon!,
              )..add(
                FetchRequestData(
                  address: Address.parse(kSelectedAddress!),
                ),
              ),
        ),
        BlocProvider<StakingRewardsHistoryBloc>(
          create: (_) =>
              StakingRewardsHistoryBloc(
                zenon: zenon!,
              )..add(
                FetchRequestData(
                  address: Address.parse(kSelectedAddress!),
                ),
              ),
        ),
        BlocProvider<PillarsByOwnerBloc>(
          create: (_) =>
              PillarsByOwnerBloc(
                zenon: zenon!,
              )..add(
                FetchRequestData(
                  address: Address.parse(kSelectedAddress!),
                ),
              ),
        ),
        BlocProvider<AllTokensBloc>(
          create: (_) => AllTokensBloc(
            zenon: zenon!,
          )..add(const AllTokensRequested()),
        ),
        BlocProvider<DelegationStatsBloc>(
          create: (_) => DelegationStatsBloc(zenon: zenon!)
            ..add(FetchRequestData(address: Address.parse(kSelectedAddress!))),
        ),
      ],
      child: KeyedSubtree(
        key: _pageContextKey,
        child: Consumer<TextScalingNotifier>(
          // Built with the shell and handed to the builder, so a change of
          // text scale gives the tree a new MediaQuery and not a new shell.
          child: _buildShortcuts(child: _buildBody()),
          builder:
              (
                BuildContext context,
                TextScalingNotifier textScalingNotifier,
                Widget? child,
              ) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: TextScaler.linear(
                    textScalingNotifier.getTextScaleFactor(context),
                  ),
                ),
                child: child!,
              ),
        ),
      ),
    );
  }

  /// The rail, the page and the status strip.
  ///
  /// Nothing here calls setState: each part listens to what it shows (the
  /// page index, the lock, a cubit), so a notification, a new momentum or a
  /// change of page rebuilds that part and leaves the rest alone. The shell
  /// used to rebuild whole, pages included, for every notification.
  Widget _buildBody() {
    return Scaffold(
      body: Stack(
        children: <Widget>[
          ShellFrame(
            locked: _locked,
            rail: _buildRail(),
            page: _buildCurrentPage(),
            status: Consumer<SelectedAddressNotifier>(
              builder: (BuildContext context, _, _) => StreamBuilder<void>(
                stream: NodeChange.stream,
                builder: (BuildContext context, _) =>
                    ValueListenableBuilder<bool>(
                      valueListenable: _locked,
                      builder: (BuildContext context, bool locked, _) =>
                          StatusStrip(
                            syncCubit: _nodeSyncStatusCubit,
                            page: _tabIndex,
                            peers: _peers,
                            showFlight: !locked,
                            flight: WalletFlightRegistry.instance.forWallet(
                              getChainIdentifier(),
                              kDefaultAddressList.whereType<String>(),
                            ),
                          ),
                    ),
              ),
            ),
          ),
          Positioned.fill(
            child: ListenableBuilder(
              listenable: _railState,
              builder: (_, _) => ZapSparks(
                visible:
                    !_locked.value && kTabs[_tabIndex.value] == Tabs.dashboard,
              ),
            ),
          ),
          ValueListenableBuilder<bool>(
            valueListenable: _bellOpen,
            builder: (BuildContext context, bool open, _) {
              final AppTokens tokens = AppTokens.of(context);
              return PositionedDirectional(
                top: tokens.toastTop,
                end: tokens.toastEdge + (open ? tokens.bellPanelWidth : 0),
                child: ValueListenableBuilder<BellController?>(
                  valueListenable: _bell,
                  builder: (_, BellController? bell, _) => bell == null
                      ? const SizedBox.shrink()
                      : BellToast(controller: bell),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  /// The shell's keyboard shortcuts: the chord key (Ctrl; Cmd on macOS) with
  /// 1 to 8 opens the rail pages. L locks, K opens Go to, B changes the rail,
  /// R refreshes the active page, H changes balance visibility and comma opens
  /// Settings. Escape closes the nearest open page layer.
  ///
  /// They are a Shortcuts widget round the shell and not a global key
  /// handler, so they stop by themselves where they should: a dialog is
  /// another route and hears none of them. Locked, only the well's replay
  /// chord is exposed; it never unlocks the wallet.
  ///
  /// Nothing is taken from a text field. Every binding needs the chord key,
  /// and none of these chords edits text on the platform it is bound on
  /// (Ctrl+K kills a line on macOS, which is why macOS gets Cmd). AltGr,
  /// which Windows reports as Ctrl+Alt, does not match: the bindings want
  /// Ctrl alone.
  ///
  /// The FocusScope gives the shell a focus node of its own under the
  /// Shortcuts. Without it, focus falls back to the route's scope when a
  /// focused field is disposed by a change of page, and that scope is above
  /// the Shortcuts, so the keys would go dead until something was clicked.
  Widget _buildShortcuts({required Widget child}) {
    return ValueListenableBuilder<bool>(
      valueListenable: _locked,
      child: FocusScope(autofocus: true, child: child),
      builder: (BuildContext context, bool locked, Widget? child) => Shortcuts(
        shortcuts: locked ? kLockedShellShortcuts : kShellShortcuts,
        child: Actions(actions: _shellActions, child: child!),
      ),
    );
  }

  late final Map<Type, Action<Intent>> _shellActions = <Type, Action<Intent>>{
    OpenPageIntent: CallbackAction<OpenPageIntent>(
      onInvoke: (OpenPageIntent intent) {
        _onRailTap(intent.tab);
        return null;
      },
    ),
    OpenGoToIntent: CallbackAction<OpenGoToIntent>(
      onInvoke: (OpenGoToIntent intent) {
        unawaited(_openGoTo());
        return null;
      },
    ),
    ToggleRailIntent: CallbackAction<ToggleRailIntent>(
      onInvoke: (ToggleRailIntent intent) {
        _toggleRail();
        return null;
      },
    ),
    RefreshPageIntent: CallbackAction<RefreshPageIntent>(
      onInvoke: (_) {
        _refreshActivePage();
        return null;
      },
    ),
    ToggleBalancesIntent: CallbackAction<ToggleBalancesIntent>(
      onInvoke: (_) {
        if (!_isWalletLocked()) BalanceVisibility.instance.toggle();
        return null;
      },
    ),
    ReplayLockIntent: CallbackAction<ReplayLockIntent>(
      onInvoke: (_) {
        if (_isWalletLocked() && kTabs[_tabIndex.value] == Tabs.lock) {
          _lockReplay.value++;
        }
        return null;
      },
    ),
    DismissIntent: CallbackAction<DismissIntent>(
      onInvoke: (_) {
        if (!_isWalletLocked()) {
          final Tabs tab = kTabs[_tabIndex.value];
          if (!(_pageDismiss[tab]?.dismissLatest() ?? false)) {
            FocusManager.instance.primaryFocus?.unfocus();
          }
        }
        return null;
      },
    ),
  };

  bool _goToOpen = false;

  void _refreshActivePage() {
    if (_isWalletLocked()) return;
    final Tabs tab = kTabs[_tabIndex.value];
    if (tab == Tabs.transfer) {
      _transfer.refresh();
    } else {
      _pageRefresh[tab]?.refresh();
    }
  }

  /// Opens the "Go to" palette and shows the page chosen in it.
  Future<void> _openGoTo() async {
    if (_isWalletLocked() || _goToOpen) {
      return;
    }
    _goToOpen = true;
    final Object? wallet = kWalletFile;
    final Object? client = zenon;
    final String? node = kCurrentNode;
    final String? scope = bellScopeForWallet(
      getChainIdentifier(),
      kDefaultAddressList.whereType<String>(),
    );
    bool current() =>
        mounted &&
        !_isWalletLocked() &&
        wallet != null &&
        identical(wallet, kWalletFile) &&
        identical(client, zenon) &&
        node == kCurrentNode &&
        scope != null &&
        scope ==
            bellScopeForWallet(
              getChainIdentifier(),
              kDefaultAddressList.whereType<String>(),
            );
    try {
      final ShellGoToTarget? target = await showGoToPalette<ShellGoToTarget>(
        context: context,
        chordName: kChordName,
        entries: buildShellGoToCatalog(
          context: context,
          chordName: kChordName,
          addresses: kDefaultAddressList.whereType<String>(),
          labels: kAddressLabelMap,
          contacts: ContactsStore.instance.contacts,
        ),
      );
      if (target == null || !current()) return;
      runUnlessSeamed(
        seam: target.seam,
        action: () {
          switch (target.kind) {
            case ShellGoToKind.page:
              _onRailTap(target.page!);
            case ShellGoToKind.send:
              _openTransfer(TransferMode.send);
            case ShellGoToKind.receive:
              _openTransfer(TransferMode.receive);
            case ShellGoToKind.zap:
              // The seam above refuses indirect dispatch too.
              break;
            case ShellGoToKind.delegation:
              _navigateTo(Tabs.pillars);
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (current() && kTabs[_tabIndex.value] == Tabs.pillars) {
                  _nodesCommands.invoke(NodesCommand.delegate);
                }
              });
            case ShellGoToKind.deleteCache:
              unawaited(_confirmCacheDeletion(current));
            case ShellGoToKind.ownAddress:
              final String address = target.address!;
              final BuildContext? source = _pageContextKey.currentContext;
              if (source != null && kDefaultAddressList.contains(address)) {
                unawaited(
                  selectWalletAddress(
                    source,
                    address,
                    isCurrent: () =>
                        current() && kDefaultAddressList.contains(address),
                  ),
                );
              }
            case ShellGoToKind.contact:
              final String address = target.address!;
              if (ContactsStore.instance.byAddress(address)?.address ==
                      address &&
                  ContactsStore.normalize(address) == address) {
                _sendDraft.selectRecipient(address);
                _openTransfer(TransferMode.send);
              }
          }
        },
      );
    } finally {
      _goToOpen = false;
    }
  }

  Future<void> _confirmCacheDeletion(bool Function() current) async {
    await openWalletMaintenance(
      context: context,
      owner: _maintenanceOwner,
      kind: WalletMaintenanceKind.cache,
      sourceIsCurrent: current,
    );
  }

  Future<void> _confirmWalletReset(bool Function() current) =>
      openWalletMaintenance(
        context: context,
        owner: _maintenanceOwner,
        kind: WalletMaintenanceKind.reset,
        sourceIsCurrent: current,
      );

  /// The side rail of mockup B: its labels shown when it is open, its icons
  /// alone when it is collapsed. It sets its own width.
  Widget _buildRail() {
    return ListenableBuilder(
      listenable: _railState,
      builder: (BuildContext context, Widget? child) =>
          ValueListenableBuilder<bool>(
            valueListenable: _bell.value?.hasUnseen ?? _noUnseen,
            builder: (_, bool unseen, _) => ShellRail(
              collapse: _railCollapse,
              selected: kTabs[_tabIndex.value],
              locked: _locked.value,
              hasUnseen: unseen,
              onNotifications: () => unawaited(_openBell()),
              onSelected: _onRailTap,
            ),
          ),
    );
  }

  void _syncBell() {
    final List<String> addresses = kDefaultAddressList
        .whereType<String>()
        .toList();
    final String? scope = bellScopeForWallet(getChainIdentifier(), addresses);
    if (_isWalletLocked() ||
        kWalletFile == null ||
        scope == null ||
        !Hive.isBoxOpen(kNotificationsBox)) {
      _bell.value?.setPrivate(value: true);
      return;
    }
    if (_bell.value?.scope != scope) {
      final BellController? previous = _bell.value;
      previous?.setPrivate(value: true);
      _bell.value = BellController(
        history: HiveBellHistory(Hive.box<dynamic>(kNotificationsBox)),
        scope: scope,
        readSeen: (String key) {
          final Object? value = sharedPrefsService?.get('bell_seen:$key');
          return value is List
              ? value.whereType<String>().toList()
              : <String>[];
        },
        writeSeen: (String key, List<String> identities) async {
          await sharedPrefsService?.put('bell_seen:$key', identities);
        },
        approvals: web3WalletService?.pendingApprovals,
      );
      unawaited(previous?.close());
    }
    _bell.value?.setPrivate(value: false);
  }

  Future<void> _openBell() async {
    if (!mounted || _isWalletLocked() || _bellOpen.value) return;
    _syncBell();
    final BellController? bell = _bell.value;
    if (bell == null || bell.state.private) return;
    _bellOpen.value = true;
    try {
      await showBellPanel(context: context, controller: bell);
    } finally {
      if (mounted) _bellOpen.value = false;
    }
  }

  void _toggleRail() {
    // The same rule as [_onRailTap]: locked, nothing in the rail answers.
    if (_isWalletLocked()) {
      return;
    }
    _railCollapse.toggle();
  }

  void _onRailTap(Tabs tab) {
    // The rail takes no pointer and no focus while locked; this is the
    // same rule for any path that reaches it anyway.
    if (_isWalletLocked() || kTabs[_tabIndex.value] == tab) {
      return;
    }
    _navigateTo(tab);
    if (tab == Tabs.lock) {
      _onNavigateToLock();
    }
  }

  void _onNavigateToLock() {
    _receiveReady = false;
    _receiveFeed?.revoke();
    _lockReplay.value++;
    _invalidateOwnedWork();
    _bell.value?.setPrivate(value: true);
    // Lock revokes global access. Only the operation that returned from open
    // may release its original acquisition, including an in-flight SDK send.
    kWalletFile = null;
    _navigateToLockTimer?.cancel();
    _sendDraft.clear();
    _zapDraft.clear();
    _tokensPage
      ..selectFilter(TokensFilter.held)
      ..setQuery('')
      ..rememberScroll(0);
    _syncLocked();
  }

  bool _isWalletLocked() {
    return _navigateToLockTimer == null ||
        _navigateToLockTimer != null && !_navigateToLockTimer!.isActive;
  }

  /// Tells the rail after anything that starts or stops the auto-lock timer.
  void _syncLocked() {
    _locked.value = _isWalletLocked();
    _syncBell();
  }

  void _receiveContextChanged() {
    _receiveFeed?.revoke();
    if (_receiveRearmQueued) return;
    _receiveRearmQueued = true;
    scheduleMicrotask(() {
      _receiveRearmQueued = false;
      if (mounted) _receiveFeed?.rearm();
    });
  }

  Future<void> _scanForReceives() async {
    await _receiveFeed?.scanNow();
  }

  bool _ownsReceiveSender() {
    final Object? lease = _receiveSenderLease;
    return mounted &&
        lease != null &&
        (_receiveWorker?.ownsSender(lease) ?? false);
  }

  void _invalidateOwnedWork({bool contextAlreadyInvalidated = false}) {
    if (!contextAlreadyInvalidated) {
      WalletContextRevision.invalidate();
      if (sl.isRegistered<LatestTransactionsBloc>()) {
        sl.get<LatestTransactionsBloc>().invalidateReadContext();
      }
      if (sl.isRegistered<PowGeneratingStatusBloc>()) {
        sl.get<PowGeneratingStatusBloc>().invalidate();
      }
    }
    for (final HomeCollectionController controller in _collections.values) {
      controller.invalidate();
    }
  }

  HomeCollectionController? _collectionForCurrentWallet() {
    final String? scope = bellScopeForWallet(
      getChainIdentifier(),
      kDefaultAddressList.whereType<String>(),
    );
    final String? address = kSelectedAddress;
    if (scope == null || address == null || _isWalletLocked()) return null;
    return _collections.putIfAbsent(
      (getChainIdentifier(), scope, address),
      () => HomeCollectionController(
        sender: _sender,
        address: address,
        chainId: getChainIdentifier(),
        flight: WalletFlightRegistry.instance.forWallet(
          getChainIdentifier(),
          kDefaultAddressList.whereType<String>(),
        ),
      ),
    );
  }

  HomeCollectionSession? _captureCollectionSession() {
    final Zenon? client = zenon;
    final Object? file = kWalletFile;
    final String? address = kSelectedAddress;
    if (client == null ||
        file == null ||
        address == null ||
        _isWalletLocked()) {
      return null;
    }
    final int chain = getChainIdentifier();
    final int? nodeChain = kNodeChainId;
    final String? node = kCurrentNode;
    final String? path = kWalletPath;
    final List<String?> addresses = List<String?>.of(kDefaultAddressList);
    return HomeCollectionSession(
      address: address,
      chainId: chain,
      isCurrent: () =>
          mounted &&
          !_isWalletLocked() &&
          kWalletInitCompleted &&
          kCurrentPage != Tabs.lock &&
          identical(client, zenon) &&
          identical(file, kWalletFile) &&
          chain == getChainIdentifier() &&
          nodeChain == kNodeChainId &&
          node == kCurrentNode &&
          path == kWalletPath &&
          address == kSelectedAddress &&
          listEquals(addresses, kDefaultAddressList),
      buildBlock: (HomeRewardSource source) => switch (source) {
        HomeRewardSource.pillar => client.embedded.pillar.collectReward(),
        HomeRewardSource.sentinel => client.embedded.sentinel.collectReward(),
        HomeRewardSource.stake => client.embedded.stake.collectReward(),
      },
    );
  }

  /// The page for the selected rail item.
  ///
  /// Only that page is built. It used to be a TabBarView, which slid
  /// sideways through every page between two rail items and kept the
  /// neighbours built, each with its own fetches. The rail's destinations
  /// have no left-to-right order, so the new page fades in and rises a few
  /// pixels instead, and the old one is gone 100 ms after it is left.
  Widget _buildCurrentPage() {
    return ValueListenableBuilder<int>(
      valueListenable: _tabIndex,
      builder: (BuildContext context, int index, Widget? child) {
        final Widget page = KeyedSubtree(
          key: ValueKey<int>(index),
          child: _buildPageScope(kTabs[index]),
        );
        // Lock removes the outgoing financial page in this frame.
        return kTabs[index] == Tabs.lock ? page : RiseSwitcher(child: page);
      },
    );
  }

  Widget _buildPageScope(Tabs tab) => PageDismissScope(
    controller: _pageDismiss.putIfAbsent(tab, PageDismissController.new),
    child: PageRefreshScope(
      controller: _pageRefresh.putIfAbsent(tab, PageRefreshController.new),
      child: _buildPage(tab),
    ),
  );

  Widget _buildPage(Tabs tab) {
    return switch (tab) {
      Tabs.dashboard => DashboardTabChild(
        changePage: _navigateTo,
        openTransfer: _openTransfer,
        collectionOwner: _collectionForCurrentWallet,
        collectionSession: _captureCollectionSession,
      ),
      // Not const, so another page's constructor can change without
      // breaking the shell.
      Tabs.transfer => TransferTabChild(controller: _transfer),
      Tabs.pillars => NodesTabChild(
        commands: _nodesCommands,
        onStepperNotificationSeeMorePressed: () =>
            _navigateTo(Tabs.notifications),
      ),
      Tabs.sentinels => NodesTabChild(
        commands: _nodesCommands,
        initialTab: NodesTab.sentinels,
        onStepperNotificationSeeMorePressed: () =>
            _navigateTo(Tabs.notifications),
      ),
      Tabs.staking => const StakingTabChild(),
      Tabs.plasma => const PlasmaTabChild(),
      Tabs.tokens => _buildTokensPage(),
      Tabs.p2pSwap => P2pSwapTabChild(
        onStepperNotificationSeeMorePressed: () =>
            _navigateTo(Tabs.notifications),
      ),
      Tabs.walletConnect => _buildSettings(
        initialSection: SettingsSectionId.apps,
      ),
      Tabs.accelerator => AcceleratorTabChild(
        onStepperNotificationSeeMorePressed: () =>
            _navigateTo(Tabs.notifications),
      ),
      Tabs.notifications => NotificationsTabChild(controller: _bell.value),
      Tabs.settings => _buildSettings(),
      // Never shown: [_navigateTo] refuses the disabled tabs.
      Tabs.generation || Tabs.sync => const SizedBox.shrink(),
      Tabs.lock => _buildLockPage(),
    };
  }

  Widget _buildTokensPage() {
    final int epoch = _pageEpoch;
    return TokensTabChild(
      controller: _tokensPage,
      onSendToken: (String standard) => _openTokenTransfer(standard, epoch),
      onStepperNotificationSeeMorePressed: () =>
          _navigateTo(Tabs.notifications),
    );
  }

  void _openTokenTransfer(String standard, int epoch) {
    bool ownsPage() =>
        mounted &&
        epoch == _pageEpoch &&
        kTabs[_tabIndex.value] == Tabs.tokens &&
        !_isWalletLocked();
    if (!ownsPage()) return;
    try {
      if (TokenStandard.parse(standard).toString() != standard) return;
    } on Object {
      return;
    }
    final String? owner = kSelectedAddress;
    final WalletActionContext? action = owner == null
        ? null
        : WalletActionContext.capture(owner);
    if (action == null || !action.isCurrent) return;
    _sendDraft.selectToken(
      fromAddress: action.ownerAddress,
      tokenStandard: standard,
    );
    // Draft observers can synchronously revoke the original page or account.
    if (ownsPage() && action.isCurrent) _openTransfer(TransferMode.send);
  }

  Widget _buildLockPage() {
    final StartupStageSession? startup = _startup;
    if (startup != null && !startup.isClosed) {
      return _startupInShell ? startup.buildAuth() : const SizedBox.expand();
    }
    return LockTabChild(
      _mainLockCallback,
      _afterAppInitCallback,
      replay: _lockReplay,
    );
  }

  void _closeStartup() {
    final StartupStageSession? startup = _startup;
    _startup = null;
    _startupInShell = false;
    startup?.dispose();
  }

  Widget _buildSettings({SettingsSectionId? initialSection}) =>
      SettingsTabChild(
        _onChangeAutoLockTime,
        scanForReceives: _scanForReceives,
        senderIsCurrent: _ownsReceiveSender,
        onDeleteCache: _confirmCacheDeletion,
        onResetWallet: _confirmWalletReset,
        onSend: () => _openTransfer(TransferMode.send),
        initialSection: initialSection,
        railCollapse: _railCollapse,
        onStepperNotificationSeeMorePressed: () =>
            _navigateTo(Tabs.notifications),
        onNodeChangedCallback: () => _navigateTo(Tabs.dashboard),
      );

  void _openTransfer(TransferMode mode) {
    if (_isWalletLocked()) return;
    _transfer.value = mode;
    _navigateTo(Tabs.transfer);
  }

  Future<void> _mainLockCallback(String password) async {
    if (!mounted) return;
    _receiveReady = true;
    _startAutoLockTimer();
    if (kLastWalletConnectUriNotifier.value != null) {
      _navigateTo(Tabs.walletConnect);
    } else {
      _lockBloc.addEvent(LockEvent.navigateToPreviousTab);
    }
  }

  @override
  void dispose() {
    _receiveReady = false;
    WalletContextRevision.changes.removeListener(_receiveContextChanged);
    unawaited(_receiveFeed?.close());
    final Object? receiveLease = _receiveSenderLease;
    if (receiveLease != null) _receiveWorker?.detachSender(receiveLease);
    _closeStartup();
    _selectionContext?.close();
    _maintenanceOwner.beforeDispose();
    _invalidateOwnedWork();
    _maintenanceOwner.afterDispose();
    for (final HomeCollectionController controller in _collections.values) {
      controller.dispose();
    }
    unawaited(_sender.close());
    windowManager.removeListener(this);
    clipboardWatcher.removeListener(this);
    unawaited(_nodeSyncStatusCubit.close());
    unawaited(_sendDraft.close());
    unawaited(_zapDraft.close());
    _transfer.dispose();
    _tokensPage.dispose();
    _nodesCommands.dispose();
    for (final PageRefreshController controller in _pageRefresh.values) {
      controller.dispose();
    }
    for (final PageDismissController controller in _pageDismiss.values) {
      controller.dispose();
    }
    unawaited(_peerSyncSubscription?.cancel());
    unawaited(_nodeChangeSubscription?.cancel());
    _peers.dispose();
    _navigateToLockTimer?.cancel();
    unawaited(_lockBlockStreamSubscription.cancel());
    unawaited(_incomingLinkSubscription?.cancel());
    unawaited(_receiveNotificationsSubscription?.cancel());
    _tabIndex.dispose();
    _locked.dispose();
    _lockReplay.dispose();
    _railCollapse.dispose();
    final BellController? bell = _bell.value;
    bell?.setPrivate(value: true);
    unawaited(bell?.close());
    _bell.dispose();
    _noUnseen.dispose();
    _bellOpen.dispose();
    super.dispose();
  }

  void _onChangeAutoLockTime() {
    if (mounted) _lockBloc.addEvent(LockEvent.resetTimer);
  }

  void _afterAppInitCallback() {
    if (!mounted) return;
    _receiveReady = true;
    unawaited(_nodeSyncStatusCubit.fetchDataPeriodically());
    _startAutoLockTimer();
    if (kLastWalletConnectUriNotifier.value != null) {
      _navigateTo(Tabs.walletConnect);
    } else {
      _lockBloc.addEvent(LockEvent.navigateToDashboard);
    }

    _receiveContextChanged();
  }

  void _listenToAutoReceiveTxWorkerNotifications() {
    final AutoReceiveTxWorker? worker = _receiveWorker;
    if (worker == null || _receiveNotificationsSubscription != null) return;
    _receiveNotificationsSubscription = worker.stream.listen(
      (WalletNotification event) {
        if (_ownsReceiveSender() && _receiveReady && !_isWalletLocked()) {
          unawaited(sl<NotificationsBloc>().addNotification(event));
        }
      },
    );
  }

  /// Shows [page]. Every change of page goes through here: the rail, the
  /// lock, a deep link, a page's own "see more".
  ///
  /// This is what the TabController did, without its ticker: a page that is
  /// not in [kTabs] (WalletConnect without a project id) or is disabled is
  /// refused, and the page left is remembered for the next unlock.
  void _navigateTo(Tabs page) {
    if (page == Tabs.notifications) {
      unawaited(_openBell());
      return;
    }
    if (page == Tabs.lock) {
      _invalidateOwnedWork();
      _bell.value?.setPrivate(value: true);
    }
    final int index = kTabs.indexOf(page);
    if (index < 0 || index == _tabIndex.value || kDisabledTabs.contains(page)) {
      return;
    }
    _previousTabIndex = _tabIndex.value;
    _pageEpoch++;
    if (page != Tabs.lock) _closeStartup();
    final bool leavingLock = kCurrentPage == Tabs.lock;
    kCurrentPage = page;
    _tabIndex.value = index;
    if (leavingLock && page != Tabs.lock && _receiveReady) {
      _receiveContextChanged();
    }
    DappBridge.instance.selectionChanged();
  }

  void _initLockBlock() {
    _lockBloc = Provider.of<LockBloc>(context, listen: false);
    _lockBlockStreamSubscription = _lockBloc.stream.listen((LockEvent event) {
      if (!mounted) return;
      switch (event) {
        case LockEvent.countDown:
          if (kCurrentPage != Tabs.lock) {
            _startAutoLockTimer();
          }
        case LockEvent.navigateToDashboard:
          _navigateTo(Tabs.dashboard);
        case LockEvent.navigateToLock:
          if (Navigator.of(context).canPop()) {
            Navigator.popUntil(
              context,
              ModalRoute.withName(MainAppContainer.route),
            );
          }
          _onNavigateToLock();
          _navigateTo(Tabs.lock);
        case LockEvent.resetTimer:
          if (_navigateToLockTimer != null && _navigateToLockTimer!.isActive) {
            _startAutoLockTimer();
          }
        case LockEvent.navigateToPreviousTab:
          _navigateTo(kTabs[_previousTabIndex]);
      }
    });
    if (widget.redirectedFromWalletSuccess) {
      _receiveReady = true;
      _lockBloc.addEvent(LockEvent.countDown);
    }
  }

  /// Starts the auto-lock countdown afresh, and is the only place that
  /// makes its timer.
  ///
  /// The timer is periodic, so that a lock put off by an incoming swap is
  /// tried again one interval later. A periodic timer that is replaced
  /// without being cancelled keeps firing: the countdown, an unlock and the
  /// end of initialisation each used to assign a new one over the last, and
  /// the one left behind locked the wallet on its own, earlier schedule.
  /// Cancelling here first means there is never more than one.
  void _startAutoLockTimer() {
    final bool needsFeed = !(_navigateToLockTimer?.isActive ?? false);
    _navigateToLockTimer?.cancel();
    _navigateToLockTimer = Timer.periodic(
      Duration(minutes: kAutoLockWalletMinutes!),
      (Timer timer) {
        if (!sl<HtlcSwapsHandler>().hasActiveIncomingSwaps) {
          _lockBloc.addEvent(LockEvent.navigateToLock);
        }
      },
    );
    _syncLocked();
    if (_receiveReady && needsFeed) _receiveContextChanged();
  }

  void _handleIncomingLinks() {
    if (!kIsWeb && !Platform.isLinux) {
      _incomingLinkSubscription = _appLinks.uriLinkStream.listen(
        (Uri? uri) async {
          if (!await windowManager.isFocused() ||
              !await windowManager.isVisible()) {
            await windowManager.show();
          }
          if (!mounted) return;

          if (uri != null) {
            String uriRaw = uri.toString();

            Logger(
              'MainAppContainer',
            ).log(Level.INFO, 'Incoming link action: ${uri.host}');

            if (context.mounted) {
              if (uri.host == 'wc') {
                if (Platform.isWindows) {
                  uriRaw = uriRaw.replaceAll('/?', '?');
                }
                final String wcUri = Uri.decodeFull(
                  uriRaw.split('wc?uri=').last,
                );
                if (Uri.tryParse(wcUri) != null) {
                  await _updateWalletConnectUri(wcUri);
                }
                return;
              }

              // Deep link query parameters
              String queryAddress = '';
              String queryAmount = ''; // with decimals
              int queryDuration = 0; // in months
              String queryZTS = '';
              String queryPillarName = '';
              Token? token;

              if (uri.hasQuery) {
                uri.queryParametersAll.forEach((
                  String key,
                  List<String> value,
                ) async {
                  if (key == 'amount') {
                    queryAmount = value.first;
                  } else if (key == 'zts') {
                    queryZTS = value.first;
                  } else if (key == 'address') {
                    queryAddress = value.first;
                  } else if (key == 'duration') {
                    queryDuration = int.parse(value.first);
                  } else if (key == 'pillar') {
                    queryPillarName = value.first;
                  }
                });
              }

              if (queryZTS.isNotEmpty) {
                if (queryZTS == 'znn' || queryZTS == 'ZNN') {
                  token = kZnnCoin;
                } else if (queryZTS == 'qsr' || queryZTS == 'QSR') {
                  token = kQsrCoin;
                } else {
                  token = await zenon!.embedded.token.getByZts(
                    TokenStandard.parse(queryZTS),
                  );
                }
              }

              final SendTransactionBloc sendTransactionBloc = _sender;
              final DelegationBloc delegationBloc = DelegationBloc(
                accountBlockUtils: AccountBlockUtils(),
                zenon: zenon!,
              );
              if (context.mounted) {
                switch (uri.host) {
                  // A page asks for the wallet to be started or brought
                  // forward, then talks to it over the loopback channel.
                  case 'open':
                    break;
                  case 'transfer':
                    await sl<NotificationsBloc>().addNotification(
                      WalletNotification(
                        title: 'Transfer action detected',
                        timestamp: DateTime.now().millisecondsSinceEpoch,
                        details: 'Incoming transfer link received',
                        type: NotificationType.paymentReceived,
                      ),
                    );

                    if (!mounted) return;
                    if (kCurrentPage != Tabs.lock) {
                      _navigateTo(Tabs.transfer);

                      if (token != null) {
                        final bool? actionAccepted =
                            await showDialogWithNoAndYesOptions(
                              context: context,
                              title: 'Transfer action',
                              isBarrierDismissible: true,
                              content: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: <Widget>[
                                  Text(
                                    'Transfer $queryAmount ${token.symbol} '
                                    'from $kSelectedAddress to $queryAddress?',
                                  ),
                                ],
                              ),
                            );

                        if (!mounted || _isWalletLocked()) return;
                        if (actionAccepted ?? false) {
                          context.read<SendTransactionBloc>().add(
                            SendTransactionInitiate(
                              fromAddress: kSelectedAddress!,
                              toAddress: queryAddress,
                              amount: queryAmount.extractDecimals(
                                token.decimals,
                              ),
                              token: token,
                            ),
                          );
                        }
                      }
                    }
                  case 'stake':
                    await sl<NotificationsBloc>().addNotification(
                      WalletNotification(
                        title: 'Stake action detected',
                        timestamp: DateTime.now().millisecondsSinceEpoch,
                        details: 'Incoming stake link received',
                        type: NotificationType.paymentReceived,
                      ),
                    );

                    if (!mounted) return;
                    if (kCurrentPage != Tabs.lock) {
                      _navigateTo(Tabs.staking);

                      final bool? actionAccepted =
                          await showDialogWithNoAndYesOptions(
                            context: context,
                            title: 'Stake ${kZnnCoin.symbol} action',
                            isBarrierDismissible: true,
                            content: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
                                Text(
                                  'Stake $queryAmount ${kZnnCoin.symbol} '
                                  'for $queryDuration month(s)?',
                                ),
                              ],
                            ),
                          );

                      if (!mounted || _isWalletLocked()) return;
                      if (actionAccepted ?? false) {
                        final AccountBlockTemplate block = zenon!.embedded.stake
                            .stake(
                              queryDuration * stakeTimeUnitSec,
                              queryAmount.extractDecimals(kZnnCoin.decimals),
                            );

                        sendTransactionBloc.add(
                          SendTransactionInitiateFromBlock(
                            block: block,
                            fromAddress: kSelectedAddress!,
                            reasonForGeneratingPlasma:
                                context.l10n.plasmaPurposeCreateStake,
                          ),
                        );
                      }
                    }

                  case 'delegate':
                    await sl<NotificationsBloc>().addNotification(
                      WalletNotification(
                        title: 'Delegate action detected',
                        timestamp: DateTime.now().millisecondsSinceEpoch,
                        details: 'Incoming delegation link received',
                        type: NotificationType.paymentReceived,
                      ),
                    );

                    if (!mounted) return;
                    if (kCurrentPage != Tabs.lock) {
                      _navigateTo(Tabs.pillars);

                      final bool? actionAccepted =
                          await showDialogWithNoAndYesOptions(
                            context: context,
                            title: 'Delegate ${kZnnCoin.symbol} action',
                            isBarrierDismissible: true,
                            content: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
                                Text(
                                  'Delegate ${kZnnCoin.symbol} '
                                  'from $kSelectedAddress to $queryPillarName?',
                                ),
                              ],
                            ),
                          );

                      if (!mounted || _isWalletLocked()) return;
                      if (actionAccepted ?? false) {
                        delegationBloc.add(
                          DelegationRequested(
                            address: Address.parse(kSelectedAddress!),
                            pillarName: queryPillarName,
                          ),
                        );
                      }
                    }

                  case 'fuse':
                    await sl<NotificationsBloc>().addNotification(
                      WalletNotification(
                        title: 'Fuse ${kQsrCoin.symbol} action detected',
                        timestamp: DateTime.now().millisecondsSinceEpoch,
                        details: 'Incoming fuse link received',
                        type: NotificationType.paymentReceived,
                      ),
                    );

                    if (!mounted) return;
                    if (kCurrentPage != Tabs.lock) {
                      _navigateTo(Tabs.plasma);
                      final String? owner = kSelectedAddress;
                      final WalletActionContext? action = owner == null
                          ? null
                          : WalletActionContext.capture(owner);
                      final BigInt? amount = parsePlasmaQsr(queryAmount);
                      if (action == null ||
                          amount == null ||
                          amount <= BigInt.zero) {
                        return;
                      }
                      try {
                        Address.parse(queryAddress);
                      } on Object {
                        return;
                      }
                      final PlasmaSession session = PlasmaSession.wallet(
                        action,
                      );
                      final int pageEpoch = _pageEpoch;
                      bool isCurrent() =>
                          mounted &&
                          _pageEpoch == pageEpoch &&
                          kCurrentPage == Tabs.plasma &&
                          session.isCurrent;

                      final bool? actionAccepted =
                          await showDialogWithNoAndYesOptions(
                            context: context,
                            title: 'Fuse ${kQsrCoin.symbol} action',
                            isBarrierDismissible: true,
                            content: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
                                Text(
                                  'Fuse $queryAmount ${kQsrCoin.symbol} '
                                  'for $queryAddress?',
                                ),
                              ],
                            ),
                          );

                      if (!isCurrent()) return;
                      if (actionAccepted ?? false) {
                        final FusePlasmaBloc fusePlasmaBloc = FusePlasmaBloc(
                          accountBlockUtils: AccountBlockUtils(),
                          zenon: action.client,
                          zenonAddressUtils: ZenonAddressUtils(),
                          sender: _sender,
                        );
                        final Future<FusePlasmaState> completion =
                            fusePlasmaBloc.stream.firstWhere(
                              (FusePlasmaState state) =>
                                  state is FusePlasmaDone ||
                                  state is FusePlasmaFailure,
                            );
                        try {
                          fusePlasmaBloc.add(
                            FusePlasmaRequested(
                              beneficiaryAddress: queryAddress,
                              amount: amount,
                              session: session,
                              isCurrent: isCurrent,
                            ),
                          );
                          await completion;
                        } finally {
                          await fusePlasmaBloc.close();
                        }
                      }
                    }

                  case 'sentinel':
                    await sl<NotificationsBloc>().addNotification(
                      WalletNotification(
                        title: 'Deploy Sentinel action detected',
                        timestamp: DateTime.now().millisecondsSinceEpoch,
                        details: 'Incoming Sentinel link received',
                        type: NotificationType.paymentReceived,
                      ),
                    );

                    if (!mounted) return;
                    if (kCurrentPage != Tabs.lock) {
                      _navigateTo(Tabs.sentinels);
                    }

                  case 'pillar':
                    await sl<NotificationsBloc>().addNotification(
                      WalletNotification(
                        title: 'Deploy Pillar action detected',
                        timestamp: DateTime.now().millisecondsSinceEpoch,
                        details: 'Incoming Pillar link received',
                        type: NotificationType.paymentReceived,
                      ),
                    );

                    if (!mounted) return;
                    if (kCurrentPage != Tabs.lock) {
                      _navigateTo(Tabs.pillars);
                    }

                  default:
                    await sl<NotificationsBloc>().addNotification(
                      WalletNotification(
                        title: 'Incoming link detected',
                        timestamp: DateTime.now().millisecondsSinceEpoch,
                        details: 'Incoming action link received',
                        type: NotificationType.paymentReceived,
                      ),
                    );
                }
              }
              return;
            }
          }
        },
        onDone: () {
          Logger(
            'MainAppContainer',
          ).log(Level.INFO, '_handleIncomingLinks', 'done');
        },
        onError: (Object err) async {
          await NotificationUtils.sendNotificationError(
            err,
            'Handle incoming link failed',
          );
          Logger(
            'MainAppContainer',
          ).log(Level.WARNING, '_handleIncomingLinks', err);
          if (!mounted) return;
        },
      );
    }
  }

  Future<void> _handleInitialUri() async {
    if (!_initialUriIsHandled) {
      _initialUriIsHandled = true;
      try {
        final Uri? uri = await _appLinks.getInitialLink();
        if (uri != null) {
          Logger(
            'MainAppContainer',
          ).log(Level.INFO, 'Initial link action: ${uri.host}');
        }
        if (!mounted) return;
      } on PlatformException catch (e, stackTrace) {
        Logger('MainAppContainer').log(
          Level.WARNING,
          '_handleInitialUri PlatformException',
          e,
          stackTrace,
        );
      } on FormatException catch (e, stackTrace) {
        Logger('MainAppContainer').log(
          Level.WARNING,
          '_handleInitialUri FormatException',
          e,
          stackTrace,
        );
        if (!mounted) return;
      }
    }
  }

  @override
  Future<void> onClipboardChanged() async {
    final ClipboardData? newClipboardData = await Clipboard.getData(
      Clipboard.kTextPlain,
    );
    final String text = newClipboardData?.text ?? '';
    if (text.isNotEmpty && Uri.tryParse(text) != null) {
      // The clipboard watcher may emit the same change twice.
      if (kLastWalletConnectUriNotifier.value != text) {
        await _updateWalletConnectUri(text);
      }
    }
  }

  Future<void> _updateWalletConnectUri(String text) async {
    kLastWalletConnectUriNotifier.value = text;
    if (!_isWalletLocked()) {
      if (kCurrentPage != Tabs.walletConnect) {
        await sl<NotificationsBloc>().addNotification(
          WalletNotification(
            title: 'WalletConnect link detected. Open Connected sites.',
            timestamp: DateTime.now().millisecondsSinceEpoch,
            details:
                'A WalletConnect link has been copied to clipboard. '
                'Open Connected sites to review the connection request.',
            type: NotificationType.copiedToClipboard,
          ),
        );
        _navigateTo(Tabs.walletConnect);
      }
    }
  }
}
