part of 'transfer_page.dart';

const double _pendingRowHeight = 44;
const int _pendingViewportRows = 5;

/// Reduces repeated pages only by exact inbound hash, keeping node order.
List<AccountBlock> _inboundRows(List<AccountBlock> blocks) {
  final Map<Hash, AccountBlock> rows = <Hash, AccountBlock>{};
  for (final AccountBlock block in blocks) {
    final AccountBlock inbound = BlockUtils.isReceiveBlock(block.blockType)
        ? block.pairedAccountBlock ?? block
        : block;
    rows.putIfAbsent(inbound.hash, () => inbound);
  }
  return rows.values.toList();
}

class _TransferPending extends StatefulWidget {
  const _TransferPending({required this.showEmpty, required this.worker});

  final bool showEmpty;
  final AutoReceiveTxWorker worker;

  @override
  State<_TransferPending> createState() => _TransferPendingState();
}

class _TransferPendingState extends State<_TransferPending> {
  final ScrollController _scroll = ScrollController();
  bool _requestedMore = false;
  bool _receiveFailed = false;
  Hash? _receiving;
  final Map<String, Object> _rowTokens = <String, Object>{};

  void _rememberRows(List<AccountBlock> rows) {
    final Set<String> hashes = rows
        .map((AccountBlock block) => block.hash.toString())
        .toSet();
    _rowTokens.removeWhere((String hash, Object _) => !hashes.contains(hash));
    for (final String hash in hashes) {
      _rowTokens.putIfAbsent(hash, Object.new);
    }
  }

