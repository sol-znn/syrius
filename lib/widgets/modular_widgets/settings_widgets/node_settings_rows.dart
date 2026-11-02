part of 'node_settings_view.dart';

String _nodeNumber(int value) =>
    NumberFormat.decimalPattern('en_US').format(value);

String _nodeIdentifier(String text) => text.length <= 46
    ? text
    : '${text.substring(0, 26)}…${text.substring(text.length - 16)}';

class _NodeSettingsButton extends StatelessWidget {
  const _NodeSettingsButton({
    required this.label,
    required this.onPressed,
    this.icon,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = AppTokens.of(context);
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: tokens.foreground,
        backgroundColor: tokens.card2,
        disabledForegroundColor: tokens.faint,
        side: BorderSide(color: tokens.line),
        minimumSize: Size(0, tokens.nodeSettingsCompactButtonHeight),
        padding: EdgeInsets.symmetric(
          horizontal: tokens.nodeSettingsCompactButtonInset,
        ),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        textStyle: tokens.nodeSettingsSubtitleText.copyWith(
          fontFamily: tokens.sansFontFamily,
          fontWeight: FontWeight.w500,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (icon != null) ...<Widget>[
            Icon(icon, size: tokens.zapSmallGlyphSize),
            SizedBox(width: tokens.fieldLabelGap),
          ],
          Text(label),
        ],
      ),
    );
  }
}

class _NodeSettingsHeader extends StatelessWidget {
  const _NodeSettingsHeader({
    required this.count,
    required this.network,
    required this.onAdd,
  });

  final int count;
  final NodeSettingsNetwork? network;
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = AppTokens.of(context);
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final bool summaryBelow =
            constraints.maxWidth < 760 ||
            MediaQuery.textScalerOf(context).scale(1) > 1.3;
        final Widget summary = _NodeSettingsSummary(network: network);
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            ConstrainedBox(
              constraints: BoxConstraints(minHeight: tokens.panelHeaderHeight),
              child: Padding(
                padding: tokens.settingsRowPadding,
                child: Row(
                  children: <Widget>[
                    Text(
                      context.l10n.nodeSettingsTitle,
                      style: tokens.headingText,
                    ),
                    SizedBox(width: tokens.cardGap),
                    Text(
                      _nodeNumber(count),
                      key: const Key('node_settings_count'),
                      textDirection: TextDirection.ltr,
                      style: ledgerLabelStyle(context),
                    ),
                    const Spacer(),
                    if (!summaryBelow) ...<Widget>[
                      Flexible(flex: 4, child: summary),
                      SizedBox(width: tokens.cardGap),
                    ],
                    _NodeSettingsButton(
                      key: const Key('node_settings_add'),
                      icon: Icons.add,
                      label: context.l10n.nodeSettingsAdd,
                      onPressed: onAdd,
                    ),
                  ],
                ),
              ),
            ),
            if (summaryBelow && network != null)
              Padding(padding: tokens.settingsRowPadding, child: summary),
          ],
        );
      },
    );
  }
}

class _NodeSettingsSummary extends StatelessWidget {
  const _NodeSettingsSummary({required this.network});

  final NodeSettingsNetwork? network;

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = AppTokens.of(context);
    final NodeSettingsNetwork? facts = network;
    if (facts == null) {
      return const SizedBox.shrink();
    }
    return Wrap(
      spacing: tokens.nodeSettingsSummaryGap,
      runSpacing: tokens.fieldLabelGap,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: <Widget>[
        Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              facts.synced == false ? Icons.sync : Icons.check_circle_outline,
              size: tokens.zapSmallGlyphSize,
              color: facts.synced == false ? tokens.warn : tokens.znnInk,
            ),
            SizedBox(width: tokens.fieldLabelGap),
            Text(
              facts.synced == null
                  ? context.l10n.nodeSettingsConnected
                  : facts.synced!
                  ? context.l10n.nodeSettingsSynced
                  : context.l10n.nodeSettingsSyncing,
              style: tokens.nodeSettingsSummaryText,
            ),
          ],
        ),
        _NodeSummaryFact(
          label: context.l10n.nodeSettingsMomentum,
          value: facts.height,
        ),
        if (facts.peers != null)
          _NodeSummaryFact(
            label: context.l10n.nodeSettingsPeers,
            value: facts.peers!.length,
          ),
        _NodeSummaryFact(label: context.l10n.stripChain, value: facts.chain),
      ],
    );
  }
}

