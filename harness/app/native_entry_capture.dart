import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/rendering.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';
import 'package:zenon_syrius_wallet_flutter/blocs/auto_receive_tx_worker.dart';
import 'package:zenon_syrius_wallet_flutter/blocs/auto_unlock_htlc_worker.dart';
import 'package:zenon_syrius_wallet_flutter/handlers/htlc_swaps_handler.dart';
import 'package:zenon_syrius_wallet_flutter/main.dart' as app;
import 'package:zenon_syrius_wallet_flutter/services/htlc_swaps_service.dart';
import 'package:zenon_syrius_wallet_flutter/services/i_web3wallet_service.dart';
import 'package:zenon_syrius_wallet_flutter/services/shared_prefs_service.dart';
import 'package:zenon_syrius_wallet_flutter/utils/app_theme.dart' show AppTheme;
import 'package:zenon_syrius_wallet_flutter/utils/constants.dart';
import 'package:zenon_syrius_wallet_flutter/utils/entry_capture_source.dart';
import 'package:zenon_syrius_wallet_flutter/utils/notifiers/app_theme_notifier.dart';
import 'package:zenon_syrius_wallet_flutter/utils/reference_artwork_source.dart';
import 'package:zenon_syrius_wallet_flutter/utils/wallet_initialization.dart';
import 'package:zenon_syrius_wallet_flutter/utils/wallet_initialization_source.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

import 'capture_protocol.dart';
import 'client_window.dart';
import 'entry_capture_progress.dart';
import 'native_window_owner.dart';
import 'retained_renderer_frame.dart';

/// Captures original Welcome and one reversible incomplete Import draft.
/// Launch, Ready, existing wallets and other entry routes remain separate.
final class NativeEntryCapture {
  /// Reserve native startup before ordinary app.main can draw a frame.
  NativeEntryCapture({
    required this._window,
    required this._readView,
    required this._openImport,
    required this._prepareImport,
  }) {
    EntryCaptureRegistry.instance.observeHarnessEntry();
    _startup = _window.startup();
    _protocol = CaptureProtocol<Map<String, Object?>>(capture: _captureSource);
    unawaited(_startup.settled.then<void>((_) => _retainStartupOwners()));
  }

  final NativeWindowOwner _window;
  final RenderView Function() _readView;
  final Future<void> Function(VoidCallback admission) _openImport;
  final Future<void> Function(EntryImportDraftReceipt receipt) _prepareImport;
  late final NativeWindowCall<NativeWindowStartupReceipt> _startup;
  late final CaptureProtocol<Map<String, Object?>> _protocol;
  final List<_EntryScope> _scopes = <_EntryScope>[];
  final EntryEffectTraceEmitter? _effectTrace =
      Platform.isWindows &&
          Platform.environment['SYRIUS_CI_ENTRY_EFFECT_TRACE'] == 'true'
      ? EntryEffectTraceEmitter(stdout.writeln)
      : null;
  _EntryOwners? _owners;
  _EarlyEntryOwners? _early;
  Object? _startupCaptureError;
  StackTrace? _startupCaptureStack;
  int _captures = 0;

  void _retainStartupOwners() {
    try {
      final NativeWindowStartupReceipt? native = _startup.receipt;
      final EntryStartupReceipt? startup =
          EntryCaptureRegistry.instance.startup;
      if (native == null || !_window.isCurrent(native) || startup == null) {
        throw const CaptureRefused('original-entry-startup-unavailable');
      }
      _early = _EarlyEntryOwners.capture(startup, _readView());
      if (_early == null) {
        throw const CaptureRefused('original-entry-startup-too-late');
      }
    } on Object catch (error, stack) {
      _startupCaptureError = error;
      _startupCaptureStack = stack;
      _protocol.revoke();
    }
  }

  /// Fixed booleans disclose neither service identities nor profile content.
  Map<String, Object?> snapshot() {
    final EntryCaptureRegistry registry = EntryCaptureRegistry.instance;
    final NativeWindowStartupReceipt? native = _startup.receipt;
    return <String, Object?>{
      'nativeWindowReady': native != null && _window.isCurrent(native),
      'startupReady': registry.startup?.ready ?? false,
      'welcomeReady': registry.welcome?.ready ?? false,
      'held':
          _startupCaptureError != null ||
          _startupCaptureStack != null ||
          _protocol.heldUnknown ||
          _window.heldUnknown ||
          registry.held ||
          (_early != null && !_early!.current),
      'captures': _captures,
      if (_scopes.isNotEmpty) 'captureProgress': _scopes.last.progress,
    };
  }

