import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/blocs/blocs.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/help_widgets/originals_card.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/settings_widgets/apps.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/settings_widgets/settings_frame.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/widgets.dart';

/// Seven Settings sections, including the wallet's connected apps.
/// The last section chosen survives page changes within the session.
class SettingsTabChild extends StatefulWidget {
  /// Creates Settings with the existing wallet callbacks.
  const SettingsTabChild(
    this._onChangeAutoLockTime, {
    required this.onStepperNotificationSeeMorePressed,
    required this.onNodeChangedCallback,
    required this.scanForReceives,
    required this.onDeleteCache,
    required this.onResetWallet,
    this.onSend,
    this.senderIsCurrent,
    this.initialSection,
    this.railCollapse,
    super.key,
  });
  final FutureOr<void> Function() _onChangeAutoLockTime;

  /// Captures the root-owned receive source before the preference scan.
  final Future<void> Function() scanForReceives;

  /// Starts the root's exact owned maintenance question.
  final Future<void> Function(bool Function() isCurrent) onDeleteCache;

  /// Captures reset authority before covering the original Settings page.
  final Future<void> Function(bool Function() isCurrent) onResetWallet;

  /// Opens explicit Send after the captured contact updates the owned draft.
  final VoidCallback? onSend;

  /// The exact sender attachment, independently of section visibility.
  final bool Function()? senderIsCurrent;

  /// Opens the notification history for a multi-step operation.
  final VoidCallback onStepperNotificationSeeMorePressed;

  /// Returns to the connected wallet after a node changes.
  final VoidCallback onNodeChangedCallback;

  /// Opens a section directly, for a connected-site link or Go to action.
  final SettingsSectionId? initialSection;

  /// The shared rail choice controlled by Display.
  final RailCollapse? railCollapse;

  @override
  State<SettingsTabChild> createState() => _SettingsTabChildState();
}

class _SettingsTabChildState extends State<SettingsTabChild> {
  // The shell builds a page only while it is shown, so the section picked
  // last is kept here for the next visit.
  static SettingsSectionId _lastSection = SettingsSectionId.addresses;

  late SettingsSectionId _section = widget.initialSection ?? _lastSection;
  int _sectionEpoch = 0;
  final OriginalsController _originals = OriginalsController();

  final AccountChainStatsBloc _accountChainStatsBloc = AccountChainStatsBloc();

  @override
  void initState() {
    super.initState();
    _lastSection = _section;
  }

  @override
  Widget build(BuildContext context) {
    return SettingsFrame(
      selected: _section,
      onSelected: (SettingsSectionId section) {
        if (section == _section) return;
        setState(() {
          _sectionEpoch++;
          _section = section;
          _lastSection = section;
        });
      },
      child: _buildSection(_section),
    );
  }

  @override
  void didUpdateWidget(SettingsTabChild oldWidget) {
    super.didUpdateWidget(oldWidget);
    final SettingsSectionId? initial = widget.initialSection;
    if (initial != null && initial != oldWidget.initialSection) {
      if (initial != _section) _sectionEpoch++;
      _section = initial;
      _lastSection = initial;
    }
  }

  Widget _buildSection(SettingsSectionId section) {
    switch (section) {
      case SettingsSectionId.addresses:
        final int addressesEpoch = _sectionEpoch;
        bool addressesCurrent() =>
            mounted &&
            _section == SettingsSectionId.addresses &&
            addressesEpoch == _sectionEpoch;
        return Addresses(
          accountChainStatsBloc: _accountChainStatsBloc,
          isCurrent: addressesCurrent,
          senderIsCurrent: widget.senderIsCurrent,
          onSend: widget.onSend == null
              ? null
              : () {
                  if (addressesCurrent() &&
                      (widget.senderIsCurrent?.call() ?? true)) {
                    widget.onSend?.call();
                  }
                },
        );
      case SettingsSectionId.node:
        final int epoch = _sectionEpoch;
        return NodeSettingsSection(
          onNodeChangedCallback: widget.onNodeChangedCallback,
          isCurrent: () =>
              mounted &&
              _section == SettingsSectionId.node &&
              epoch == _sectionEpoch,
        );
      case SettingsSectionId.security:
        final int securityEpoch = _sectionEpoch;
        bool securityCurrent() =>
            mounted &&
            _section == SettingsSectionId.security &&
            securityEpoch == _sectionEpoch;
        return SecurityWidget(
          widget._onChangeAutoLockTime,
          onStepperNotificationSeeMorePressed:
              widget.onStepperNotificationSeeMorePressed,
          isCurrent: securityCurrent,
          onResetWallet: (bool Function() current) {
            if (securityCurrent() && current()) {
              unawaited(
                widget.onResetWallet(
                  () => securityCurrent() && current(),
                ),
              );
            }
          },
        );
      case SettingsSectionId.display:
        return DisplayWidget(railCollapse: widget.railCollapse);
      case SettingsSectionId.wallet:
        final int walletEpoch = _sectionEpoch;
        bool walletCurrent() =>
            mounted &&
            _section == SettingsSectionId.wallet &&
            walletEpoch == _sectionEpoch;
        return WalletOptions(
          isCurrent: walletCurrent,
          scanForReceives: widget.scanForReceives,
          senderIsCurrent: widget.senderIsCurrent,
          onDeleteCache: (bool Function() source) {
            if (walletCurrent() && source()) {
              unawaited(
                widget.onDeleteCache(
                  () => walletCurrent() && source(),
                ),
              );
            }
          },
          onResetWallet: (bool Function() source) {
            if (walletCurrent() && source()) {
              unawaited(
                widget.onResetWallet(
                  () => walletCurrent() && source(),
                ),
              );
            }
          },
        );
      case SettingsSectionId.apps:
        final int appsEpoch = _sectionEpoch;
        return AppsSettingsSection(
          isCurrent: () =>
              mounted &&
              _section == SettingsSectionId.apps &&
              appsEpoch == _sectionEpoch,
        );
      case SettingsSectionId.about:
        final int aboutEpoch = _sectionEpoch;
        bool aboutCurrent() =>
            mounted &&
            _section == SettingsSectionId.about &&
            aboutEpoch == _sectionEpoch;
        return ListenableBuilder(
          listenable: _originals,
          builder: (BuildContext context, _) => AboutSection(
            licencesTrailingBuilder: (_) => OriginalsDiscovery(
              controller: _originals,
              isCurrent: aboutCurrent,
            ),
            afterLicences: _originals.revealed
                ? OriginalsCard(isCurrent: aboutCurrent)
                : null,
          ),
        );
    }
  }

  @override
  void dispose() {
    _originals.dispose();
    _accountChainStatsBloc.dispose();
    super.dispose();
  }
}
