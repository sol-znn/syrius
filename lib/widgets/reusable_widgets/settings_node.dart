import 'dart:async';

import 'package:flutter_vector_icons/flutter_vector_icons.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/l10n/l10n.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/extensions/buildcontext_extension.dart';
import 'package:zenon_syrius_wallet_flutter/utils/app_colors.dart';
import 'package:zenon_syrius_wallet_flutter/utils/app_theme.dart';
import 'package:zenon_syrius_wallet_flutter/utils/constants.dart';
import 'package:zenon_syrius_wallet_flutter/utils/global.dart';
import 'package:zenon_syrius_wallet_flutter/utils/input_validators.dart';
import 'package:zenon_syrius_wallet_flutter/utils/node_utils.dart';
import 'package:zenon_syrius_wallet_flutter/utils/notification_utils.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/settings_widgets/settings_parts.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/widgets.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

/// Retains the legacy single-node row for callers outside the Settings section.
class SettingsNode extends StatefulWidget {
  /// Receives exact node identities and the existing catalog-change callbacks.
  const SettingsNode({
    required this.node,
    required this.onNodePressed,
    required this.onChangedOrDeletedNode,
    required this.currentNode,
    super.key,
  });

  /// The saved endpoint or embedded-node sentinel represented by this row.
  final String node;

  /// Requests selection of this exact row through the caller's connection flow.
  final void Function(String?) onNodePressed;

  /// Reports completion of the existing custom-node catalog mutation.
  final VoidCallback onChangedOrDeletedNode;

  /// The selected node identity used to restrict actual frontier reads.
  final String currentNode;

  @override
  State<SettingsNode> createState() => _SettingsNodeState();
}

class _SettingsNodeState extends State<SettingsNode> {
  bool _editable = false;
  String? _nodeError;

  final TextEditingController _nodeController = TextEditingController();

  final GlobalKey<MyOutlinedButtonState> _changeButtonKey = GlobalKey();

  int? connectedNodeChainIdentifier;

  @override
  void initState() {
    _nodeController.text = widget.node;

    super.initState();
    unawaited(_loadCurrentChain());
  }

  Future<void> _loadCurrentChain() async {
    final String node = widget.node;
    if (node != widget.currentNode || node != kCurrentNode) return;
    final int? chain = await NodeUtils.getNodeChainIdentifier();
    if (!mounted ||
        widget.node != node ||
        widget.currentNode != node ||
        kCurrentNode != node) {
      return;
    }
    setState(() => connectedNodeChainIdentifier = chain);
  }

