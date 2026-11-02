import 'dart:async';

import 'package:flutter/services.dart';
import 'package:intl/intl.dart' show NumberFormat;
import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/extensions/buildcontext_extension.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/disclosure.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/ltr.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/page/page_widgets.dart';
import 'package:zenon_syrius_wallet_flutter/seams/seam.dart';
import 'package:zenon_syrius_wallet_flutter/utils/app_theme.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/settings_widgets/node_settings_presenter.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/settings_widgets/settings_parts.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/reusable_widgets/modals/frosted_route.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/reusable_widgets/modals/modal_chrome.dart';

part 'node_settings_rows.dart';

/// A pure Node presentation. All sources, actions and updater UI are injected.
class NodeSettingsView extends StatefulWidget {
  /// This constructor never falls back to a wallet, socket, file or updater.
  const NodeSettingsView({
    required this.presenter,
    required this.embeddedNode,
    this.question,
    this.isCurrent,
    this.confirmSelected = false,
    super.key,
  });

  /// The external owner closes this presenter after unmounting the view.
  final NodeSettingsPresenter presenter;

  /// Production supplies the existing updater; tests supply inert content.
  final Widget embeddedNode;

  /// An injected mismatch response for bounded, network-free view tests.
  final Future<bool> Function(NodeSettingsMismatch mismatch)? question;

  /// Optional original page authority, including an outgoing section guard.
  final bool Function()? isCurrent;

  /// Onboarding may explicitly verify and continue with the existing selection.
  final bool confirmSelected;

  @override
  State<NodeSettingsView> createState() => _NodeSettingsViewState();
}