  /// A fresh native callback verifies the original window after an outer
  /// harness window restoration; prior local receipts are insufficient.
  Future<Map<String, Object?>> verifyCurrent() async {
    final NativeWindowStartupReceipt? original = _startup.receipt;
    final _EntryOwners? owners = _owners;
    if (original == null ||
        owners == null ||
        _protocol.heldUnknown ||
        !owners.current ||
        !owners.welcome.ready ||
        !identical(_readView(), owners.view) ||
        _scopes.length != _captures ||
        !_scopes.every(
          (_EntryScope scope) => scope.restored && scope.current(),
        )) {
      throw const CaptureRefused('original-entry-verification-refused');
    }
    final NativeWindowFrameReceipt frame = await _window
        .requestFrame()
        .completion;
    if (!identical(frame.startup, original) ||
        !_window.isCurrent(original) ||
        !owners.current ||
        !owners.welcome.ready ||
        _protocol.heldUnknown) {
      throw const CaptureRefused('original-entry-verification-refused');
    }
    return <String, Object?>{
      ...snapshot(),
      'restorationVerified': true,
      'frameReady': true,
    };
  }

  /// One protocol instance retains all outcomes; a new request cannot recover
  /// an uncertain original by capturing another window, route or service set.
  Future<Map<String, Object?>> capture({
    required String screen,
    required String theme,
  }) async {
    if (!<String>{'welcome', 'import'}.contains(screen) ||
        !<String>{'dark', 'light'}.contains(theme)) {
      throw const CaptureRefused('unsupported-entry-capture');
    }
    final CaptureRun<Map<String, Object?>> run = _protocol.start(
      CapturePlan(
        screen: screen,
        theme: theme,
        mode: CaptureMode.entry,
        frame: CaptureFrameSpec(renderer: _readView()),
      ),
    );
    final CaptureOutcome<Map<String, Object?>> outcome = await run.completion;
    if (outcome.status != CaptureStatus.captured ||
        !outcome.restorationVerified ||
        outcome.result == null) {
      throw CaptureRefused(
        outcome.status == CaptureStatus.heldUnknown
            ? 'original-entry-scope-held'
            : 'original-entry-capture-refused',
      );
    }
    _captures++;
    return <String, Object?>{
      ...outcome.result!,
      'harnessMode': 'wallet',
      'captureMode': 'entry',
      'restorationVerified': true,
    };
  }

  CaptureSource<Map<String, Object?>>? _captureSource(CapturePlan plan) {
    final EntryCaptureRegistry registry = EntryCaptureRegistry.instance;
    final NativeWindowStartupReceipt? native = _startup.receipt;
    final EntryWelcomeReceipt? welcome = registry.welcome;
    final _EarlyEntryOwners? early = _early;
    if (native == null ||
        !_window.isCurrent(native) ||
        early == null ||
        !early.current ||
        welcome == null ||
        !welcome.ready ||
        !identical(welcome.startup, early.startup) ||
        !identical(plan.frame.renderer, _readView())) {
      return null;
    }
    final RenderView view = _readView();
    final ClientMetrics metrics = ClientMetrics(
      view.flutterView.physicalSize,
      view.flutterView.devicePixelRatio,
    );
    if (!metrics.matches(const Size(1280, 780))) return null;
    final _EntryOwners? owners = _owners ??= _EntryOwners.capture(
      early: early,
      welcome: welcome,
      view: view,
    );
    if (owners == null ||
        !owners.current ||
        !identical(owners.welcome, welcome)) {
      return null;
    }
    final _EntryScope scope = _EntryScope(this, owners, native, plan);
    _scopes.add(scope);
    return CaptureSource<Map<String, Object?>>(
      identity: scope,
      originalRoute: welcome.route,
      isCurrent: scope.current,
      prepare: scope.prepare,
      observe: scope.observe,
      shot: scope.shot,
      restore: scope.restore,
      isRestored: (_) => scope.restored,
    );
  }
}