  @override
  void didUpdateWidget(SettingsNode oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.node != widget.node ||
        oldWidget.currentNode != widget.currentNode) {
      connectedNodeChainIdentifier = null;
      unawaited(_loadCurrentChain());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: _editable ? _buildNodeInputField() : _buildNode(context),
    );
  }

  Widget _buildNode(BuildContext context) {
    final bool custom =
        !kDefaultNodes.contains(widget.node) &&
        !kDefaultCommunityNodes.contains(widget.node);
    final bool chainMatches =
        connectedNodeChainIdentifier == getChainIdentifier();
    final int? chain = connectedNodeChainIdentifier;
    return Row(
      children: <Widget>[
        Expanded(
          child: InkWell(
            borderRadius: BorderRadius.circular(kCardRadius),
            onTap: () => widget.onNodePressed(widget.node),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
              child: Text(
                _nodeController.text,
                overflow: TextOverflow.ellipsis,
                // A URL is data; the embedded node is a name.
                style: widget.node == kEmbeddedNode
                    ? Theme.of(context).textTheme.bodyLarge
                    : settingMonoStyle(context).copyWith(
                        color: Theme.of(context).textTheme.bodyLarge!.color,
                      ),
              ),
            ),
          ),
        ),
        if (widget.currentNode == widget.node)
          StandardTooltipIcon(
            chain == null
                ? context.l10n.nodeSettingsUnknown
                : chainMatches
                ? context.l10n.settingsNodeChainIdTooltip(
                    getChainIdentifier(),
                    chain,
                  )
                : context.l10n.settingsNodeChainIdMismatchTooltip(
                    getChainIdentifier(),
                    chain,
                  ),
            MaterialCommunityIcons.identifier,
            iconColor: chain == null
                ? AppColors.faint
                : chainMatches
                ? AppColors.znnColor
                : AppColors.errorColor,
          ),
        if (widget.node.contains('wss://'))
          StandardTooltipIcon(
            context.l10n.settingsNodeEncryptedTooltip,
            Icons.lock_outline,
            iconColor: AppColors.faint,
          ),
        if (widget.node.contains('ws://'))
          StandardTooltipIcon(
            context.l10n.settingsNodeUnencryptedTooltip,
            Icons.lock_open,
            iconColor: AppColors.warn,
          ),
        if (widget.node.contains('Embedded')) ...<Widget>[
          StandardTooltipIcon(
            context.l10n.settingsNodeEmbeddedTooltip,
            MaterialCommunityIcons.security,
            iconColor: AppColors.faint,
          ),
          StandardTooltipIcon(
            context.l10n.settingsNodeEmbeddedSyncTooltip,
            MaterialCommunityIcons.clock,
            iconColor: AppColors.warn,
          ),
        ],
        if (kDefaultCommunityNodes.contains(widget.node))
          StandardTooltipIcon(
            context.l10n.settingsNodeCommunityTooltip,
            MaterialCommunityIcons.vector_link,
            iconColor: AppColors.faint,
          ),
        if (custom) ...<Widget>[
          IconButton(
            padding: const EdgeInsets.all(4),
            constraints: const BoxConstraints(),
            iconSize: 15,
            icon: const Icon(Icons.edit_outlined, color: AppColors.faint),
            onPressed: () {
              setState(() {
                _editable = true;
              });
            },
            tooltip: context.l10n.settingsNodeEditTooltip,
          ),
          IconButton(
            padding: const EdgeInsets.all(4),
            constraints: const BoxConstraints(),
            iconSize: 15,
            icon: const Icon(Icons.delete_outline, color: AppColors.faint),
            onPressed: () async {
              final bool? deleteConfirmed = await showDialogWithNoAndYesOptions(
                isBarrierDismissible: true,
                context: context,
                title: context.l10n.settingsNodeDeleteLabel,
                description: context.l10n.settingsNodeDeleteConfirm(
                  widget.node,
                ),
              );

              if (deleteConfirmed ?? false) {
                unawaited(_deleteNodeFromDb(widget.node));
              }
            },
            tooltip: context.l10n.settingsNodeDeleteLabel,
          ),
        ],
        const SizedBox(width: 8),
      ],
    );
  }

  Widget _buildNodeInputField() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Form(
              key: widget.key,
              autovalidateMode: AutovalidateMode.onUserInteraction,
              child: InputField(
                controller: _nodeController,
                hintText: context.l10n.settingsNodeAddressHint,
                onSubmitted: (String value) {
                  if (_nodeController.text != widget.node &&
                      _ifUserInputValid()) {
                    unawaited(_onChangeButtonPressed());
                  }
                },
                onChanged: (String value) {
                  if (value.isNotEmpty) {
                    setState(() {
                      _nodeError = null;
                    });
                  }
                },
                validator: (String? value) =>
                    InputValidators.node(value) ?? _nodeError,
              ),
            ),
          ),
          const SizedBox(width: 10),
          SecondaryAction(
            child: SettingsButton(
              onPressed:
                  _nodeController.text != widget.node && _ifUserInputValid()
                  ? _onChangeButtonPressed
                  : null,
              text: context.l10n.commonSave,
              key: _changeButtonKey,
            ),
          ),
          IconButton(
            tooltip: context.l10n.cancel,
            visualDensity: VisualDensity.compact,
            iconSize: 16,
            icon: const Icon(Icons.close, color: AppColors.faint),
            onPressed: () {
              setState(() {
                _nodeController.text = widget.node;
                _editable = false;
                _nodeError = null;
              });
            },
          ),
        ],
      ),
    );
  }

  bool _ifUserInputValid() =>
      InputValidators.node(_nodeController.text) == null;

  Future<void> _onChangeButtonPressed() async {
    try {
      _changeButtonKey.currentState!.showLoadingIndicator(true);
      if (_nodeController.text.isNotEmpty &&
          _nodeController.text.length <= kAddressLabelMaxLength &&
          !<String>[
            ...kDefaultNodes,
            ...kDefaultCommunityNodes,
            ...kDbNodes,
          ].contains(_nodeController.text)) {
        if (!Hive.isBoxOpen(kNodesBox)) {
          await Hive.openBox<String>(kNodesBox);
        }
        final Box<String> nodesBox = Hive.box<String>(kNodesBox);
        final Object? nodeKey = nodesBox.keys.firstWhere(
          (Object? key) => nodesBox.get(key) == widget.node,
        );
        await nodesBox.put(nodeKey, _nodeController.text);
        await NodeUtils.loadDbNodes();
        if (!mounted) return;
        setState(() {
          _editable = false;
          _nodeError = null;
        });
        widget.onChangedOrDeletedNode();
      } else if (_nodeController.text.isEmpty) {
        setState(() {
          _nodeError = currentL10n.settingsNodeEmptyError;
        });
      } else if (_nodeController.text.length > kAddressLabelMaxLength) {
        setState(() {
          _nodeError = currentL10n.settingsNodeTooLongError(
            kAddressLabelMaxLength,
          );
        });
      } else {
        setState(() {
          _nodeError = currentL10n.settingsNodeExistsError;
        });
      }
    } on Object catch (e) {
      if (!mounted) return;
      await NotificationUtils.sendNotificationError(
        e,
        currentL10n.commonSomethingWentWrong,
      );
    } finally {
      if (mounted) {
        _changeButtonKey.currentState?.showLoadingIndicator(false);
      }
    }
  }

  Future<void> _deleteNodeFromDb(String node) async {
    try {
      if (!Hive.isBoxOpen(kNodesBox)) {
        await Hive.openBox<String>(kNodesBox);
      }
      final Box<String> nodesBox = Hive.box<String>(kNodesBox);
      final Object? nodeKey = nodesBox.keys.firstWhere(
        (Object? key) => nodesBox.get(key) == node,
      );
      await nodesBox.delete(nodeKey);
      kDbNodes.remove(node);
      if (!mounted) return;
      widget.onChangedOrDeletedNode();
    } on Object catch (e) {
      if (!mounted) return;
      await NotificationUtils.sendNotificationError(
        e,
        currentL10n.settingsNodeDeleteFailedNotificationTitle(node),
      );
    }
  }

  @override
  void dispose() {
    _nodeController.dispose();
    super.dispose();
  }
}
