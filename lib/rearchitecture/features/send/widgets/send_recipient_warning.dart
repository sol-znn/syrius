part of 'send_populated.dart';

class _SendRecipientWarning extends StatelessWidget {
  const _SendRecipientWarning({
    required this.finding,
    required this.typed,
    required this.name,
    required this.acknowledged,
    required this.onUseKnown,
    required this.onUseTyped,
  });

  final LookAlike finding;
  final String typed;
  final String name;
  final bool acknowledged;
  final VoidCallback? onUseKnown;
  final VoidCallback? onUseTyped;

  Widget _buildAddress(BuildContext context, String address, String key) {
    final AppTokens tokens = AppTokens.of(context);
    return Tooltip(
      message: address,
      child: SelectableText.rich(
        TextSpan(
          style: tokens.dataText.copyWith(color: tokens.dim),
          children: <InlineSpan>[
            for (int index = 0; index < address.length; index++)
              TextSpan(
                text: address[index],
                style: finding.differing.contains(index)
                    ? TextStyle(
                        color: key == 'send_typed_address'
                            ? tokens.warn
                            : tokens.foreground,
                      )
                    : null,
              ),
          ],
        ),
        key: Key(key),
        textDirection: TextDirection.ltr,
        textAlign: ltrTextAlign(context),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = AppTokens.of(context);
    return Container(
      key: const Key('send_recipient_warning'),
      padding: tokens.transferWarningPadding,
      decoration: BoxDecoration(
        color: tokens.transferWarningTint,
        borderRadius: BorderRadius.circular(tokens.transferControlRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Icon(
                Icons.warning_amber_rounded,
                size: tokens.heroIconSize,
                color: tokens.warn,
              ),
              SizedBox(width: tokens.inlineGap),
              Expanded(
                child: Text(
                  context.l10n.sendLooksLike(name),
                  style: tokens.headingText,
                ),
              ),
            ],
          ),
          SizedBox(height: tokens.inlineGap),
          Text(
            context.l10n.sendLookAlikeDetail,
            style: tokens.transferCaptionText,
          ),
          SizedBox(height: tokens.inlineGap),
          Text(context.l10n.sendKnownAddress, style: tokens.ledgerText),
          _buildAddress(context, finding.address, 'send_known_address'),
          SizedBox(height: tokens.fieldLabelGap),
          Text(context.l10n.sendTypedAddress, style: tokens.ledgerText),
          _buildAddress(context, typed, 'send_typed_address'),
          SizedBox(height: tokens.inlineGap),
          Wrap(
            spacing: tokens.inlineGap,
            runSpacing: tokens.fieldLabelGap,
            children: <Widget>[
              OutlinedButton(
                key: const Key('send_use_known'),
                onPressed: onUseKnown,
                child: Text(context.l10n.sendUseKnown(name)),
              ),
              TextButton(
                key: const Key('send_use_typed'),
                onPressed: onUseTyped,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    if (acknowledged) ...<Widget>[
                      Icon(Icons.check, size: tokens.heroCopyIconSize),
                      SizedBox(width: tokens.fieldLabelGap),
                    ],
                    Flexible(child: Text(context.l10n.sendUseTypedAnyway)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
