part of 'transfer_page.dart';

class _TransferReceiver extends StatelessWidget {
  const _TransferReceiver({required this.controller});

  final ReceiveHeaderController controller;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (BuildContext context, Widget? child) {
      final ReceiveHeaderSnapshot? choices = controller.snapshot;
      if (choices == null) return const SizedBox.shrink();
      final AppTokens tokens = AppTokens.of(context);
      return MenuAnchor(
        menuChildren: <Widget>[
          for (final MapEntry<String, String> option in choices.labels.entries)
            MenuItemButton(
              onPressed: () => controller.select(choices, option.key),
              child: Text(option.value),
            ),
        ],
        builder: (_, MenuController menu, Widget? child) => TextButton(
          key: const Key('transfer_receiver'),
          onPressed: () {
            if (!identical(controller.snapshot, choices)) return;
            if (menu.isOpen) {
              menu.close();
            } else {
              menu.open();
            }
          },
          style: TextButton.styleFrom(
            foregroundColor: tokens.foreground,
            backgroundColor: tokens.card2,
            minimumSize: Size(0, tokens.compactButtonHeight),
            padding: tokens.transferChipPadding,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(tokens.transferControlRadius),
              side: BorderSide(color: tokens.line),
            ),
            textStyle: tokens.compactText,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Flexible(
                child: Text(
                  choices.labels[choices.selected]!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              SizedBox(width: tokens.transferRecentGap),
              Icon(Icons.expand_more, size: tokens.activityIconSize),
            ],
          ),
        ),
      );
    },
  );
}

class _TransferSender extends StatelessWidget {
  const _TransferSender();

  @override
  Widget build(BuildContext context) {
    final SendDraftCubit? draft = context.read<SendDraftCubit?>();
    if (draft == null) return const SizedBox.shrink();
    return BlocBuilder<MultipleBalanceBloc, MultipleBalanceState>(
      builder: (_, MultipleBalanceState state) {
        final Map<String, AccountInfo>? balances = state.data;
        final List<String> addresses =
            balances?.keys.where(kDefaultAddressList.contains).toList() ??
            <String>[];
        if (state.status != MultipleBalanceStatus.success ||
            addresses.isEmpty) {
          return const SizedBox.shrink();
        }
        return BlocBuilder<SendDraftCubit, SendDraft>(
          bloc: draft,
          builder: (_, SendDraft value) {
            final String selected = addresses.contains(value.fromAddress)
                ? value.fromAddress!
                : addresses.contains(kSelectedAddress)
                ? kSelectedAddress!
                : addresses.first;
            final ValueListenable<bool> busy = context
                .read<SendTransactionBloc>()
                .busy;
            final AppTokens tokens = AppTokens.of(context);
            String label(String address) =>
                kAddressLabelMap[address] ??
                sentPartyName(address, const <String, String>{});
            return ValueListenableBuilder<bool>(
              valueListenable: busy,
              builder: (_, bool blocked, _) => PopupMenuButton<String>(
                key: const Key('transfer_sender'),
                enabled: !blocked,
                tooltip: context.l10n.send,
                initialValue: selected,
                itemBuilder: (_) => <PopupMenuEntry<String>>[
                  for (final String address in addresses)
                    PopupMenuItem<String>(
                      value: address,
                      child: Text(label(address)),
                    ),
                ],
                onSelected: (String address) {
                  if (!context.mounted || busy.value || draft.isClosed) return;
                  if (!addresses.contains(address) ||
                      !kDefaultAddressList.contains(address)) {
                    return;
                  }
                  final MultipleBalanceState latest = context
                      .read<MultipleBalanceBloc>()
                      .state;
                  if (latest.status != MultipleBalanceStatus.success ||
                      !(latest.data?.containsKey(address) ?? false)) {
                    return;
                  }
                  final SendDraft current = draft.state;
                  draft.save(
                    fromAddress: address,
                    tokenStandard:
                        current.tokenStandard ??
                        kZnnCoin.tokenStandard.toString(),
                    recipient: current.recipient,
                    amount: current.amount,
                  );
                },
                child: Container(
                  constraints: BoxConstraints(
                    minHeight: tokens.compactButtonHeight,
                  ),
                  padding: tokens.transferChipPadding,
                  decoration: BoxDecoration(
                    color: tokens.card2,
                    borderRadius: BorderRadius.circular(
                      tokens.transferControlRadius,
                    ),
                    border: Border.all(color: tokens.line),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Flexible(
                        child: Text(
                          label(selected),
                          style: tokens.compactText,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      SizedBox(width: tokens.transferRecentGap),
                      Flexible(
                        child: HiddenAmount(
                          style: tokens.captionText,
                          child: Text(
                            balances![selected]!
                                .getBalance(kZnnCoin.tokenStandard)
                                .addDecimals(kZnnCoin.decimals),
                            style: tokens.captionText,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                      Text(' ZNN', style: tokens.captionText),
                      Icon(
                        Icons.expand_more,
                        size: tokens.activityIconSize,
                        color: tokens.faint,
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