class _NodeSettingsViewState extends State<NodeSettingsView>
    with WidgetsBindingObserver {
  final TextEditingController _endpoint = TextEditingController();
  final TextEditingController _chain = TextEditingController();
  final DisclosureController _nodeForm = DisclosureController();
  StreamSubscription<NodeSettingsState>? _subscription;
  String? _editing;
  String? _inputError;
  int _formEpoch = 0;
  int _chainEpoch = 0;
  int _seenEpoch = 0;
  bool _chainOpen = false;
  bool _visible = true;
  bool _windowActive = true;
  bool _attached = false;
  FocusNode? _parentFocus;
  ModalRoute<dynamic>? _pageRoute;
  FrostedDialogRoute<bool>? _questionRoute;
  NavigatorState? _questionNavigator;

  NodeSettingsPresenter get _presenter => widget.presenter;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _endpoint.addListener(_changed);
    _chain.addListener(_changed);
    _nodeForm.addListener(_formChanged);
    _listen();
  }

  void _listen() {
    _seenEpoch = _presenter.authorityEpoch;
    _subscription = _presenter.stream.listen((NodeSettingsState state) {
      if (_seenEpoch != _presenter.authorityEpoch) {
        _seenEpoch = _presenter.authorityEpoch;
        _dismissQuestion();
      }
      _changed();
    });
  }

  void _changed() {
    if (mounted) {
      setState(() {});
    }
  }

  void _formChanged() {
    _formEpoch++;
    _changed();
  }

  bool get _ownQuestion =>
      (_questionRoute?.isActive ?? false) &&
      (_questionRoute?.isCurrent ?? false);

  bool get _focusAllowsInput {
    if (_ownQuestion) {
      return true;
    }
    final FocusNode? focus = _parentFocus;
    return focus == null ||
        (focus.descendantsAreFocusable &&
            focus.ancestors.every(
              (FocusNode ancestor) => ancestor.descendantsAreFocusable,
            ));
  }

  bool get _sourceVisible =>
      _windowActive &&
      (widget.isCurrent?.call() ?? true) &&
      _focusAllowsInput &&
      TickerMode.valuesOf(context).enabled &&
      ((_pageRoute?.isCurrent ?? true) || _ownQuestion);

  bool get _current =>
      mounted &&
      _visible &&
      _windowActive &&
      (widget.isCurrent?.call() ?? true) &&
      _focusAllowsInput &&
      ((_pageRoute?.isCurrent ?? true) || _ownQuestion);

  bool _canAct(NodeSettingsPresenter owner, int epoch) =>
      identical(owner, _presenter) && _current && epoch == owner.authorityEpoch;

  void _owned(NodeSettingsPresenter owner, int epoch, VoidCallback action) {
    if (_canAct(owner, epoch)) {
      action();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _parentFocus = Focus.maybeOf(context, scopeOk: true);
    _pageRoute = ModalRoute.of(context);
    _synchronizeVisibility();
  }

  void _synchronizeVisibility({bool refresh = false}) {
    final bool wasVisible = _visible;
    _visible = _sourceVisible;
    _presenter.setVisible(visible: _visible);
    if (!_visible) _dismissQuestion();
    if (!_attached || refresh || (!wasVisible && _visible)) {
      _attached = true;
      if (_visible) unawaited(_presenter.refresh());
    }
  }

  @override
  void didUpdateWidget(NodeSettingsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final bool replaced = !identical(oldWidget.presenter, widget.presenter);
    final bool previousCurrent = oldWidget.isCurrent?.call() ?? true;
    if (replaced) {
      oldWidget.presenter.setVisible(visible: false);
      unawaited(_subscription?.cancel());
      _dismissQuestion();
      _listen();
    } else if (!previousCurrent) {
      _presenter.invalidate();
      _dismissQuestion();
    }
    _synchronizeVisibility(refresh: replaced || !previousCurrent);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _windowActive = state == AppLifecycleState.resumed;
    if (!_windowActive) {
      _visible = false;
      _presenter.setVisible(visible: false);
      _dismissQuestion();
    } else if (mounted) {
      _synchronizeVisibility(refresh: true);
    }
    _changed();
  }

  void _dismissQuestion() {
    final FrostedDialogRoute<bool>? route = _questionRoute;
    final NavigatorState? navigator = _questionNavigator;
    _questionRoute = null;
    _questionNavigator = null;
    if (route == null || navigator == null) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((Duration _) {
      if (navigator.mounted && route.isActive) {
        navigator.removeRoute(route, false);
      }
    });
  }

  Future<bool> _ask({
    required String title,
    required String body,
    required String node,
    required String accept,
    required int epoch,
  }) async {
    final NodeSettingsPresenter owner = _presenter;
    if (!_current ||
        epoch != _presenter.authorityEpoch ||
        _questionRoute != null) {
      return false;
    }
    final NavigatorState navigator = Navigator.of(context, rootNavigator: true);
    final String cancel = context.l10n.cancel;
    late final FrostedDialogRoute<bool> route;
    void answer({required bool accepted}) {
      if (!_canAct(owner, epoch) ||
          !identical(_questionRoute, route) ||
          !route.isCurrent ||
          !navigator.mounted) {
        return;
      }
      navigator.pop(accepted);
    }

    route = FrostedDialogRoute<bool>(
      barrierDismissible: false,
      pageBuilder:
          (
            BuildContext dialog,
            Animation<double> _,
            Animation<double> _,
          ) => DialogCard(
            title: title,
            body: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(body),
                SizedBox(height: AppTokens.of(dialog).inlineGap),
                Text(
                  node,
                  textDirection: TextDirection.ltr,
                  style: AppTokens.of(dialog).dataText,
                ),
              ],
            ),
            actions: <Widget>[
              TextButton(
                key: const Key('node_settings_question_cancel'),
                autofocus: true,
                style: quietButtonStyle(dialog),
                onPressed: () => answer(accepted: false),
                child: Text(cancel),
              ),
              TextButton(
                key: const Key('node_settings_question_accept'),
                style: secondaryButtonStyle(dialog),
                onPressed: () => answer(accepted: true),
                child: Text(accept),
              ),
            ],
          ),
    );
    _questionNavigator = navigator;
    _questionRoute = route;
    try {
      final bool accepted = await navigator.push<bool>(route) ?? false;
      return _canAct(owner, epoch) && accepted;
    } finally {
      if (identical(_questionRoute, route)) {
        _questionRoute = null;
        _questionNavigator = null;
      }
    }
  }

  Future<bool> _mismatch(NodeSettingsMismatch mismatch, int epoch) {
    if (!_current || epoch != _presenter.authorityEpoch) {
      return Future<bool>.value(false);
    }
    final Future<bool> Function(NodeSettingsMismatch)? question =
        widget.question;
    if (question != null) {
      return question(mismatch);
    }
    return _ask(
      title: context.l10n.nodeSettingsMismatchTitle,
      body: context.l10n.nodeSettingsMismatchBody(
        mismatch.nodeChain,
        mismatch.clientChain,
      ),
      node: mismatch.node,
      accept: context.l10n.nodeSettingsProceed,
      epoch: epoch,
    );
  }

  void _select(String node, int epoch, {bool confirmCurrent = false}) {
    if (!_current || epoch != _presenter.authorityEpoch) {
      return;
    }
    final NodeSettingsPresenter owner = _presenter;
    unawaited(
      owner.select(
        node,
        epoch: epoch,
        confirmCurrent: confirmCurrent,
        question: (NodeSettingsMismatch mismatch) => _canAct(owner, epoch)
            ? _mismatch(mismatch, epoch)
            : Future<bool>.value(false),
      ),
    );
  }

  void _openForm(int epoch, {String? original}) {
    if (!_current ||
        _presenter.state.busy ||
        epoch != _presenter.authorityEpoch) {
      return;
    }
    if (original == null && _nodeForm.isOpen && _editing == null) {
      _nodeForm.close();
      return;
    }
    _formEpoch++;
    _editing = original;
    _inputError = null;
    _endpoint.text = original ?? '';
    _nodeForm.open();
    _changed();
  }

  Future<void> _saveNode(int epoch, int formEpoch) async {
    final NodeSettingsPresenter owner = _presenter;
    final String text = _endpoint.text;
    final String? original = _editing;
    bool current() =>
        _canAct(owner, epoch) &&
        _nodeForm.isOpen &&
        formEpoch == _formEpoch &&
        epoch == _presenter.authorityEpoch;
    if (!current()) {
      return;
    }
    if (!isNodeSettingsEndpoint(text)) {
      setState(() => _inputError = context.l10n.validatorInvalidNode);
      return;
    }
    final bool saved = await owner.storeNode(
      epoch: epoch,
      original: original,
      replacement: text,
      isCurrent: current,
    );
    if (saved && current() && _endpoint.text == text && _editing == original) {
      _endpoint.clear();
      _nodeForm.close();
    }
  }

  Future<void> _deleteNode(NodeSettingsEntry row, int epoch) async {
    final NodeSettingsPresenter owner = _presenter;
    if (!_current ||
        _presenter.state.busy ||
        epoch != _presenter.authorityEpoch) {
      return;
    }
    final bool accepted = await _ask(
      title: context.l10n.settingsNodeDeleteLabel,
      body: context.l10n.nodeSettingsDeleteQuestion,
      node: row.endpoint,
      accept: context.l10n.settingsNodeDeleteLabel,
      epoch: epoch,
    );
    if (!accepted || !_canAct(owner, epoch)) {
      return;
    }
    await owner.storeNode(epoch: epoch, original: row.node);
  }

  Future<void> _saveChain(int epoch, int chainEpoch) async {
    final NodeSettingsPresenter owner = _presenter;
    final String text = _chain.text;
    final int? value = int.tryParse(text);
    bool current() =>
        _canAct(owner, epoch) &&
        _chainOpen &&
        chainEpoch == _chainEpoch &&
        epoch == _presenter.authorityEpoch;
    if (!current() || value == null || value <= 0) {
      return;
    }
    final bool saved = await owner.changeClientChain(
      value,
      epoch: epoch,
      isCurrent: current,
    );
    if (saved && current() && _chain.text == text) {
      _chain.clear();
    }
  }

  String? _failure(NodeSettingsFailure? failure) => switch (failure) {
    null => null,
    NodeSettingsFailure.stale => context.l10n.nodeSettingsSessionChanged,
    NodeSettingsFailure.connection => context.l10n.nodeSettingsFailed,
    NodeSettingsFailure.save => context.l10n.nodeSettingsSaveFailed,
    NodeSettingsFailure.duplicate => context.l10n.settingsNodeExistsError,
    NodeSettingsFailure.invalid => context.l10n.validatorInvalidNode,
  };

  @override
  Widget build(BuildContext context) {
    final NodeSettingsState state = _presenter.state;
    final String? selectedNode = state.activeNode;
    final NodeSettingsPresenter owner = _presenter;
    final NodeSettingsNetwork? network = _presenter.currentNetwork;
    final int epoch = _presenter.authorityEpoch;
    final bool enabled = _current && !state.busy;
    final String? failure = _failure(state.failure);
    return IgnorePointer(
      ignoring: !_current,
      child: Focus(
        canRequestFocus: false,
        descendantsAreFocusable: _current,
        child: ExcludeSemantics(
          excluding: !_current,
          child: SettingsSection(
            key: const Key('node_settings_page'),
            children: <Widget>[
              Panel(
                key: const Key('node_settings_nodes'),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    _NodeSettingsHeader(
                      count: state.entries.length,
                      network: network,
                      onAdd: enabled
                          ? () => _owned(owner, epoch, () => _openForm(epoch))
                          : null,
                    ),
                    RadioGroup<String>(
                      key: const Key('node_settings_choices'),
                      groupValue: state.activeNode,
                      onChanged: (String? node) {
                        if (enabled && node != null) {
                          _owned(owner, epoch, () => _select(node, epoch));
                        }
                      },
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          for (final NodeSettingsEntry row in state.entries)
                            _NodeSettingsRow(
                              key: ValueKey<String>(
                                'node_settings_row_${row.node}',
                              ),
                              row: row,
                              active: row.node == state.activeNode,
                              pending: row.node == state.pendingNode,
                              clientChain: state.clientChain,
                              network: network?.node == row.node
                                  ? network
                                  : null,
                              onSelect: enabled
                                  ? () => _owned(
                                      owner,
                                      epoch,
                                      () => _select(row.node, epoch),
                                    )
                                  : null,
                              onEdit: enabled && row.custom
                                  ? () => _owned(
                                      owner,
                                      epoch,
                                      () => _openForm(
                                        epoch,
                                        original: row.node,
                                      ),
                                    )
                                  : null,
                              onDelete: enabled && row.custom
                                  ? () => _owned(
                                      owner,
                                      epoch,
                                      () => unawaited(_deleteNode(row, epoch)),
                                    )
                                  : null,
                            ),
                        ],
                      ),
                    ),
                    Disclosure.bare(
                      controller: _nodeForm,
                      keepAlive: true,
                      child: _buildNodeForm(enabled, epoch),
                    ),
                    if (widget.confirmSelected && selectedNode != null)
                      Align(
                        alignment: AlignmentDirectional.centerEnd,
                        child: TextButton(
                          key: const Key('node_onboarding_continue'),
                          onPressed: enabled
                              ? () => _select(
                                  selectedNode,
                                  epoch,
                                  confirmCurrent: true,
                                )
                              : null,
                          child: Text(context.l10n.continueText),
                        ),
                      ),
                    if (failure != null)
                      Padding(
                        padding: AppTokens.of(context).settingsRowPadding,
                        child: Text(
                          failure,
                          key: const Key('node_settings_failure'),
                          style: settingErrorStyle(context),
                        ),
                      ),
                  ],
                ),
              ),
              IgnorePointer(
                ignoring: !enabled,
                child: Focus(
                  canRequestFocus: false,
                  descendantsAreFocusable: enabled,
                  child: ExcludeSemantics(
                    excluding: !enabled,
                    child: widget.embeddedNode,
                  ),
                ),
              ),
              Panel(
                key: const Key('node_settings_chain_card'),
                child: Disclosure(
                  title: context.l10n.nodeSettingsChainTitle,
                  summary: context.l10n.nodeSettingsClientChain(
                    state.clientChain,
                  ),
                  keepAlive: true,
                  keyPrefix: 'node_settings_chain',
                  onChanged: (bool open) {
                    _chainOpen = open;
                    _chainEpoch++;
                    _changed();
                  },
                  child: _buildChainForm(enabled, epoch),
                ),
              ),
              Panel(
                key: const Key('node_settings_peers_card'),
                child: Disclosure(
                  title: context.l10n.nodeSettingsPeers,
                  count: network?.peers?.length,
                  keyPrefix: 'node_settings_peers',
                  child: _NodeSettingsPeers(peers: network?.peers),
                ),
              ),
              SeamGate(
                key: const Key('node_settings_sporks_gate'),
                seam: Seam.sporks,
                child: Panel(
                  child: Disclosure(
                    title: context.l10n.nodeSettingsSporks,
                    summary: context.l10n.nodeSettingsSporksMode,
                    keyPrefix: 'node_settings_sporks',
                    child: const SizedBox.shrink(),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNodeForm(bool enabled, int epoch) {
    final NodeSettingsPresenter owner = _presenter;
    final AppTokens tokens = AppTokens.of(context);
    final int formEpoch = _formEpoch;
    return Padding(
      padding: tokens.settingsRowPadding,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          TextField(
            key: const Key('node_settings_endpoint'),
            controller: _endpoint,
            enabled: enabled,
            textDirection: TextDirection.ltr,
            style: tokens.dataText,
            decoration: InputDecoration(
              labelText: context.l10n.settingsNodeAddressHint,
              errorText: _inputError,
            ),
            onChanged: (String _) {
              if (_inputError != null) {
                setState(() => _inputError = null);
              }
            },
            onSubmitted: (String _) => _owned(
              owner,
              epoch,
              () => unawaited(_saveNode(epoch, formEpoch)),
            ),
          ),
          SizedBox(height: tokens.inlineGap),
          Wrap(
            spacing: tokens.inlineGap,
            children: <Widget>[
              _NodeSettingsButton(
                key: const Key('node_settings_endpoint_save'),
                onPressed: enabled && isNodeSettingsEndpoint(_endpoint.text)
                    ? () => _owned(
                        owner,
                        epoch,
                        () => unawaited(_saveNode(epoch, formEpoch)),
                      )
                    : null,
                label: context.l10n.commonSave,
              ),
              _NodeSettingsButton(
                key: const Key('node_settings_endpoint_cancel'),
                onPressed: () => _owned(owner, epoch, () {
                  if (formEpoch == _formEpoch) {
                    _nodeForm.close();
                  }
                }),
                label: context.l10n.cancel,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildChainForm(bool enabled, int epoch) {
    final NodeSettingsPresenter owner = _presenter;
    final AppTokens tokens = AppTokens.of(context);
    final int chainEpoch = _chainEpoch;
    final int? value = int.tryParse(_chain.text);
    return Padding(
      padding: tokens.settingsRowPadding,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          TextField(
            key: const Key('node_settings_client_chain'),
            controller: _chain,
            enabled: enabled,
            textDirection: TextDirection.ltr,
            style: tokens.dataText,
            inputFormatters: <TextInputFormatter>[
              FilteringTextInputFormatter.digitsOnly,
            ],
            decoration: InputDecoration(
              labelText: context.l10n.nodeSettingsChainTitle,
              helperText: context.l10n.nodeSettingsChainHint,
              errorText: _chain.text.isNotEmpty && (value == null || value <= 0)
                  ? context.l10n.nodeSettingsChainInvalid
                  : null,
            ),
            onSubmitted: (String _) => _owned(
              owner,
              epoch,
              () => unawaited(_saveChain(epoch, chainEpoch)),
            ),
          ),
          SizedBox(height: tokens.inlineGap),
          _NodeSettingsButton(
            key: const Key('node_settings_chain_save'),
            label: context.l10n.commonSave,
            onPressed:
                enabled &&
                    value != null &&
                    value > 0 &&
                    value != _presenter.state.clientChain
                ? () => _owned(
                    owner,
                    epoch,
                    () => unawaited(_saveChain(epoch, chainEpoch)),
                  )
                : null,
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_subscription?.cancel());
    _presenter.setVisible(visible: false);
    _dismissQuestion();
    _endpoint.dispose();
    _chain.dispose();
    _nodeForm.dispose();
    super.dispose();
  }
}