/// Process owners are pinned on the actual first native frame, while the
/// original Splash is still current and before its initialization can begin.
/// A delayed callback refuses this boundary instead of adopting a later set.
final class _EarlyEntryOwners {
  _EarlyEntryOwners._(
    this.startup,
    this.view,
    this.theme,
    this.navigator,
    this.originals,
  ) : flutterView = view.flutterView;

  final EntryStartupReceipt startup;
  final RenderView view;
  final Object flutterView;
  final AppThemeNotifier theme;
  final NavigatorState navigator;
  final Map<String, Object?> originals;
  bool held = false;

  static _EarlyEntryOwners? capture(
    EntryStartupReceipt startup,
    RenderView view,
  ) {
    final Object owner = startup.owner;
    final NavigatorState? navigator = app.globalNavigatorKey.currentState;
    if (!startup.isCurrent ||
        startup.initializationStarted ||
        startup.initialization != null ||
        owner is! State ||
        !owner.mounted ||
        navigator == null ||
        !view.attached) {
      return null;
    }
    final Map<String, Object?> originals = readOwners();
    if (originals.values.any((Object? value) => value == null)) return null;
    final _EarlyEntryOwners early = _EarlyEntryOwners._(
      startup,
      view,
      Provider.of<AppThemeNotifier>(owner.context, listen: false),
      navigator,
      originals,
    );
    return early.current ? early : null;
  }

  static Map<String, Object?> readOwners() {
    final Zenon? sdk = app.zenon;
    return <String, Object?>{
      'sdk': sdk,
      'registered-sdk': app.sl<Zenon>(),
      'socket': sdk?.wsClient,
      'ledger': sdk?.ledger,
      'ledger-client': sdk?.ledger.client,
      'stats': sdk?.stats,
      'stats-client': sdk?.stats.client,
      'embedded-api': sdk?.embedded,
      'embedded-client': sdk?.embedded.client,
      'htlc-api': sdk?.embedded.htlc,
      'htlc-client': sdk?.embedded.htlc.client,
      'subscription-api': sdk?.subscribe,
      'subscription-client': sdk?.subscribe.client,
      'preferences': app.sharedPrefsService,
      'preferences-box': Hive.box<dynamic>(kSharedPrefsBox),
      'swap-store': app.htlcSwapsService,
      'registered-store': app.sl<HtlcSwapsService>(),
      'swap-handler': app.sl<HtlcSwapsHandler>(),
      'receive-worker': app.sl<AutoReceiveTxWorker>(),
      'unlock-worker': app.sl<AutoUnlockHtlcWorker>(),
      'web3': app.web3WalletService,
      'registered-web3': app.sl<IWeb3WalletService>(),
      'stopped-port': app.sl<ReceivePort>(instanceName: 'embeddedStoppedPort'),
      'stopped-stream': app.sl<Stream<dynamic>>(
        instanceName: 'embeddedStoppedStream',
      ),
    };
  }

  bool get current {
    if (held) return false;
    try {
      final Map<String, Object?> now = readOwners();
      final bool valid =
          identical(EntryCaptureRegistry.instance.startup, startup) &&
          !EntryCaptureRegistry.instance.held &&
          identical(app.globalNavigatorKey.currentState, navigator) &&
          view.attached &&
          identical(view.flutterView, flutterView) &&
          originals.entries.every(
            (MapEntry<String, Object?> item) =>
                identical(item.value, now[item.key]),
          );
      if (!valid) held = true;
      return valid;
    } on Object {
      held = true;
      return false;
    }
  }
}

/// These capabilities are captured once and only read. Starting the wallet
/// binding would create another operation; entry capture never calls start.
final class _EntryOwners {
  _EntryOwners._(
    this.early,
    this.welcome,
    this.view,
    this.wallet,
    this.preferences,
    this.box,
    this.theme,
    this.context,
    this.navigator,
    this.web3,
    this.port,
    this.stream,
  );

  final _EarlyEntryOwners early;
  final EntryWelcomeReceipt welcome;
  final RenderView view;
  final WalletInitializationBinding wallet;
  final SharedPrefsService preferences;
  final Box<dynamic> box;
  final AppThemeNotifier theme;
  final BuildContext context;
  final NavigatorState navigator;
  final IWeb3WalletService web3;
  final ReceivePort port;
  final Stream<dynamic> stream;

