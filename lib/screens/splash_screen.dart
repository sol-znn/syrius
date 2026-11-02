import 'dart:async';
import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/main.dart' show sharedPrefsService;
import 'package:zenon_syrius_wallet_flutter/model/model.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/extensions/buildcontext_extension.dart';
import 'package:zenon_syrius_wallet_flutter/screens/screens.dart';
import 'package:zenon_syrius_wallet_flutter/utils/entry_capture_source.dart';
import 'package:zenon_syrius_wallet_flutter/utils/utils.dart';
import 'package:zenon_syrius_wallet_flutter/utils/wallet_maintenance.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/reusable_widgets/startup_stage.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/widgets.dart';

/// Plays the original launch before the existing startup and routing work.
class SplashScreen extends StatefulWidget {
  /// Creates one startup session; rebuilding never starts initialization again.
  const SplashScreen({
    this.maintenance,
    this.resetStartup,
    super.key,
  });

  /// The initial route and the existing reset/cache re-entry route.
  static const String route = 'splash-screen';

  /// A one-use original request captured before its question or lock attempt.
  /// Boolean maintenance routes cannot recapture mutable global resources.
  final WalletMaintenanceRequest? maintenance;

  /// Fresh startup is a separate captured owner after positive reset cleanup.
  final WalletMaintenanceStartup? resetStartup;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  bool _initsScheduled = false;
  bool _maintenanceUnavailable = false;
  late final StartupStageSession _startup;
  final Object _entrySource = Object();
  EntryStartupReceipt? _entryCapture;

  @override
  void initState() {
    super.initState();
    _startup = StartupStageSession(
      onDone: _onFilmDone,
      authBuilder: (_, StartupStageSession session) =>
          widget.maintenance == null
          ? LockTabChild(
              session.unlock,
              session.initialized,
              replay: session.replay,
              startup: session,
            )
          : const SizedBox.shrink(),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _startup.show(context);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final ModalRoute<dynamic>? route = ModalRoute.of(context);
    if (widget.maintenance != null || route == null) return;
    final EntryStartupReceipt? receipt = EntryCaptureRegistry.instance
        .attachStartup(
          owner: this,
          source: _entrySource,
          route: route,
          startupOwner: _startup,
          detached: _startup.detached,
          cleanup: _startup.cleanup,
          current: () =>
              mounted &&
              route.isCurrent &&
              identical(ModalRoute.of(context), route),
        );
    _entryCapture ??= receipt;
  }

  void _onFilmDone() {
    if (!mounted || _initsScheduled) return;
    _initsScheduled = true;
    _startup.wait();
    // Optional art preloading cannot replace startup's actual result.
    unawaited(AppLottie.preload().onError<Object>((Object _, StackTrace _) {}));
    final Future<void> original = _splashInits();
    _entryCapture?.retainSplashOperation(original);
    unawaited(original);
  }

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: AppTokens.of(context).launchStageBackground,
    child: _maintenanceUnavailable
        ? Center(child: Text(context.l10n.walletSettingsUnavailable))
        : const SizedBox.expand(),
  );

  Future<void> _splashInits() async {
    try {
      final WalletMaintenanceRequest? request = widget.maintenance;
      if (request != null) {
        final WalletMaintenanceOutcome outcome = await request.filmDone(
          ModalRoute.of(context),
        );
        _startup.dispose();
        if (!mounted || !request.canNavigate) {
          return;
        }
        if (outcome.status == WalletMaintenanceStatus.completed) {
          if (request.kind == WalletMaintenanceKind.cache) {
            exit(0);
          }
          final WalletMaintenanceStartupReceipt? receipt = request
              .takeStartupReceipt(ModalRoute.of(context));
          final WalletMaintenanceStartup? startup = widget.resetStartup;
          if (receipt != null && startup != null && await startup(receipt)) {
            return;
          }
          if (mounted && request.canNavigate) {
            setState(() => _maintenanceUnavailable = true);
          }
        } else {
          setState(() => _maintenanceUnavailable = true);
        }
        return;
      }
      _entryCapture?.beginInitialization();
      try {
        final Future<void> original = InitUtils.initApp(context);
        _entryCapture?.initializing(original);
        await original;
      } on Object catch (error, stack) {
        _entryCapture?.initializationFailed(error, stack);
        rethrow;
      }
      if (!mounted) return;
      _navigateToNextScreen();
    } on Object catch (error) {
      if (!mounted) return;
      _startup.dispose();
      if (widget.maintenance != null) {
        // The exact original error remains in its owner; display no raw path.
        if (widget.maintenance!.canNavigate) {
          setState(() => _maintenanceUnavailable = true);
        }
        return;
      }
      Navigator.pushReplacementNamed<void, void>(
        context,
        SyriusErrorWidget.route,
        arguments: CustomSyriusErrorWidgetArguments(error.toString()),
      );
    }
  }

  void _navigateToNextScreen() {
    if (kWalletPath != null) {
      _checkForDefaultNode();
    } else {
      _startup.dispose();
      _entryCapture?.requestingWelcome();
      Navigator.pushReplacementNamed<void, void>(
        context,
        AccessWalletScreen.route,
        arguments: _entryCapture,
      );
    }
  }

  void _navigateToHomeScreen() {
    if (kWalletInitCompleted) _startup.dispose();
    Navigator.of(
      context,
      rootNavigator: true,
    ).pushReplacementNamed<void, void>(
      MainAppContainer.route,
      arguments: _startup.isClosed ? null : _startup,
    );
  }

  void _navigateToNodeManagementScreen() {
    _startup.dispose();
    Navigator.of(
      context,
      rootNavigator: true,
    ).pushReplacementNamed<void, void>(NodeManagementScreen.route);
  }

  void _checkForDefaultNode() =>
      sharedPrefsService!.get(
            kSelectedNodeKey,
          ) !=
          null
      ? _navigateToHomeScreen()
      : _navigateToNodeManagementScreen();

  @override
  void dispose() {
    if (!_startup.claimed) _startup.dispose();
    super.dispose();
  }
}
