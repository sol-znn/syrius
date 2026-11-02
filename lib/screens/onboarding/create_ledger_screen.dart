import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/blocs/ledger_wallet_file_bloc.dart';
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
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

/// Writes the hardware wallet's file, then asks which node to use.
class CreateLedgerWalletScreen extends StatefulWidget {
  /// Admits one encrypted reference for the originally selected device.
  const CreateLedgerWalletScreen(
    this.deviceInfo,
    this.password, {
    this.progressBarNumLevels = 4,
    super.key,
  });

  /// The original discovered hardware definition, never a replacement device.
  final WalletDefinition deviceInfo;

  /// The original password protecting the saved hardware reference.
  final String password;

  /// Existing flow length forwarded to the remaining node and Ready steps.
  final int progressBarNumLevels;

  @override
  State<CreateLedgerWalletScreen> createState() =>
      _CreateLedgerWalletScreenState();
}

class _CreateLedgerWalletScreenState extends State<CreateLedgerWalletScreen> {
  late final LedgerWalletFileBloc _ledgerWalletFileBloc;
  late final String _walletId;
  late final String _password;
  late final String? _walletName;
  late final int _steps;
  Object _source = Object();
  bool _requested = false;
  bool _replaced = false;
  bool _openingReady = false;

  @override
  void initState() {
    super.initState();
    _walletId = widget.deviceInfo.walletId;
    _password = widget.password;
    _walletName = widget.deviceInfo.walletName;
    _steps = widget.progressBarNumLevels;
    _ledgerWalletFileBloc = LedgerWalletFileBloc();
  }

  @override
  void didUpdateWidget(CreateLedgerWalletScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.deviceInfo.walletId != _walletId ||
        widget.password != _password ||
        widget.deviceInfo.walletName != _walletName ||
        widget.progressBarNumLevels != _steps) {
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
        _ledgerWalletFileBloc.getLedgerWalletPath(
          _walletId,
          _password,
          _walletName,
          sourceIsCurrent: () => mounted && !_replaced && lease.isCurrent,
        ),
      );
    });
  }

  @override
  void dispose() {
    _replaced = true;
    _source = Object();
    _ledgerWalletFileBloc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ValueListenableBuilder<int>(
        valueListenable: WalletContextRevision.changes,
        builder: (_, int revision, Widget? child) =>
            StreamBuilder<LedgerWalletFile?>(
              stream: _ledgerWalletFileBloc.stream,
              builder: (_, AsyncSnapshot<LedgerWalletFile?> snapshot) {
                if (!_replaced &&
                    snapshot.hasData &&
                    identical(kWalletFile, snapshot.data) &&
                    kWalletPath == snapshot.data!.walletPath &&
                    kWalletInitCompleted) {
                  final LedgerWalletFile original = snapshot.data!;
                  final WalletInitializationOutcome? outcome =
                      _ledgerWalletFileBloc.original?.outcome;
                  if (NodeTransitions.pending &&
                      outcome?.canShowQuarantinedReady == true &&
                      identical(outcome?.file, original)) {
                    return WalletSuccessScreen(
                      progressBarNumLevels: _steps,
                      originalFile: original,
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