  bool _viewCurrent() =>
      mounted &&
      TickerMode.valuesOf(context).enabled &&
      (ModalRoute.of(context)?.isCurrent ?? true) &&
      (WidgetsBinding.instance.lifecycleState == null ||
          WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed);

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_nearBottom);
  }

  void _nearBottom() {
    if (_scroll.hasClients &&
        _scroll.position.extentAfter < _pendingRowHeight) {
      _requestMore();
    }
  }

  void _requestMore() {
    final PendingTransactionsBloc bloc = context
        .read<PendingTransactionsBloc>();
    final InfiniteListState<AccountBlock> state = bloc.state;
    final String? selected = kSelectedAddress;
    if (_requestedMore ||
        selected == null ||
        state.status != InfiniteListStatus.success ||
        state.hasReachedMax) {
      return;
    }
    setState(() => _requestedMore = true);
    bloc.add(InfiniteListMoreRequested(address: Address.parse(selected)));
  }

  void _refresh() {
    final String? selected = kSelectedAddress;
    if (selected == null) return;
    context.read<PendingTransactionsBloc>().add(
      InfiniteListRefreshRequested(address: Address.parse(selected)),
    );
  }

  Future<void> _receive(
    Hash hash,
    ReceiveOrigin origin,
    bool Function() current,
  ) async {
    final AutoReceiveTxWorker worker = widget.worker;
    // The per-hash hold survives publication; running guards every other
    // row while the worker is making or publishing a receive.
    if (!current() ||
        _receiving != null ||
        worker.running ||
        worker.inFlight.value.contains(hash)) {
      return;
    }
    setState(() {
      _receiving = hash;
      _receiveFailed = false;
    });
    try {
      if (!current()) return;
      await worker.autoReceiveTransactionHash(
        hash,
        origin: origin,
        sourceIsCurrent: current,
      );
    } on Object {
      if (current()) setState(() => _receiveFailed = true);
    } finally {
      if (mounted) setState(() => _receiving = null);
    }
  }

  @override
  void dispose() {
    _rowTokens.clear();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<
      PendingTransactionsBloc,
      InfiniteListState<AccountBlock>
    >(
      listener: (_, InfiniteListState<AccountBlock> state) {
        _requestedMore = false;
        _rememberRows(_inboundRows(state.data ?? <AccountBlock>[]));
      },
      builder: (BuildContext context, InfiniteListState<AccountBlock> state) {
        final AppTokens tokens = AppTokens.of(context);
        final bool known =
            state.status == InfiniteListStatus.success && state.data != null;
        final List<AccountBlock> rows = _inboundRows(
          state.data ?? <AccountBlock>[],
        );
        _rememberRows(rows);
        final bool empty = known && rows.isEmpty;
        if (empty && !widget.showEmpty) return const SizedBox.shrink();
        final bool? autoReceive =
            sharedPrefsService?.get(
                  kAutoReceiveKey,
                  defaultValue: kAutoReceiveDefaultValue,
                )
                as bool?;
        return Padding(
          padding: EdgeInsetsDirectional.only(top: tokens.pageGap),
          child: Panel(
            key: const Key('transfer_pending'),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Padding(
                  padding: EdgeInsetsDirectional.symmetric(
                    horizontal: tokens.cardPadding.left,
                    vertical: tokens.cardPadding.top,
                  ),
                  child: Row(
                    children: <Widget>[
                      Text(
                        context.l10n.transferToReceive,
                        style: tokens.headingText,
                      ),
                      if (rows.isNotEmpty) ...<Widget>[
                        SizedBox(width: tokens.cardGap),
                        Ltr(
                          child: Text(
                            '${rows.length}',
                            style: tokens.ledgerText,
                          ),
                        ),
                      ],
                      SizedBox(width: tokens.cardGap),
                      const Spacer(),
                      if (empty)
                        Flexible(
                          child: EmptyNote.line(
                            text: context.l10n.noItemsFound,
                          ),
                        )
                      else if (autoReceive != null)
                        Flexible(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              border: Border.all(color: tokens.line),
                              borderRadius: BorderRadius.circular(
                                tokens.pillRadius,
                              ),
                            ),
                            child: Padding(
                              padding: EdgeInsetsDirectional.symmetric(
                                horizontal: tokens.inlineGap,
                                vertical: tokens.fieldLabelGap,
                              ),
                              child: Text(
                                autoReceive
                                    ? context.l10n.transferAutoReceiveOn
                                    : context.l10n.transferAutoReceiveOff,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: tokens.captionText.copyWith(
                                  color: tokens.dim,
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                if (!empty) ...<Widget>[
                  Divider(height: 1, color: tokens.line),
                  if (state.status == InfiniteListStatus.initial ||
                      (state.status == InfiniteListStatus.success &&
                          state.data == null))
                    LinearProgressIndicator(
                      key: const Key('transfer_pending_loading'),
                      minHeight: tokens.focusWidth,
                      color: tokens.znnInk,
                    ),
                  if (state.status == InfiniteListStatus.failure)
                    _PendingFailure(
                      key: const Key('transfer_pending_failure'),
                      message: context.l10n.commonSomethingWentWrong,
                      onRetry: _refresh,
                    ),
                  if (_receiveFailed)
                    _PendingFailure(
                      message: context.l10n.autoReceiveFailedNotificationTitle,
                    ),
                  if (rows.isNotEmpty)
                    ValueListenableBuilder<Set<Hash>>(
                      valueListenable: widget.worker.inFlight,
                      builder: (BuildContext context, Set<Hash> inFlight, _) {
                        return SizedBox(
                          height:
                              math.min(rows.length, _pendingViewportRows) *
                              _pendingRowHeight,
                          child: ListView.builder(
                            key: const Key('transfer_pending_rows'),
                            controller: _scroll,
                            itemExtent: _pendingRowHeight,
                            itemCount: rows.length,
                            itemBuilder: (_, int index) {
                              final AccountBlock block = rows[index];
                              final AutoReceiveTxWorker worker = widget.worker;
                              final String hash = block.hash.toString();
                              final Object token = _rowTokens[hash]!;
                              bool sourceCurrent() =>
                                  _viewCurrent() &&
                                  identical(widget.worker, worker) &&
                                  identical(_rowTokens[hash], token);
                              final ReceiveOrigin? origin = worker
                                  .captureOrigin(
                                    sourceIsCurrent: sourceCurrent,
                                  );
                              bool current() =>
                                  sourceCurrent() &&
                                  (origin?.isCurrent ?? false);
                              final bool held =
                                  inFlight.contains(block.hash) ||
                                  _receiving == block.hash;
                              final bool blocked =
                                  held ||
                                  _receiving != null ||
                                  widget.worker.running ||
                                  BlockUtils.isReceiveBlock(block.blockType);
                              return _PendingRow(
                                key: ValueKey<String>(
                                  'transfer_pending_${block.hash}',
                                ),
                                block: block,
                                receiving: held,
                                onReceive: blocked || origin == null
                                    ? null
                                    : () => unawaited(
                                        _receive(
                                          Hash.parse(hash),
                                          origin,
                                          current,
                                        ),
                                      ),
                              );
                            },
                          ),
                        );
                      },
                    ),
                  if (known && !state.hasReachedMax)
                    TextButton(
                      key: const Key('transfer_pending_more'),
                      onPressed: _requestedMore ? null : _requestMore,
                      child: Text(context.l10n.commonShowMore),
                    ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _PendingFailure extends StatelessWidget {
  const _PendingFailure({required this.message, this.onRetry, super.key});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = AppTokens.of(context);
    return Padding(
      padding: EdgeInsetsDirectional.symmetric(
        horizontal: tokens.cardPadding.left,
        vertical: tokens.cardPadding.top,
      ),
      child: Row(
        children: <Widget>[
          Icon(
            Icons.error_outline_rounded,
            color: tokens.error,
            size: tokens.railIconSize,
          ),
          SizedBox(width: tokens.inlineGap),
          Expanded(
            child: Text(
              message,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: tokens.compactText.copyWith(color: tokens.error),
            ),
          ),
          if (onRetry != null)
            TextButton(
              onPressed: onRetry,
              child: Text(context.l10n.commonRetry),
            ),
        ],
      ),
    );
  }
}

class _PendingRow extends StatelessWidget {
  const _PendingRow({
    required this.block,
    required this.receiving,
    required this.onReceive,
    super.key,
  });

  final AccountBlock block;
  final bool receiving;
  final VoidCallback? onReceive;

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = AppTokens.of(context);
    final Token? token = block.token;
    final String address = block.address.toString();
    final String short = address.length > 16
        ? '${address.substring(0, 6)}…${address.substring(address.length - 4)}'
        : address;
    final int timestamp =
        (block.confirmationDetail?.momentumTimestamp ?? 0) * 1000;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: tokens.line)),
      ),
      child: Padding(
        padding: EdgeInsetsDirectional.symmetric(
          horizontal: tokens.cardPadding.left,
        ),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Tooltip(
                message: address,
                child: Text(
                  short,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textDirection: TextDirection.ltr,
                  textAlign: ltrTextAlign(context),
                  style: tokens.dataText.copyWith(color: tokens.dim),
                ),
              ),
            ),
            SizedBox(width: tokens.cardGap),
            Expanded(
              child: Tooltip(
                message: block.hash.toString(),
                child: Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: token == null
                      ? Text(context.l10n.pending, style: tokens.captionText)
                      : HiddenAmount(
                          child: AmountText(
                            block.amount,
                            decimals: token.decimals,
                            symbol: token.symbol,
                            style: tokens.dataText,
                          ),
                        ),
                ),
              ),
            ),
            SizedBox(width: tokens.cardGap),
            Expanded(
              child: Text(
                timestamp == 0
                    ? context.l10n.pending
                    : FormatUtils.formatDateForTable(timestamp),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: tokens.compactText.copyWith(color: tokens.dim),
              ),
            ),
            SizedBox(width: tokens.cardGap),
            SizedBox(
              width: tokens.fieldHeight * 2.5,
              child: OutlinedButton(
                key: ValueKey<String>('receive_${block.hash}'),
                style: cardSecondaryButtonStyle(context).copyWith(
                  minimumSize: WidgetStatePropertyAll<Size>(
                    Size(0, tokens.smallButtonHeight),
                  ),
                ),
                onPressed: onReceive,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    if (receiving) ...<Widget>[
                      SizedBox.square(
                        dimension: tokens.inlineGap,
                        child: CircularProgressIndicator(
                          strokeWidth: tokens.focusWidth,
                          color: tokens.dim,
                        ),
                      ),
                      SizedBox(width: tokens.fieldLabelGap),
                    ],
                    Flexible(
                      child: Text(
                        receiving
                            ? context.l10n.transferReceiving
                            : context.l10n.receive,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