  static _EntryOwners? capture({
    required _EarlyEntryOwners early,
    required EntryWelcomeReceipt welcome,
    required RenderView view,
  }) {
    final WalletInitializationBinding? wallet =
        WalletInitializationSource.capture(creating: true);
    final SharedPrefsService? preferences = app.sharedPrefsService;
    final NavigatorState? navigator = app.globalNavigatorKey.currentState;
    final IWeb3WalletService? web3 = app.web3WalletService;
    final Object owner = welcome.owner;
    if (!early.current ||
        !identical(early.view, view) ||
        !identical(early.navigator, navigator) ||
        wallet == null ||
        preferences == null ||
        navigator == null ||
        web3 == null ||
        owner is! State ||
        !owner.mounted ||
        !Hive.isBoxOpen(kSharedPrefsBox) ||
        !app.sl.isRegistered<IWeb3WalletService>() ||
        !app.sl.isRegistered<ReceivePort>(
          instanceName: 'embeddedStoppedPort',
        ) ||
        !app.sl.isRegistered<Stream<dynamic>>(
          instanceName: 'embeddedStoppedStream',
        )) {
      return null;
    }
    final AppThemeNotifier theme = Provider.of<AppThemeNotifier>(
      owner.context,
      listen: false,
    );
    if (!identical(early.theme, theme)) return null;
    return _EntryOwners._(
      early,
      welcome,
      view,
      wallet,
      preferences,
      Hive.box<dynamic>(kSharedPrefsBox),
      theme,
      owner.context,
      navigator,
      web3,
      app.sl<ReceivePort>(instanceName: 'embeddedStoppedPort'),
      app.sl<Stream<dynamic>>(instanceName: 'embeddedStoppedStream'),
    );
  }

  bool get current =>
      early.current &&
      welcome.isAttached &&
      context.mounted &&
      wallet.isCurrent &&
      identical(EntryCaptureRegistry.instance.welcome, welcome) &&
      !EntryCaptureRegistry.instance.held &&
      identical(app.sharedPrefsService, preferences) &&
      box.isOpen &&
      Hive.isBoxOpen(kSharedPrefsBox) &&
      identical(Hive.box<dynamic>(kSharedPrefsBox), box) &&
      identical(Provider.of<AppThemeNotifier>(context, listen: false), theme) &&
      identical(app.globalNavigatorKey.currentState, navigator) &&
      identical(app.web3WalletService, web3) &&
      app.sl.isRegistered<IWeb3WalletService>() &&
      identical(app.sl<IWeb3WalletService>(), web3) &&
      app.sl.isRegistered<ReceivePort>(instanceName: 'embeddedStoppedPort') &&
      identical(
        app.sl<ReceivePort>(instanceName: 'embeddedStoppedPort'),
        port,
      ) &&
      app.sl.isRegistered<Stream<dynamic>>(
        instanceName: 'embeddedStoppedStream',
      ) &&
      identical(
        app.sl<Stream<dynamic>>(instanceName: 'embeddedStoppedStream'),
        stream,
      );
}

/// Each effect reserves a slot before invoking an original asynchronous call.
final class _EntryEffect {
  _EntryEffect(this.name);
  final Stopwatch elapsed = Stopwatch()..start();
  final String name;
  EntryCaptureCompletion? receipt;
  Object? error;
  StackTrace? stack;
}

final class _EntryScope {
  _EntryScope(this.host, this.owners, this.native, this.plan)
    : originalMode = owners.theme.currentThemeMode,
      originalTheme = owners.context
          .findAncestorWidgetOfExactType<Theme>()
          ?.data,
      preferenceExisted = owners.box.containsKey(kThemeModeKey),
      originalPreference = owners.box.get(kThemeModeKey),
      importsBefore = EntryCaptureRegistry.instance.imports.length;