class _NodeSummaryFact extends StatelessWidget {
  const _NodeSummaryFact({required this.label, required this.value});

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = AppTokens.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(label, style: tokens.nodeSettingsSummaryText),
        SizedBox(width: tokens.fieldLabelGap),
        Text(
          _nodeNumber(value),
          textDirection: TextDirection.ltr,
          style: tokens.nodeSettingsSummaryText.copyWith(
            fontFamily: tokens.monoFontFamily,
          ),
        ),
      ],
    );
  }
}

class _NodeSettingsRow extends StatelessWidget {
  const _NodeSettingsRow({
    required this.row,
    required this.active,
    required this.pending,
    required this.clientChain,
    required this.network,
    required this.onSelect,
    required this.onEdit,
    required this.onDelete,
    super.key,
  });

  final NodeSettingsEntry row;
  final bool active;
  final bool pending;
  final int clientChain;
  final NodeSettingsNetwork? network;
  final VoidCallback? onSelect;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = AppTokens.of(context);
    final NodeSettingsNetwork? facts = network;
    final Widget choice = SizedBox(
      width: tokens.nodeSettingsChoiceSize,
      height: tokens.nodeSettingsChoiceSize,
      child: Radio<String>(
        key: ValueKey<String>('node_settings_select_${row.node}'),
        value: row.node,
        enabled: onSelect != null,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
      ),
    );
    final Widget endpoint = InkWell(
      canRequestFocus: false,
      onTap: onSelect,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            row.embedded
                ? context.l10n.nodeSettingsEmbedded
                : Uri.tryParse(row.endpoint)?.host ?? row.endpoint,
            textDirection: row.embedded ? null : TextDirection.ltr,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: row.embedded ? tokens.bodyText : tokens.dataText,
          ),
          Tooltip(
            message: row.endpoint,
            child: Text(
              _nodeIdentifier(row.endpoint),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textDirection: TextDirection.ltr,
              style: tokens.nodeSettingsSubtitleText,
            ),
          ),
        ],
      ),
    );
    final Widget chain = facts == null
        ? Tooltip(
            message: context.l10n.nodeSettingsUnknown,
            child: Text('?', style: tokens.nodeSettingsSubtitleText),
          )
        : Text(
            context.l10n.nodeSettingsNodeChain(facts.chain),
            textDirection: ltrUnlessRtl(
              context.l10n.nodeSettingsNodeChain(facts.chain),
            ),
            style: tokens.nodeSettingsSummaryText.copyWith(
              color: facts.chain == clientChain ? tokens.dim : tokens.warn,
            ),
          );
    final Widget status = _NodeSettingsChip(
      pending: pending,
      connected: active && facts != null,
    );
    final Widget actions = Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (row.custom) ...<Widget>[
          _NodeSettingsIcon(
            key: ValueKey<String>('node_settings_edit_${row.node}'),
            tooltip: context.l10n.settingsNodeEditTooltip,
            icon: Icons.edit_outlined,
            onPressed: onEdit,
          ),
          _NodeSettingsIcon(
            key: ValueKey<String>('node_settings_delete_${row.node}'),
            tooltip: context.l10n.settingsNodeDeleteLabel,
            icon: Icons.delete_outline,
            onPressed: onDelete,
          ),
        ] else
          Tooltip(
            message: row.embedded
                ? context.l10n.settingsNodeEmbeddedTooltip
                : row.endpoint.startsWith('wss://')
                ? context.l10n.settingsNodeEncryptedTooltip
                : context.l10n.settingsNodeUnencryptedTooltip,
            child: Icon(
              row.embedded
                  ? Icons.shield_outlined
                  : row.endpoint.startsWith('wss://')
                  ? Icons.lock_outline
                  : Icons.lock_open,
              size: tokens.zapSmallGlyphSize,
              color: tokens.faint,
            ),
          ),
      ],
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: tokens.line)),
      ),
      child: Padding(
        padding: tokens.settingsRowPadding,
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final bool compact =
                constraints.maxWidth < 620 ||
                MediaQuery.textScalerOf(context).scale(1) > 1.3;
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    choice,
                    SizedBox(width: tokens.pageGap),
                    Expanded(flex: 5, child: endpoint),
                    if (!compact) ...<Widget>[
                      SizedBox(width: tokens.inlineGap),
                      Expanded(flex: 2, child: chain),
                      Expanded(
                        flex: 3,
                        child: Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: status,
                        ),
                      ),
                    ],
                    SizedBox(width: tokens.inlineGap),
                    actions,
                  ],
                ),
                if (compact)
                  Padding(
                    padding: EdgeInsetsDirectional.only(
                      start: tokens.nodeSettingsChoiceSize + tokens.pageGap,
                      top: tokens.fieldLabelGap,
                    ),
                    child: Wrap(
                      spacing: tokens.nodeSettingsSummaryGap,
                      runSpacing: tokens.fieldLabelGap,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: <Widget>[chain, status],
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _NodeSettingsIcon extends StatelessWidget {
  const _NodeSettingsIcon({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    super.key,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = AppTokens.of(context);
    return IconButton(
      onPressed: onPressed,
      tooltip: tooltip,
      constraints: BoxConstraints.tightFor(
        width: tokens.nodeSettingsCompactButtonHeight,
        height: tokens.nodeSettingsCompactButtonHeight,
      ),
      padding: EdgeInsets.zero,
      iconSize: tokens.zapSmallGlyphSize,
      color: tokens.dim,
      visualDensity: VisualDensity.compact,
      icon: Icon(icon),
    );
  }
}

class _NodeSettingsChip extends StatelessWidget {
  const _NodeSettingsChip({required this.pending, required this.connected});

  final bool pending;
  final bool connected;

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = AppTokens.of(context);
    final Color ink = pending
        ? tokens.qsrInk
        : connected
        ? tokens.znnInk
        : tokens.dim;
    final String label = pending
        ? context.l10n.nodeSettingsUpdating
        : connected
        ? context.l10n.nodeSettingsConnected
        : context.l10n.nodeSettingsUnknown;
    return Container(
      constraints: BoxConstraints(minHeight: tokens.nodeSettingsChipHeight),
      padding: EdgeInsets.symmetric(
        horizontal: tokens.nodeSettingsCompactButtonInset,
        vertical: tokens.fieldLabelGap / 2,
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(tokens.pillRadius),
        color: pending || connected ? ink.withValues(alpha: 0.14) : null,
        border: pending || connected ? null : Border.all(color: tokens.line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(
            pending
                ? Icons.sync
                : connected
                ? Icons.check
                : Icons.help_outline,
            size: tokens.zapSmallGlyphSize,
            color: ink,
          ),
          SizedBox(width: tokens.fieldLabelGap),
          Flexible(
            child: Text(
              label,
              style: tokens.nodeSettingsSubtitleText.copyWith(
                fontFamily: tokens.sansFontFamily,
                color: ink,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NodeSettingsPeers extends StatefulWidget {
  const _NodeSettingsPeers({required this.peers});

  final List<NodeSettingsPeer>? peers;

  @override
  State<_NodeSettingsPeers> createState() => _NodeSettingsPeersState();
}

class _NodeSettingsPeersState extends State<_NodeSettingsPeers> {
  bool _keySort = false;
  bool _ascending = true;

  void _sort({required bool publicKey}) {
    setState(() {
      _ascending = publicKey != _keySort || !_ascending;
      _keySort = publicKey;
    });
  }

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = AppTokens.of(context);
    final List<NodeSettingsPeer>? source = widget.peers;
    if (source == null || source.isEmpty) {
      return Padding(
        padding: tokens.settingsRowPadding,
        child: Text(
          source == null
              ? context.l10n.nodeSettingsUnknown
              : context.l10n.nodeSettingsNone,
          style: tokens.nodeSettingsSummaryText,
        ),
      );
    }
    final List<NodeSettingsPeer> peers = List<NodeSettingsPeer>.of(source)
      ..sort((NodeSettingsPeer a, NodeSettingsPeer b) {
        final String left = _keySort ? a.publicKey : a.ip;
        final String right = _keySort ? b.publicKey : b.ip;
        return _ascending ? left.compareTo(right) : right.compareTo(left);
      });
    return Padding(
      padding: tokens.settingsRowPadding,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: TextButton(
                  style: quietButtonStyle(context),
                  onPressed: () => _sort(publicKey: false),
                  child: Text(context.l10n.nodeSettingsPeerIp),
                ),
              ),
              Expanded(
                flex: 2,
                child: TextButton(
                  style: quietButtonStyle(context),
                  onPressed: () => _sort(publicKey: true),
                  child: Text(context.l10n.nodeSettingsPeerKey),
                ),
              ),
            ],
          ),
          for (final NodeSettingsPeer peer in peers)
            Padding(
              padding: EdgeInsets.symmetric(vertical: tokens.fieldLabelGap),
              child: Row(
                children: <Widget>[
                  Expanded(child: _buildPeerText(context, peer.ip)),
                  SizedBox(width: tokens.inlineGap),
                  Expanded(
                    flex: 2,
                    child: _buildPeerText(context, peer.publicKey),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPeerText(BuildContext context, String text) => Tooltip(
    message: text,
    child: Text(
      _nodeIdentifier(text),
      overflow: TextOverflow.ellipsis,
      textDirection: TextDirection.ltr,
      style: AppTokens.of(context).nodeSettingsSubtitleText,
    ),
  );
}
