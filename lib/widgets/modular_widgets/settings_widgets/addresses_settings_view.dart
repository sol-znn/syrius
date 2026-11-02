import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/home/widgets/amount_text.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/send/cubit/send_draft_cubit.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/extensions/buildcontext_extension.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/disclosure.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/ltr.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/page/page_widgets.dart';
import 'package:zenon_syrius_wallet_flutter/services/contacts_store.dart';
import 'package:zenon_syrius_wallet_flutter/utils/address_utils.dart';
import 'package:zenon_syrius_wallet_flutter/utils/app_theme.dart';
import 'package:zenon_syrius_wallet_flutter/utils/format_utils.dart';
import 'package:zenon_syrius_wallet_flutter/utils/zts_utils.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/settings_widgets/addresses_settings_presenter.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

/// Fixed results of the original input predicates, without wallet values.
enum AddressesInputGate {
  /// No build has been observed.
  unknown,
  /// Every original input predicate passed.
  ready,
  /// The original backend is unavailable.
  backend,
  /// The original State is not mounted.
  mounted,
  /// The original view is hidden without a narrower retained condition.
  hidden,
  /// The original window is inactive.
  window,
  /// The original section callback refused input.
  section,
  /// The original focus ancestry refuses input.
  focus,
  /// The original route is not current.
  route,
  /// The original inherited ticker is disabled.
  ticker,
  /// The original backend is busy.
  busy,
}

/// A passive snapshot of the last build, without another authorization check.
abstract interface class AddressesInputSource {
  /// Reading this value does not evaluate callbacks, owners, routes or focus.
  AddressesInputGate get paintedInputGate;
}

/// Addresses presentation with supplied backend and navigation actions.
class AddressesSettingsView extends StatefulWidget {
  /// Requires an existing presenter and draft; creates no production services.
  const AddressesSettingsView({
    required this.presenter,
    required this.draft,
    required this.isCurrent,
    this.senderIsCurrent,
    this.onSend,
    this.hideBalances = false,
    super.key,
  });

  /// The external owner closes this disposable adapter.
  final AddressesSettingsPresenter presenter;

  /// The original session's recipient draft, never a transaction sender.
  final SendDraftCubit draft;

  /// Frozen page and section authority.
  final bool Function() isCurrent;

  /// The exact root sender attachment required for recipient handoff.
  final bool Function()? senderIsCurrent;

  /// Explicitly opens Send after the unchanged exact recipient is selected.
  final VoidCallback? onSend;

  /// Applies the wallet's shared amount-hiding choice.
  final bool hideBalances;

  @override
  State<AddressesSettingsView> createState() => _AddressesSettingsViewState();
}