  final NativeEntryCapture host;
  final _EntryOwners owners;
  final NativeWindowStartupReceipt native;
  final CapturePlan plan;
  final ThemeMode? originalMode;
  final ThemeData? originalTheme;
  final bool preferenceExisted;
  final Object? originalPreference;
  final int importsBefore;
  final List<_EntryEffect> effects = <_EntryEffect>[];
  final List<ReferenceArtworkFrame> artwork = <ReferenceArtworkFrame>[];
  EntryImportReceipt? imported;
  EntryImportDraftReceipt? preparedImport;
  RetainedRendererFrame? image;
  Size? outerSize;
  Offset? position;
  bool restoring = false;
  bool restored = false;
  bool held = false;

  // The last admitted scope is never replaced by requested values.
  Map<String, Object?>? get progress => projectEntryCaptureProgress(
    screen: plan.screen, theme: plan.theme, scopes: host._scopes.length,
    completedCaptures: host._captures,
    effects: <Map<String, Object?>>[
      for (final _EntryEffect effect in effects) <String, Object?>{
        'phase': effect.name,
        'future': effect.receipt?.status.name ?? 'not_returned',
        'failed': effect.error != null,
        'milliseconds': effect.elapsed.elapsedMilliseconds,
      },
    ],
    artworkCount: artwork.length, imageCreated: image != null,
    restoring: restoring, restored: restored, held: held,
  );

  void _traceEffect(_EntryEffect effect, String boundary) {
    host._effectTrace?.add(<String, Object?>{
      'schema': 1, 'screen': plan.screen, 'theme': plan.theme,
      'scopes': host._scopes.indexOf(this) + 1,
      'effects': effects.indexOf(effect) + 1, 'phase': effect.name,
      'boundary': boundary,
      'future': effect.receipt?.status.name ?? 'not_returned',
      'failed': effect.error != null,
      'milliseconds': effect.elapsed.elapsedMilliseconds,
    });
  }

  bool current() {
    if (held) return false;
    final bool valid =
        owners.current &&
        host._window.isCurrent(native) &&
        identical(host._readView(), owners.view) &&
        (restoring || artwork.every((ReferenceArtworkFrame frame) =>
            frame.isCurrent)) &&
        (restoring || image == null || image!.isCurrent);
    if (!valid) held = true;
    return valid;
  }

  void requireCurrent() {
    if (!current()) throw const CaptureRefused('original-entry-owner-changed');
  }

  Future<T> effect<T>(String name, Future<T> Function() call) async {
    requireCurrent();
    if (effects.length >= 192) {
      held = true;
      throw const CaptureRefused('original-entry-effect-limit');
    }
    final _EntryEffect effect = _EntryEffect(name);
    effects.add(effect);
    _traceEffect(effect, 'begin');
    try {
      requireCurrent();
      final Future<T> original = call();
      effect.receipt = EntryCaptureCompletion(original);
      _traceEffect(effect, 'returned');
      final T value = await original;
      requireCurrent();
      return value;
    } on Object catch (error, stack) {
      effect
        ..error = error
        ..stack = stack;
      rethrow;
    } finally {
      effect.elapsed.stop();
      _traceEffect(effect, 'ended');
    }
  }

  Future<void> nativeFrame() async {
    requireCurrent();
    final NativeWindowCall<NativeWindowFrameReceipt> call = host._window
        .requestFrame();
    final NativeWindowFrameReceipt receipt = await effect(
      'original-native-frame',
      () => call.completion,
    );
    if (!identical(receipt.startup, native)) {
      throw const CaptureRefused('original-native-frame-changed');
    }
  }

  Future<void> waitRoute(ModalRoute<dynamic> route) async {
    if (!entryRouteReady(route)) {
      final Completer<void> observed = Completer<void>();
      void observe(AnimationStatus _) {
        if (observed.isCompleted) return;
        if (!route.isCurrent) {
          observed.completeError(
            const CaptureRefused('original-entry-route-changed'),
          );
        } else if (entryRouteReady(route)) {
          observed.complete();
        }
      }

      if (!route.isCurrent) {
        throw const CaptureRefused('original-entry-route-changed');
      }
      route.animation?.addStatusListener(observe);
      route.secondaryAnimation?.addStatusListener(observe);
      try {
        observe(AnimationStatus.forward);
        await effect<void>('original-route-transition', () => observed.future);
      } finally {
        route.animation?.removeStatusListener(observe);
        route.secondaryAnimation?.removeStatusListener(observe);
      }
    }
    await effect(
      'original-route-frame',
      () => WidgetsBinding.instance.endOfFrame,
    );
    if (!entryRouteReady(route)) {
      throw const CaptureRefused('original-entry-route-changed');
    }
  }

