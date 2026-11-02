import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/screens/onboarding/entry_action_boundary.dart';
import 'package:zenon_syrius_wallet_flutter/screens/onboarding/import_wallet/import_draft.dart';
import 'package:zenon_syrius_wallet_flutter/screens/onboarding/import_wallet/import_file_offer.dart';
import 'package:zenon_syrius_wallet_flutter/screens/onboarding/import_wallet/import_file_picker.dart';
import 'package:zenon_syrius_wallet_flutter/screens/onboarding/welcome_surface.dart';
import 'package:zenon_syrius_wallet_flutter/screens/screens.dart';
import 'package:zenon_syrius_wallet_flutter/utils/entry_capture_source.dart';
import 'package:zenon_syrius_wallet_flutter/utils/navigation_utils.dart';
import 'package:zenon_syrius_wallet_flutter/utils/wallet_file.dart';

/// The welcome: the three ways into a wallet, one under the other, with
/// creating a new one as the main action.
class AccessWalletScreen extends StatefulWidget {
  /// Presents entry choices without eagerly mounting their wallet owners.
  const AccessWalletScreen({super.key});

  /// Stable route name for the existing wallet-entry destination.
  static const String route = 'access-wallet-screen';

  @override
  State<AccessWalletScreen> createState() => _AccessWalletScreenState();
}

class _AccessWalletScreenState extends State<AccessWalletScreen> {
  final Object _source = Object();
  final Completer<void> _disposed = Completer<void>();
  late final EntryCaptureCompletion _disposal = EntryCaptureCompletion(
    _disposed.future,
  );
  EntryWelcomeReceipt? _capture;
  ModalRoute<dynamic>? _captureRoute;
  bool _captureInvalid = false;

  bool get _canSelect =>
      mounted && (ModalRoute.of(context)?.isCurrent ?? false);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final ModalRoute<dynamic>? route = ModalRoute.of(context);
    if (route == null) return;
    if (_captureRoute != null && !identical(route, _captureRoute)) {
      _captureInvalid = true;
    }
    _captureRoute ??= route;
    final EntryWelcomeReceipt? receipt = EntryCaptureRegistry.instance
        .attachWelcome(
          owner: this,
          source: _source,
          route: route,
          disposed: _disposed.future,
          attached: () =>
              !_captureInvalid &&
              mounted &&
              identical(ModalRoute.of(context), route),
          current: () => _canSelect && identical(ModalRoute.of(context), route),
        );
    _capture ??= receipt;
  }

  @override
  Widget build(BuildContext context) => EntryActionBoundary(
    source: _source,
    builder: (_, EntryActionLease lease) => ImportFilePicker(
      lease: lease,
      probe: WalletFile.isKeyStoreFile,
      onSelected: (ImportFileSelection? selection) {
        if (_canSelect && lease.isCurrent) {
          _openImport(fileOffer: ImportFileOffer(selection));
        }
      },
      // Welcome exposes only the drop adapter, never the browse callback.
      onPickerFailed: () {},
      builder: (_, _, ImportDropWrapper wrap) => WelcomeSurface(
        source: _source,
        onSelected: _onSelected,
        wrapImportDrop: wrap,
      ),
    ),
  );

  void _onSelected(WelcomeDestination destination) {
    if (!_canSelect) return;
    // These owners generate seed material, clear address state or construct
    // Ledger access on mount. Only an admitted row press constructs one.
    switch (destination) {
      case WelcomeDestination.createWallet:
        NavigationUtils.push(
          context,
          const NewWalletSeedChoiceScreen(),
        );
      case WelcomeDestination.importWallet:
        _openImport();
      case WelcomeDestination.hardwareWallet:
        NavigationUtils.push(
          context,
          const HardwareWalletDeviceChoiceScreen(),
        );
    }
  }

  void _openImport({ImportFileOffer? fileOffer}) {
    if (!_canSelect) return;
    // Both entry actions reserve the genuine route before its owner mounts.
    final MaterialPageRoute<void> route = MaterialPageRoute<void>(
      builder: (_) => ImportWalletSeedChoiceScreen(fileOffer: fileOffer),
    );
    final EntryImportReceipt? receipt = EntryCaptureRegistry.instance
        .openingImport(welcome: _capture, route: route);
    try {
      final Future<void> original = Navigator.push<void>(context, route);
      receipt?.navigating(original);
    } on Object catch (error, stack) {
      receipt?.navigationFailed(error, stack);
      rethrow;
    }
  }

  @override
  void dispose() {
    // Keep a listener even when a replacement owner cannot enter the registry.
    unawaited(_disposal.completion);
    try {
      super.dispose();
      _disposed.complete();
    } on Object catch (error, stack) {
      _disposed.completeError(error, stack);
      rethrow;
    }
  }
}