class _AddressesSettingsViewState extends State<AddressesSettingsView>
    with WidgetsBindingObserver implements AddressesInputSource {
  final TextEditingController _label = TextEditingController();
  final TextEditingController _name = TextEditingController();
  final TextEditingController _contactAddress = TextEditingController();
  final DisclosureController _labelForm = DisclosureController();
  final DisclosureController _contactForm = DisclosureController();
  String? _editingAddress;
  Object? _editingLabelOwner;
  Contact? _editingContact;
  String? _labelError;
  String? _contactError;
  String? _actionError;
  int _epoch = 0;
  int _labelEpoch = 0;
  int _contactEpoch = 0;
  bool _visible = true;
  bool _windowActive = true;
  bool _attached = false;
  bool _sendHandedOff = false;
  FocusNode? _parentFocus;
  ModalRoute<dynamic>? _route;
  List<FocusNode> _observedFocus = <FocusNode>[];
  bool _ancestorFocusAllowed = true;
  bool _focusUpdateQueued = false;

  AddressesInputGate _currentInputGate = AddressesInputGate.unknown;
  AddressesInputGate _visibilityInputGate = AddressesInputGate.unknown;
  AddressesInputGate _paintedInputGate = AddressesInputGate.unknown;

  @override
  AddressesInputGate get paintedInputGate => _paintedInputGate;

  bool _inputPredicate(AddressesInputGate gate, bool allowed) {
    if (!allowed) _currentInputGate = gate;
    return allowed;
  }

  bool _visibilityPredicate(AddressesInputGate gate, bool allowed) {
    if (!allowed) _visibilityInputGate = gate;
    return allowed;
  }

  AddressesSettingsPresenter get _presenter => widget.presenter;
  AddressesSettingsBinding? get _binding => _presenter.binding;

  bool get _focusAllowsInput =>
      _parentFocus == null ||
      (_parentFocus!.descendantsAreFocusable &&
          _parentFocus!.ancestors.every(
            (FocusNode node) => node.descendantsAreFocusable,
          ));

  bool get _current {
    _currentInputGate = AddressesInputGate.ready;
    return _inputPredicate(AddressesInputGate.mounted, mounted) &&
        _inputPredicate(
          _visibilityInputGate == AddressesInputGate.ready
              ? AddressesInputGate.hidden : _visibilityInputGate,
          _visible,
        ) &&
        _inputPredicate(AddressesInputGate.window, _windowActive) &&
        _inputPredicate(AddressesInputGate.section, widget.isCurrent()) &&
        _inputPredicate(AddressesInputGate.focus, _focusAllowsInput) &&
        _inputPredicate(AddressesInputGate.route, _route?.isCurrent ?? true);
  }

  bool Function() _capture() {
    final int epoch = _epoch;
    final AddressesSettingsPresenter owner = _presenter;
    final SendDraftCubit draft = widget.draft;
    final bool Function() source = widget.isCurrent;
    bool revoked = false;
    return () =>
        !revoked &&
        !(revoked =
            !_current ||
            !source() ||
            epoch != _epoch ||
            !identical(owner, _presenter) ||
            !identical(draft, widget.draft));
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _parentFocus = Focus.maybeOf(context, scopeOk: true);
    _route = ModalRoute.of(context);
    _observeFocusAncestors();
    _syncVisibility();
  }

  void _observeFocusAncestors() {
    final FocusNode? parent = _parentFocus;
    final List<FocusNode> nodes = parent == null
        ? <FocusNode>[] : <FocusNode>[parent, ...parent.ancestors];
    _ancestorFocusAllowed = _focusAllowsInput;
    if (listEquals(nodes, _observedFocus)) return;
    for (final FocusNode node in _observedFocus) {
      node.removeListener(_ancestorFocusChanged);
    }
    _observedFocus = nodes;
    for (final FocusNode node in _observedFocus) {
      node.addListener(_ancestorFocusChanged);
    }
  }

  void _ancestorFocusChanged() {
    if (!mounted) return;
    final bool allowed = _focusAllowsInput;
    if (allowed == _ancestorFocusAllowed) return;
    _ancestorFocusAllowed = allowed;
    if (!allowed) {
      // Revoke old callbacks even when focus returns before the next frame.
      _visibilityInputGate = AddressesInputGate.focus;
      _setVisible(false);
    }
    if (_focusUpdateQueued) return;
    _focusUpdateQueued = true;
    scheduleMicrotask(() {
      _focusUpdateQueued = false;
      if (!mounted) return;
      // An inner Focus only inherits its nearest node. Outer page arrivals
      // must refresh visibility too, through all original input predicates.
      _observeFocusAncestors();
      _syncVisibility();
      setState(() {});
    });
  }

  void _syncVisibility() {
    _visibilityInputGate = AddressesInputGate.ready;
    _setVisible(
      _visibilityPredicate(AddressesInputGate.ticker,
          TickerMode.valuesOf(context).enabled) &&
          _visibilityPredicate(AddressesInputGate.window, _windowActive) &&
          _visibilityPredicate(
            AddressesInputGate.section, widget.isCurrent(),
          ) &&
          _visibilityPredicate(AddressesInputGate.focus, _focusAllowsInput) &&
          _visibilityPredicate(
            AddressesInputGate.route, _route?.isCurrent ?? true,
          ),
    );
    if (_visible && !_attached) {
      _attached = true;
      unawaited(_presenter.refresh());
    }
  }

  void _setVisible(bool visible) {
    if (!_visible && visible) _sendHandedOff = false;
    if (_visible && !visible) {
      _epoch++;
      _labelEpoch++;
      _contactEpoch++;
      _attached = false;
    }
    _visible = visible;
    _presenter.setVisible(visible: visible);
  }

  @override
  void didUpdateWidget(AddressesSettingsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.presenter, widget.presenter)) {
      oldWidget.presenter.setVisible(visible: false);
      _epoch++;
      _labelEpoch++;
      _contactEpoch++;
      _attached = false;
      _presenter.setVisible(visible: _visible);
      if (_visible) unawaited(_presenter.refresh());
    } else if (!oldWidget.isCurrent()) {
      _epoch++;
    } else if (!identical(oldWidget.draft, widget.draft)) {
      _epoch++;
      _sendHandedOff = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _windowActive = state == AppLifecycleState.resumed;
    _visibilityInputGate = AddressesInputGate.ready;
    _setVisible(
      _visibilityPredicate(AddressesInputGate.window, _windowActive) &&
          _visibilityPredicate(
            AddressesInputGate.section, widget.isCurrent(),
          ) &&
          _visibilityPredicate(AddressesInputGate.ticker,
              TickerMode.valuesOf(context).enabled) &&
          _visibilityPredicate(AddressesInputGate.focus, _focusAllowsInput) &&
          _visibilityPredicate(
            AddressesInputGate.route, _route?.isCurrent ?? true,
          ),
    );
    if (_visible && !_attached) {
      _attached = true;
      unawaited(_presenter.refresh());
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _epoch++;
    WidgetsBinding.instance.removeObserver(this);
    for (final FocusNode node in _observedFocus) {
      node.removeListener(_ancestorFocusChanged);
    }
    _observedFocus = <FocusNode>[];
    _label.dispose();
    _name.dispose();
    _contactAddress.dispose();
    _labelForm.dispose();
    _contactForm.dispose();
    super.dispose();
  }

  void _editLabel(String address, bool Function() current) {
    final AddressesSettingsBinding? owner = _binding;
    if (!current() ||
        owner == null ||
        !owner.ownsResources ||
        owner.busy ||
        !owner.members.contains(address)) {
      return;
    }
    setState(() {
      _labelEpoch++;
      _editingAddress = address;
      _editingLabelOwner = owner.labelOwner(address);
      _label.text = owner.labels[address] ?? '';
      _labelError = null;
      _labelForm.open();
    });
  }

  void _editContact(Contact? contact, bool Function() current) {
    final AddressesSettingsBinding? owner = _binding;
    if (!current() ||
        owner == null ||
        !owner.ownsResources ||
        owner.busy ||
        !owner.contactsAvailable ||
        (contact != null &&
            !identical(owner.contacts.byAddress(contact.address), contact))) {
      return;
    }
    setState(() {
      _contactEpoch++;
      _editingContact = contact;
      _name.text = contact?.name ?? '';
      _contactAddress.text = contact?.address ?? '';
      _contactError = null;
      _contactForm.open();
    });
  }

  Future<void> _saveLabel(bool Function() source) async {
    final AddressesSettingsBinding? owner = _binding;
    final String? address = _editingAddress;
    final String label = _label.text;
    final int epoch = _labelEpoch;
    bool current() => source() && epoch == _labelEpoch && _labelForm.isOpen;
    if (!current() || owner == null || address == null || owner.busy) return;
    final AddressesWriteOutcome result = await owner.rename(
      address,
      label,
      isCurrent: current,
      expectedOwner: _editingLabelOwner,
    );
    if (!current()) return;
    setState(() {
      _labelError = result.committed && result.error != null
          ? context.l10n.addressesSavedReopen
          : _error(result.error);
      if (result.error == null) {
        _labelForm.close();
        _labelEpoch++;
      }
    });
  }

  Future<void> _saveContact(bool Function() source) async {
    final AddressesSettingsBinding? owner = _binding;
    final String name = _name.text;
    final String address = _contactAddress.text;
    final Contact? expected = _editingContact;
    final int epoch = _contactEpoch;
    bool current() => source() && epoch == _contactEpoch && _contactForm.isOpen;
    if (!current() || owner == null || owner.busy) return;
    final AddressesWriteOutcome result = await owner.saveContact(
      name: name,
      address: address,
      expected: expected,
      isCurrent: current,
    );
    if (!current()) return;
    setState(() {
      _contactError = result.committed && result.error != null
          ? context.l10n.addressesSavedReopen
          : _error(result.error);
      if (result.error == null) {
        _contactForm.close();
        _contactEpoch++;
      }
    });
  }

  Future<void> _generate(bool Function() current) async {
    final AddressesSettingsBinding? owner = _binding;
    if (!current() || owner == null || !owner.ownsResources || owner.busy) {
      return;
    }
    setState(() => _actionError = null);
    final AddressesWriteOutcome result = await owner.generate(
      isCurrent: current,
    );
    if (!current()) return;
    if (result.error != null) {
      final Object? original = result.result;
      final bool uncertain =
          result.committed ||
          (original is AddressGenerationOutcome &&
              original.memberWrites.isNotEmpty);
      setState(
        () => _actionError = uncertain
            ? context.l10n.addressesGenerationUncertain
            : context.l10n.addressesGenerationFailed,
      );
    }
  }

  Future<void> _select(String address, bool Function() current) async {
    final AddressesSettingsBinding? owner = _binding;
    if (!current() ||
        owner == null ||
        owner.busy ||
        address == owner.selected) {
      return;
    }
    final AddressesWriteOutcome result = await owner.select(
      address,
      isCurrent: current,
    );
    if (current() && result.error != null) {
      setState(
        () => _actionError = result.committed
            ? context.l10n.addressesSavedReopen
            : context.l10n.addressesSaveFailed,
      );
    }
  }

  Future<void> _copy(
    String address,
    AddressesSettingsBinding owner,
    bool Function() current,
  ) async {
    if (!current() ||
        !owner.ownsResources ||
        !owner.members.contains(address)) {
      return;
    }
    try {
      await Clipboard.setData(ClipboardData(text: address));
    } on Object {
      if (current() && owner.ownsResources) {
        setState(() => _actionError = context.l10n.commonSomethingWentWrong);
      }
    }
  }

  void _send(
    Contact contact,
    bool Function() current, {
    required SendDraftCubit draft,
    required VoidCallback? open,
    required bool Function()? senderIsCurrent,
  }) {
    final AddressesSettingsBinding? owner = _binding;
    bool original() =>
        current() &&
        owner != null &&
        owner.ownsResources &&
        !owner.busy &&
        owner.contactsAvailable &&
        owner.canSend &&
        !draft.isClosed &&
        identical(draft, widget.draft) &&
        identical(open, widget.onSend) &&
        (senderIsCurrent?.call() ?? true) &&
        open != null &&
        identical(owner.contacts.byAddress(contact.address), contact) &&
        ContactsStore.normalize(contact.address) == contact.address;
    if (_sendHandedOff || !original()) return;
    _sendHandedOff = true;
    draft.selectRecipient(contact.address);
    // A synchronous draft observer can remove this contact or replace its page.
    if (original() && draft.state.recipient == contact.address) open!();
  }

  String? _error(Object? error) {
    if (error == null) return null;
    if (error is AddressesLabelException) {
      return switch (error.error) {
        AddressesLabelError.empty =>
          context.l10n.settingsAddressLabelEmptyError,
        AddressesLabelError.tooLong => context.l10n.addressesLabelTooLong,
        AddressesLabelError.taken =>
          context.l10n.settingsAddressLabelExistsNotificationTitle,
      };
    }
    if (error is ContactsException) {
      return switch (error.error) {
        ContactError.invalidAddress => context.l10n.addressesInvalidAddress,
        ContactError.emptyName => context.l10n.addressesNameEmpty,
        ContactError.nameTooLong => context.l10n.addressesNameTooLong,
        ContactError.nameTaken => context.l10n.addressesNameTaken,
        ContactError.addressTaken => context.l10n.addressesAddressTaken,
        ContactError.notFound ||
        ContactError.sourceChanged => context.l10n.addressesSaveFailed,
      };
    }
    return context.l10n.addressesSaveFailed;
  }

  @override
  Widget build(
    BuildContext context,
  ) => BlocBuilder<AddressesSettingsPresenter, AddressesSettingsState>(
    bloc: _presenter,
    builder: (BuildContext context, AddressesSettingsState state) {
      final AppTokens tokens = AppTokens.of(context);
      final AddressesSettingsBinding? owner = _binding;
      final bool available = state.available && (owner?.ownsResources ?? false);
      final bool inputCurrent = available && _current;
      final bool enabled = inputCurrent && !owner!.busy;
      _paintedInputGate = !available ? AddressesInputGate.backend
          : !inputCurrent ? _currentInputGate
          : enabled ? AddressesInputGate.ready : AddressesInputGate.busy;
      final bool contactsAvailable = available && owner!.contactsAvailable;
      final List<Contact> contacts = contactsAvailable
          ? owner.contacts.contacts
          : const <Contact>[];
      final String chainLabel = available
          ? owner!.labels[owner.selected] ?? owner.selected
          : context.l10n.settingsSectionAddresses;
      final AddressesAccount? selectedAccount = available
          ? state.balances[owner!.selected]
          : null;
      final bool Function() current = _capture();
      return SingleChildScrollView(
        key: const Key('addresses_settings_page'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _card(
              context,
              context.l10n.addressesYourAddresses,
              available ? owner!.members.length : null,
              _button(
                context,
                const Key('settings_add_address'),
                context.l10n.addressesAddAddress,
                enabled ? () => unawaited(_generate(current)) : null,
                add: true,
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  if (owner != null && available)
                    _table(context, <Widget>[
                      for (final String address in owner.members)
                        _addressRow(
                          context,
                          owner,
                          address,
                          state.balances[address],
                          enabled,
                          current,
                        ),
                    ])
                  else
                    _note(context, context.l10n.addressesBalancesUnavailable),
                  if (state.loading) _note(context, context.l10n.homeLoading),
                  if (state.balancesFailed)
                    _note(context, context.l10n.addressesBalancesUnavailable),
                  Disclosure.bare(
                    controller: _labelForm,
                    child: _buildLabelForm(context, enabled, current),
                  ),
                  if (_actionError != null)
                    _note(context, _actionError!, error: true),
                ],
              ),
            ),
            SizedBox(height: tokens.panelGap),
            _card(
              context,
              context.l10n.addressesContacts,
              contactsAvailable ? contacts.length : null,
              _button(
                context,
                const Key('addresses_add_contact'),
                context.l10n.addressesAddContact,
                enabled && contactsAvailable
                    ? () => _editContact(null, current)
                    : null,
                add: true,
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  if (!contactsAvailable)
                    _note(context, context.l10n.sendContactsUnavailable)
                  else if (contacts.isEmpty)
                    _note(context, context.l10n.nodesNoneYet)
                  else
                    _table(context, <Widget>[
                      for (final Contact contact in contacts)
                        _contactRow(context, owner, contact, enabled, current),
                    ]),
                  Disclosure.bare(
                    controller: _contactForm,
                    child: _buildContactForm(context, enabled, current),
                  ),
                ],
              ),
            ),
            SizedBox(height: tokens.panelGap),
            Panel(
              child: Disclosure(
                title: context.l10n.addressesAccountChain(chainLabel),
                keyPrefix: 'addresses_account_chain',
                summary: selectedAccount == null
                    ? null
                    : context.l10n.addressesBlockCount(selectedAccount.height),
                onChanged: (bool open) {
                  if (open && current() && available) {
                    unawaited(_presenter.loadChain());
                  }
                },
                child: _buildChain(context, state),
              ),
            ),
          ],
        ),
      );
    },
  );

  Widget _card(
    BuildContext context,
    String title,
    int? count,
    Widget action,
    Widget body,
  ) {
    final AppTokens tokens = AppTokens.of(context);
    return Panel(
      heading: Row(
        children: <Widget>[
          Flexible(child: Text(title, style: tokens.headingText)),
          if (count != null) ...<Widget>[
            SizedBox(width: tokens.inlineGap),
            Text('$count', style: tokens.ledgerText),
          ],
        ],
      ),
      actions: <Widget>[action],
      shrinkWrap: true,
      child: body,
    );
  }

  Widget _button(
    BuildContext context,
    Key key,
    String label,
    VoidCallback? action, {
    bool add = false,
  }) {
    final AppTokens tokens = AppTokens.of(context);
    return OutlinedButton(
      key: key,
      onPressed: action,
      style: OutlinedButton.styleFrom(
        minimumSize: Size(0, tokens.smallButtonHeight),
        padding: EdgeInsetsDirectional.symmetric(
          horizontal: tokens.securitySettingsButtonInset,
        ),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        foregroundColor: tokens.foreground,
        textStyle: tokens.compactText,
        side: BorderSide(color: tokens.line),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(tokens.pillRadius),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (add) ...<Widget>[
            Icon(Icons.add, size: tokens.settingsIconSize),
            SizedBox(width: tokens.fieldLabelGap),
          ],
          Text(label),
        ],
      ),
    );
  }

  Widget _table(BuildContext context, List<Widget> rows) {
    final AppTokens tokens = AppTokens.of(context);
    final double scale = MediaQuery.textScalerOf(context).scale(1);
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double minimum = tokens.addressesTableMinWidth * scale;
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: constraints.maxWidth > minimum
                ? constraints.maxWidth
                : minimum,
            child: Column(
              children: <Widget>[
                for (int index = 0; index < rows.length; index++) ...<Widget>[
                  if (index > 0) const Divider(),
                  rows[index],
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _addressRow(
    BuildContext context,
    AddressesSettingsBinding owner,
    String address,
    AddressesAccount? account,
    bool enabled,
    bool Function() current,
  ) {
    final AppTokens tokens = AppTokens.of(context);
    final bool selected = address == owner.selected;
    final double scale = MediaQuery.textScalerOf(context).scale(1);
    final String label = owner.labels[address] ?? address;
    return ConstrainedBox(
      key: ValueKey<String>('addresses_row_$address'),
      constraints: BoxConstraints(minHeight: tokens.addressesRowMinHeight),
      child: Padding(
        padding: tokens.addressesTablePadding,
        child: Row(
          children: <Widget>[
            SizedBox(
              width: tokens.addressesChoiceWidth,
              child: Semantics(
                checked: selected,
                inMutuallyExclusiveGroup: true,
                child: IconButton(
                  key: ValueKey<String>('addresses_select_$address'),
                  tooltip: label,
                  onPressed: enabled && !selected
                      ? () => unawaited(_select(address, current))
                      : null,
                  iconSize: tokens.settingsIconSize,
                  icon: Icon(
                    selected
                        ? Icons.radio_button_checked
                        : Icons.radio_button_off,
                    color: selected ? tokens.znnInk : tokens.faint,
                  ),
                ),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: tokens.fieldLabelGap,
                    children: <Widget>[
                      Text(label, style: tokens.bodyText),
                      if (selected)
                        DecoratedBox(
                          decoration: BoxDecoration(
                            color: tokens.znn.withValues(alpha: .12),
                            borderRadius: BorderRadius.circular(
                              tokens.pillRadius,
                            ),
                          ),
                          child: Padding(
                            padding: EdgeInsetsDirectional.symmetric(
                              horizontal: tokens.fieldLabelGap,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
                                Icon(
                                  Icons.check,
                                  size: tokens.settingsIconSize,
                                  color: tokens.znnInk,
                                ),
                                Text(
                                  context.l10n.addressesSelected,
                                  style: tokens.addressesSelectedText.copyWith(
                                    color: tokens.znnInk,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                  _AddressText(address, style: tokens.addressesAddressText),
                ],
              ),
            ),
            SizedBox(
              width: tokens.addressesBalanceWidth * scale,
              child: _balance(
                context,
                account?.znn,
                kZnnCoin.symbol,
                dim: false,
              ),
            ),
            SizedBox(
              width: tokens.addressesBalanceWidth * scale,
              child: _balance(
                context,
                account?.qsr,
                kQsrCoin.symbol,
                dim: true,
              ),
            ),
            SizedBox(
              width: tokens.addressesActionsWidth,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: <Widget>[
                  IconButton(
                    key: ValueKey<String>('addresses_rename_$address'),
                    tooltip: context.l10n.settingsAddressRenameTooltip,
                    onPressed: enabled
                        ? () => _editLabel(address, current)
                        : null,
                    iconSize: tokens.settingsIconSize,
                    icon: const Icon(Icons.edit_outlined),
                  ),
                  IconButton(
                    key: ValueKey<String>('addresses_copy_$address'),
                    tooltip: context.l10n.receiveCopyAddress,
                    onPressed: enabled
                        ? () => unawaited(_copy(address, owner, current))
                        : null,
                    iconSize: tokens.settingsIconSize,
                    icon: const Icon(Icons.copy_outlined),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _balance(
    BuildContext context,
    BigInt? amount,
    String symbol, {
    required bool dim,
  }) {
    final AppTokens tokens = AppTokens.of(context);
    return Align(
      alignment: AlignmentDirectional.centerEnd,
      child: amount == null || widget.hideBalances
          ? Text(
              widget.hideBalances ? '••••' : '…',
              textDirection: TextDirection.ltr,
              style: tokens.dataText.copyWith(color: tokens.dim),
            )
          : AmountText(
              amount,
              decimals: coinDecimals,
              style: tokens.dataText.copyWith(
                color: dim ? tokens.dim : tokens.foreground,
              ),
              symbol: symbol,
            ),
    );
  }

  Widget _contactRow(
    BuildContext context,
    AddressesSettingsBinding owner,
    Contact contact,
    bool enabled,
    bool Function() current,
  ) {
    final AppTokens tokens = AppTokens.of(context);
    final double scale = MediaQuery.textScalerOf(context).scale(1);
    final SendDraftCubit draft = widget.draft;
    final VoidCallback? open = widget.onSend;
    final bool Function()? senderIsCurrent = widget.senderIsCurrent;
    DateTime? sent;
    for (final String member in owner.members) {
      final DateTime? candidate = owner.contacts.lastSent(
        contact.address,
        from: member,
      );
      if (candidate != null && (sent == null || candidate.isAfter(sent))) {
        sent = candidate;
      }
    }
    final String sentLabel = sent == null
        ? context.l10n.addressesNoRecord
        : context.l10n.addressesSent(
            FormatUtils.formatDateForTable(
              sent.millisecondsSinceEpoch,
              locale: Localizations.localeOf(context),
            ),
          );
    return ConstrainedBox(
      key: ValueKey<String>('addresses_contact_${contact.address}'),
      constraints: BoxConstraints(minHeight: tokens.addressesContactMinHeight),
      child: Padding(
        padding: tokens.addressesTablePadding,
        child: Row(
          children: <Widget>[
            SizedBox(
              width: tokens.addressesContactNameWidth * scale,
              child: Text(
                contact.name,
                overflow: TextOverflow.ellipsis,
                style: tokens.bodyText,
              ),
            ),
            Expanded(
              child: _AddressText(contact.address, style: tokens.dataText),
            ),
            SizedBox(
              width: tokens.addressesLastSentWidth * scale,
              child: Text(
                sentLabel,
                style: tokens.bodyText.copyWith(color: tokens.dim),
              ),
            ),
            ConstrainedBox(
              constraints: BoxConstraints(
                minWidth: tokens.addressesActionsWidth * scale,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.end,
                children: <Widget>[
                  _button(
                    context,
                    ValueKey<String>('addresses_send_${contact.address}'),
                    context.l10n.send,
                    enabled &&
                            owner.canSend &&
                            widget.onSend != null &&
                            !widget.draft.isClosed &&
                            (widget.senderIsCurrent?.call() ?? true)
                        ? () => _send(
                            contact,
                            current,
                            draft: draft,
                            open: open,
                            senderIsCurrent: senderIsCurrent,
                          )
                        : null,
                  ),
                  IconButton(
                    tooltip: context.l10n.addressesEditContact,
                    key: ValueKey<String>(
                      'addresses_edit_contact_${contact.address}',
                    ),
                    iconSize: tokens.settingsIconSize,
                    icon: const Icon(Icons.edit_outlined),
                    onPressed: enabled
                        ? () => _editContact(contact, current)
                        : null,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLabelForm(
    BuildContext context,
    bool enabled,
    bool Function() current,
  ) {
    final AppTokens tokens = AppTokens.of(context);
    return Padding(
      padding: tokens.addressesTablePadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          TextField(
            key: const Key('addresses_label_field'),
            controller: _label,
            enabled: enabled,
            decoration: InputDecoration(
              labelText: context.l10n.settingsAddressLabelHint,
            ),
            onSubmitted: (_) => unawaited(_saveLabel(current)),
          ),
          SizedBox(height: tokens.settingsActionGap),
          Wrap(
            spacing: tokens.settingsActionGap,
            children: <Widget>[
              _button(
                context,
                const Key('addresses_save_label'),
                context.l10n.commonSave,
                enabled ? () => unawaited(_saveLabel(current)) : null,
              ),
              TextButton(
                onPressed: () {
                  if (!current()) return;
                  setState(() {
                    _labelEpoch++;
                    _labelForm.close();
                  });
                },
                child: Text(context.l10n.cancel),
              ),
            ],
          ),
          if (_labelError != null) _note(context, _labelError!, error: true),
        ],
      ),
    );
  }

  Widget _buildContactForm(
    BuildContext context,
    bool enabled,
    bool Function() current,
  ) {
    final AppTokens tokens = AppTokens.of(context);
    return Padding(
      padding: tokens.addressesTablePadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          TextField(
            key: const Key('addresses_contact_name'),
            controller: _name,
            enabled: enabled,
            decoration: InputDecoration(
              labelText: context.l10n.addressesContactName,
            ),
          ),
          SizedBox(height: tokens.settingsActionGap),
          TextField(
            key: const Key('addresses_contact_address'),
            controller: _contactAddress,
            enabled: enabled && _editingContact == null,
            style: tokens.dataText,
            textDirection: TextDirection.ltr,
            decoration: InputDecoration(
              labelText: context.l10n.addressesContactAddress,
            ),
          ),
          SizedBox(height: tokens.settingsActionGap),
          Wrap(
            spacing: tokens.settingsActionGap,
            children: <Widget>[
              _button(
                context,
                const Key('addresses_save_contact'),
                context.l10n.commonSave,
                enabled ? () => unawaited(_saveContact(current)) : null,
              ),
              TextButton(
                onPressed: () {
                  if (!current()) return;
                  setState(() {
                    _contactEpoch++;
                    _contactForm.close();
                  });
                },
                child: Text(context.l10n.cancel),
              ),
            ],
          ),
          if (_contactError != null)
            _note(context, _contactError!, error: true),
        ],
      ),
    );
  }

  Widget _buildChain(BuildContext context, AddressesSettingsState state) {
    if (state.chainLoading) return _note(context, context.l10n.homeLoading);
    if (state.chainFailed || state.chain == null) {
      return _note(context, context.l10n.addressesAccountChainUnavailable);
    }
    if (state.chain!.height == 0) {
      return _note(context, context.l10n.nodesNoneYet);
    }
    final AppTokens tokens = AppTokens.of(context);
    return Padding(
      padding: tokens.addressesTablePadding,
      child: Column(
        children: <Widget>[
          for (final MapEntry<int, int> entry in state.chain!.counts.entries)
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    FormatUtils.extractNameFromEnum<BlockTypeEnum>(
                      BlockTypeEnum.values[entry.key],
                    ),
                    style: tokens.bodyText,
                  ),
                ),
                Text(
                  '${entry.value}',
                  textDirection: TextDirection.ltr,
                  style: tokens.dataText,
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _note(BuildContext context, String message, {bool error = false}) {
    final AppTokens tokens = AppTokens.of(context);
    return Padding(
      padding: tokens.addressesTablePadding,
      child: Text(
        message,
        style: tokens.bodyText.copyWith(
          color: error ? tokens.error : tokens.dim,
        ),
      ),
    );
  }
}

class _AddressText extends StatelessWidget {
  const _AddressText(this.address, {required this.style});
  final String address;
  final TextStyle style;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: address,
    child: LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final TextPainter measure = TextPainter(
          text: TextSpan(text: address, style: style),
          textDirection: TextDirection.ltr,
          textScaler: MediaQuery.textScalerOf(context),
        )..layout();
        final String text =
            measure.width <= constraints.maxWidth || address.length <= 24
            ? address
            : '${address.substring(0, 12)}…'
                  '${address.substring(address.length - 8)}';
        measure.dispose();
        return Text(
          text,
          style: style,
          textDirection: TextDirection.ltr,
          textAlign: ltrTextAlign(context),
          maxLines: 1,
          overflow: TextOverflow.clip,
        );
      },
    ),
  );
}