  Future<void> waitTheme(ThemeData expected) async {
    // Observe painted ThemeData, including interpolated tokens. Elapsed time
    // or a matching brightness alone does not prove the requested colours.
    for (int frame = 0; frame < 60; frame++) {
      if (!owners.context.mounted) {
        throw const CaptureRefused('original-entry-owner-changed');
      }
      final ThemeData? actual = owners.context
          .findAncestorWidgetOfExactType<Theme>()
          ?.data;
      if (actual == expected) return;
      await effect(
        'original-theme-frame',
        () => WidgetsBinding.instance.endOfFrame,
      );
    }
    throw const CaptureRefused('original-painted-theme-unproven');
  }

  Future<void> writeTheme(Object? value, {required bool exists}) async {
    await effect<void>(
      'original-theme-write',
      () => exists
          ? owners.box.put(kThemeModeKey, value)
          : owners.box.delete(kThemeModeKey),
    );
    await effect<void>('original-theme-flush', owners.box.flush);
    if (owners.box.containsKey(kThemeModeKey) != exists ||
        owners.box.get(kThemeModeKey) != value) {
      throw const CaptureRefused('original-theme-write-unproven');
    }
  }

  Future<void> prepareArtwork() async {
    final Object owner = imported?.owner ?? owners.welcome.owner;
    if (owner is! State || !owner.mounted || !expectedRoute) {
      throw const CaptureRefused('original-entry-artwork-owner-unavailable');
    }
    ReferenceArtworkSource? asArtwork(Object value) =>
        value is ReferenceArtworkSource ? value : null;
    State<StatefulWidget>? asState(Object value) =>
        value is State<StatefulWidget> ? value : null;
    final List<ReferenceArtworkSource> sources = <ReferenceArtworkSource>[];
    int visited = 0;
    void visit(Element element) {
      if (++visited > 16384) {
        throw const CaptureRefused('original-entry-artwork-tree-limit');
      }
      if (element is StatefulElement) {
        final ReferenceArtworkSource? source = asArtwork(element.state);
        if (source != null) sources.add(source);
      }
      element.visitChildren(visit);
    }
    owner.context.visitChildElements(visit);
    sources.sort((ReferenceArtworkSource a, ReferenceArtworkSource b) =>
        a.referenceArtworkKind.index.compareTo(b.referenceArtworkKind.index));
    final List<ReferenceArtworkKind> expected = <ReferenceArtworkKind>[
      if (plan.screen == 'welcome') ReferenceArtworkKind.welcomeGlobe,
      ReferenceArtworkKind.entryField,
    ];
    if (sources.length != expected.length || artwork.isNotEmpty) {
      throw const CaptureRefused('original-entry-artwork-set-changed');
    }
    for (int index = 0; index < sources.length; index++) {
      final ReferenceArtworkSource source = sources[index];
      final Object generation = source.referenceArtworkGeneration;
      final State<StatefulWidget>? originalOwner = asState(source);
      if (originalOwner == null || !originalOwner.mounted ||
          source.referenceArtworkKind != expected[index]) {
        throw const CaptureRefused('original-entry-artwork-source-changed');
      }
      final Future<Object?>? original = source.referenceArtworkReadiness;
      if (source.referenceArtworkKind == ReferenceArtworkKind.welcomeGlobe &&
          original == null) {
        throw const CaptureRefused('original-entry-artwork-load-unavailable');
      }
      if (original != null) {
        await effect<Object?>('original-entry-artwork-ready', () => original);
      }
      if (!originalOwner.mounted || !expectedRoute ||
          !identical(source.referenceArtworkGeneration, generation)) {
        throw const CaptureRefused('original-entry-artwork-generation-changed');
      }
      final ReferenceArtworkFrame? frame = source.captureReferenceArtwork();
      if (frame == null) {
        throw const CaptureRefused('original-entry-artwork-sample-refused');
      }
      artwork.add(frame);
      if (!identical(frame.owner, source) ||
          !identical(frame.generation, generation) ||
          frame.kind != expected[index] || !frame.isCurrent) {
        throw const CaptureRefused('original-entry-artwork-binding-changed');
      }
    }
    await nativeFrame();
    if (!artwork.every((ReferenceArtworkFrame frame) => frame.observed)) {
      throw const CaptureRefused('original-entry-artwork-frame-unproven');
    }
  }

