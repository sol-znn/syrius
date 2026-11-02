import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/blocs/blocs.dart';
import 'package:zenon_syrius_wallet_flutter/l10n/l10n.dart';
import 'package:zenon_syrius_wallet_flutter/screens/onboarding/entry_action_boundary.dart';
import 'package:zenon_syrius_wallet_flutter/screens/onboarding/onboarding_scaffold.dart';
import 'package:zenon_syrius_wallet_flutter/screens/screens.dart';
import 'package:zenon_syrius_wallet_flutter/utils/node_transition.dart';
import 'package:zenon_syrius_wallet_flutter/utils/utils.dart';
import 'package:zenon_syrius_wallet_flutter/utils/wallet_context_revision.dart';
import 'package:zenon_syrius_wallet_flutter/utils/wallet_file.dart';
import 'package:zenon_syrius_wallet_flutter/utils/wallet_initialization.dart';
import 'package:zenon_syrius_wallet_flutter/utils/wallet_ready_binding.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/widgets.dart';

/// Writes the new wallet file, then asks which node to use.
class CreateKeyStoreScreen extends StatefulWidget {
  /// Admits one creation from the original validated mnemonic and password.
  const CreateKeyStoreScreen(
    this.seed,
    this.password, {
    this.progressBarNumLevels = 5,
    this.importedWallet = false,
    super.key,
  });

  /// The original validated private mnemonic; never log or serialize publicly.
  final String seed;

  /// The original encryption password retained only by this creation owner.
  final String password;

  /// Existing flow length forwarded to the remaining node and Ready steps.
  final int progressBarNumLevels;

  /// Import has no seed quiz to claim completed on the ready screen.
  final bool importedWallet;

  @override
  State<CreateKeyStoreScreen> createState() => _CreateKeyStoreScreenState();
}

class _CreateKeyStoreScreenState extends State<CreateKeyStoreScreen> {
  late final KeyStoreFileBloc _keyStoreFileBloc;
  late final String _seed;
  late final String _password;
  late final int _steps;
  late final bool _imported;
  Object _source = Object();
  bool _requested = false;
  bool _replaced = false;
  bool _openingReady = false;

  @override
  void initState() {
    super.initState();
    _seed = widget.seed;
    _password = widget.password;
    _steps = widget.progressBarNumLevels;
    _imported = widget.importedWallet;
    _keyStoreFileBloc = KeyStoreFileBloc();
  }

  @override
  void didUpdateWidget(CreateKeyStoreScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.seed != _seed ||
        widget.password != _password ||
        widget.progressBarNumLevels != _steps ||
        widget.importedWallet != _imported) {
      _replaced = true;
      _source = Object();
    }
  }

  void _schedule(EntryActionLease lease) {
    if (_requested || _replaced) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _requested || _replaced || !lease.isCurrent) return;
      _requested = true;
      unawaited(
        _keyStoreFileBloc.getKeyStorePath(
          _seed,
          _password,
          sourceIsCurrent: () => mounted && !_replaced && lease.isCurrent,
        ),
      );
    });
  }

  @override
  void dispose() {
    _replaced = true;
    _source = Object();
    _keyStoreFileBloc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ValueListenableBuilder<int>(
        valueListenable: WalletContextRevision.changes,
        builder: (_, int revision, Widget? child) =>
            StreamBuilder<KeyStoreWalletFile?>(
              stream: _keyStoreFileBloc.stream,
              builder: (_, AsyncSnapshot<KeyStoreWalletFile?> snapshot) {
                if (!_replaced &&
                    snapshot.hasData &&
                    identical(kWalletFile, snapshot.data) &&
                    kWalletPath == snapshot.data!.walletPath &&
                    kWalletInitCompleted) {
                  final KeyStoreWalletFile original = snapshot.data!;
                  final WalletInitializationOutcome? outcome =
                      _keyStoreFileBloc.original?.outcome;
                  if (NodeTransitions.pending &&
                      outcome?.canShowQuarantinedReady == true &&
                      identical(outcome?.file, original)) {
                    return WalletSuccessScreen(
                      progressBarNumLevels: _steps,
                      originalFile: original,
                      imported: _imported,
                    );
                  }
                  // The committed file owns the picker and its consent dialog.
                  // The completed creation lease no longer owns route input.
                  return Padding(
                    padding: const EdgeInsets.only(top: 14),
                    child: Column(
                      children: <Widget>[
                        OnboardingStepPosition(
                          step: _steps - 1,
                          steps: _steps,
                        ),
                        Expanded(
                          child: NodeManagementScreen(
                            nodeConfirmationCallback: () {
                              if (!mounted ||
                                  _replaced ||
                                  _openingReady ||
                                  ModalRoute.of(context)?.isCurrent != true ||
                                  WalletReadyBinding.capture(
                                        expectedFile: original,
                                      )?.takeOpening() !=
                                      true) {
                                return;
                              }
                              _openingReady = true;
                              NavigationUtils.push(
                                context,
                                WalletSuccessScreen(
                                  progressBarNumLevels: _steps,
                                  originalFile: original,
                                  imported: _imported,
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  );
                } else if (_replaced || snapshot.hasError || snapshot.hasData) {
                  return SyriusErrorWidget(
                    currentL10n.walletCreationUnavailable,
                  );
                }
                return EntryActionBoundary(
                  source: _source,
                  builder: (BuildContext context, EntryActionLease lease) {
                    _schedule(lease);
                    return const Center(child: SyriusLoadingWidget());
                  },
                );
              },
            ),
      ),
    );
  }
}