  Future<CapturePrepared> prepare(CaptureToken token) async {
    requireCurrent();
    if (!owners.welcome.ready ||
        (originalTheme != AppTheme.darkTheme &&
            originalTheme != AppTheme.lightTheme) ||
        originalPreference != null && originalPreference is! String) {
      throw const CaptureRefused('original-entry-startup-unproven');
    }
    outerSize = await effect('original-window-size', windowManager.getSize);
    position = await effect(
      'original-window-position',
      windowManager.getPosition,
    );
    if (await effect('original-window-visibility', windowManager.isMinimized)) {
      throw const CaptureRefused('original-entry-window-minimized');
    }
    final ThemeMode selected = plan.theme == 'dark'
        ? ThemeMode.dark
        : ThemeMode.light;
    await writeTheme(selected.toString(), exists: true);
    owners.theme.changeThemeMode(selected);
    await waitTheme(
      selected == ThemeMode.dark ? AppTheme.darkTheme : AppTheme.lightTheme,
    );
    if (plan.screen == 'import') {
      try {
        await effect<void>(
          'original-welcome-import',
          () => host._openImport(() {
            requireCurrent();
            if (!owners.welcome.ready ||
                EntryCaptureRegistry.instance.imports.length != importsBefore) {
              throw const CaptureRefused('original-welcome-action-changed');
            }
          }),
        );
      } finally {
        // The actual action reserved this route before Navigator.push. Retain
        // that same receipt even when the tap's asynchronous settle fails.
        final List<EntryImportReceipt> imports =
            EntryCaptureRegistry.instance.imports;
        if (imports.length == importsBefore + 1 &&
            identical(imports[importsBefore].welcome, owners.welcome)) {
          imported = imports[importsBefore];
        }
      }
      if (imported == null) {
        throw const CaptureRefused('original-import-navigation-unproven');
      }
      await waitRoute(imported!.route);
      if (!imported!.ready) {
        throw const CaptureRefused('original-empty-import-unproven');
      }
      final EntryImportDraftReceipt? draft = imported!.prepareIncompleteDraft();
      if (draft == null) {
        throw const CaptureRefused('original-import-preparation-refused');
      }
      preparedImport = draft;
      await effect<void>(
        'original-incomplete-import-input',
        () => host._prepareImport(draft),
      );
      if (!draft.isCurrent || imported!.ready || imported!.empty) {
        throw const CaptureRefused('original-incomplete-import-unproven');
      }
    } else {
      await waitRoute(owners.welcome.route);
    }
    await nativeFrame();
    if (!owners.context.mounted ||
        owners.theme.currentThemeMode != selected ||
        Theme.of(owners.context).brightness.name != plan.theme) {
      throw const CaptureRefused('original-entry-theme-unproven');
    }
    await prepareArtwork();
    image = await effect(
      'original-renderer-image',
      () => RetainedRendererFrame.capture(
        view: owners.view,
        expectedSize: const Size(1280, 780),
        sourceCurrent: () =>
            owners.current && host._window.isCurrent(native) &&
            expectedRoute && artwork.every((ReferenceArtworkFrame frame) =>
                frame.observed),
      ),
    );
    return CapturePrepared(
      token: token,
      source: this,
      route: imported?.route ?? owners.welcome.route,
    );
  }

  bool get expectedRoute =>
      preparedImport?.isCurrent ?? imported?.ready ?? owners.welcome.ready;

  Future<CaptureObservedFrame> observe(CaptureToken token) async {
    requireCurrent();
    await nativeFrame();
    final RetainedRendererFrame? retained = image;
    if (!owners.context.mounted ||
        !expectedRoute ||
        retained == null ||
        !retained.isCurrent ||
        owners.theme.currentThemeMode?.name != plan.theme ||
        Theme.of(owners.context).brightness.name != plan.theme) {
      throw const CaptureRefused('original-entry-frame-unproven');
    }
    return CaptureObservedFrame(
      token: token,
      source: this,
      route: imported?.route ?? owners.welcome.route,
      frame: CaptureFrameSpec(renderer: retained.view),
    );
  }

  Future<Map<String, Object?>> shot(CaptureToken token) async {
    requireCurrent();
    final RetainedRendererFrame? retained = image;
    if (!expectedRoute || retained == null) {
      throw const CaptureRefused('original-entry-image-unavailable');
    }
    final List<int> png = await effect(
      'original-png-encoding',
      retained.encodePng,
    );
    return <String, Object?>{
      'screen': plan.screen,
      'theme': plan.theme,
      'width': retained.width,
      'height': retained.height,
      'scale': 1,
      ...retained.metrics.toJson(),
      'referenceArtwork': artwork.map((ReferenceArtworkFrame frame) =>
          frame.observation).toList(growable: false),
      'png': base64Encode(png),
    };
  }

  Future<CaptureRestored> restore(CaptureToken token) async {
    requireCurrent();
    restoring = true;
    for (final ReferenceArtworkFrame frame in artwork) {
      if (!frame.restore()) {
        throw const CaptureRefused('original-entry-artwork-restore-refused');
      }
    }
    if (artwork.isNotEmpty) {
      await nativeFrame();
      if (!artwork.every((ReferenceArtworkFrame frame) => frame.restored)) {
        throw const CaptureRefused('original-entry-artwork-restore-unproven');
      }
    }
    final EntryImportReceipt? originalImport = imported;
    if (originalImport != null) {
      if (!(preparedImport?.canRestore ?? originalImport.isCurrent)) {
        throw const CaptureRefused('original-import-cannot-pop');
      }
      owners.navigator.pop<void>();
      await effect(
        'original-import-navigation-end',
        () => originalImport.navigation!.completion,
      );
      await effect(
        'original-import-route-end',
        () => originalImport.routeCompleted.completion,
      );
      final EntryCaptureCompletion? controller =
          originalImport.controllerDisposed;
      if (controller == null) {
        throw const CaptureRefused('original-import-disposal-unavailable');
      }
      await effect(
        'original-import-controller-end',
        () => controller.completion,
      );
      await waitRoute(owners.welcome.route);
      if (!owners.welcome.restoredAfter(originalImport)) {
        throw const CaptureRefused('original-import-cleanup-unproven');
      }
    } else if (!owners.welcome.ready ||
        EntryCaptureRegistry.instance.imports.length != importsBefore) {
      throw const CaptureRefused('original-welcome-restoration-unproven');
    }
    final RetainedRendererFrame? retained = image;
    if (retained != null) {
      await effect<void>('original-image-release', retained.release);
      if (!retained.released) {
        throw const CaptureRefused('original-image-release-unproven');
      }
    }
    await writeTheme(originalPreference, exists: preferenceExisted);
    owners.theme.changeThemeMode(originalMode);
    if (originalTheme == null) {
      throw const CaptureRefused('original-theme-unavailable');
    }
    await waitTheme(originalTheme!);
    await nativeFrame();
    final Size actualSize = await effect(
      'original-restored-window-size',
      windowManager.getSize,
    );
    final Offset actualPosition = await effect(
      'original-restored-window-position',
      windowManager.getPosition,
    );
    final bool minimized = await effect(
      'original-restored-window-visibility',
      windowManager.isMinimized,
    );
    restored =
        owners.context.mounted &&
        current() &&
        owners.welcome.ready &&
        owners.theme.currentThemeMode == originalMode &&
        owners.box.containsKey(kThemeModeKey) == preferenceExisted &&
        owners.box.get(kThemeModeKey) == originalPreference &&
        owners.context.findAncestorWidgetOfExactType<Theme>()?.data ==
            originalTheme &&
        actualSize == outerSize &&
        actualPosition == position &&
        !minimized &&
        artwork.every((ReferenceArtworkFrame frame) => frame.restored) &&
        (retained == null || retained.released);
    if (!restored) {
      throw const CaptureRefused('original-entry-restoration-unproven');
    }
    return CaptureRestored(
      token: token,
      source: this,
      originalRoute: owners.welcome.route,
    );
  }
}
