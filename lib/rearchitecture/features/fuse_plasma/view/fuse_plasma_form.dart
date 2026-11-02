import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/card_parts/card_parts.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/home/widgets/amount_text.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/utils.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/ltr.dart';
import 'package:zenon_syrius_wallet_flutter/utils/utils.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/widgets.dart';

/// A beneficiary captured from the wallet's existing address list.
class FusePlasmaBeneficiary {
  /// A captured wallet address and its display label.
  const FusePlasmaBeneficiary({
    required this.address,
    required this.label,
    this.isAddress = false,
  });

  /// The exact beneficiary, independent of the label.
  final String address;

  /// The captured wallet label or shortened address.
  final String label;

  /// An identifier uses mono text and reads left to right.
  final bool isAddress;
}

/// The production Fuse controls, independent of wallet and RPC construction.
/// Validation, exact parsing and publication remain with the owning card.
class FusePlasmaForm extends StatefulWidget {
  /// Draws the same production fields without constructing a publication owner.
  const FusePlasmaForm({
    required this.amountController,
    required this.beneficiaryController,
    required this.amountFocusNode,
    required this.buttonKey,
    required this.beneficiaries,
    required this.amount,
    required this.decimals,
    required this.amountEnabled,
    required this.inputValid,
    required this.amountError,
    required this.beneficiaryError,
    required this.isCurrent,
    required this.onMax,
    required this.onSubmit,
    this.showAnother = false,
    this.onAnother,
    super.key,
  });

  /// Retained exact text entered for the amount.
  final TextEditingController amountController;

  /// Retained exact beneficiary shared with the page's address selection.
  final TextEditingController beneficiaryController;

  /// The owner's amount focus, preserved across disclosure changes.
  final FocusNode amountFocusNode;

  /// The original loading button, independent of balance refreshes.
  final GlobalKey<LoadingButtonState> buttonKey;

  /// Wallet choices captured by the owning form.
  final List<FusePlasmaBeneficiary> beneficiaries;

  /// Exact parsed QSR units used only for the action's display.
  final BigInt amount;

  /// Decimal precision of the exact displayed amount.
  final int decimals;

  /// Whether a validated retained balance permits amount editing.
  final bool amountEnabled;

  /// The owning form's validation and publication hold decision.
  final bool inputValid;

  /// The owning form's amount validation message.
  final String? amountError;

  /// The owning form's beneficiary validation message.
  final String? beneficiaryError;

  /// Captured opening, draft and page authority for every retained callback.
  final bool Function() isCurrent;

  /// Fills the retained exact maximum supplied by the owning form.
  final VoidCallback onMax;

  /// Requests publication through the owning form's shared sender guard.
  final VoidCallback onSubmit;

  /// A held original exposes an explicit next-draft control.
  final bool showAnother;

  /// Enabled only by positive exact confirmation of the held original.
  final VoidCallback? onAnother;

  @override
  State<FusePlasmaForm> createState() => _FusePlasmaFormState();
}

class _FusePlasmaFormState extends State<FusePlasmaForm> {
  final TextEditingController _another = TextEditingController();
  final FocusNode _anotherFocus = FocusNode();
  bool _showAnother = false;
  bool _changingChoice = false;

  FusePlasmaBeneficiary? get _chosen {
    for (final FusePlasmaBeneficiary item in widget.beneficiaries) {
      if (item.address == widget.beneficiaryController.text) return item;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _showAnother = _chosen == null;
    if (_showAnother) _another.value = widget.beneficiaryController.value;
    _another.addListener(_onAnotherEdited);
    widget.beneficiaryController.addListener(_onBeneficiaryChanged);
  }

  @override
  void didUpdateWidget(FusePlasmaForm oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.beneficiaryController != widget.beneficiaryController) {
      oldWidget.beneficiaryController.removeListener(_onBeneficiaryChanged);
      widget.beneficiaryController.addListener(_onBeneficiaryChanged);
      _syncBeneficiary();
    } else if (oldWidget.beneficiaries != widget.beneficiaries) {
      _syncBeneficiary();
    }
  }

  void _onAnotherEdited() {
    if (!_showAnother || _changingChoice) return;
    _changingChoice = true;
    widget.beneficiaryController.value = _another.value;
    _changingChoice = false;
  }

  void _syncBeneficiary() {
    _showAnother = _chosen == null;
    if (_showAnother) {
      _changingChoice = true;
      _another.value = widget.beneficiaryController.value;
      _changingChoice = false;
    }
  }

  void _onBeneficiaryChanged() {
    if (_changingChoice) return;
    setState(_syncBeneficiary);
  }

  void _pick(int index, bool Function() isCurrent) {
    if (!isCurrent() || index < -1 || index >= widget.beneficiaries.length) {
      return;
    }
    _changingChoice = true;
    setState(() {
      _showAnother = index < 0;
      if (_showAnother) {
        widget.beneficiaryController.value = _another.value;
      } else {
        widget.beneficiaryController.text = widget.beneficiaries[index].address;
      }
    });
    _changingChoice = false;
    if (_showAnother) _anotherFocus.requestFocus();
  }

  @override
  void dispose() {
    widget.beneficiaryController.removeListener(_onBeneficiaryChanged);
    _another.dispose();
    _anotherFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = AppTokens.of(context);
    final ThemeData theme = Theme.of(context);
    final bool Function() isCurrent = widget.isCurrent;
    final bool inputValid = widget.inputValid;
    void submit() {
      if (isCurrent() && inputValid) widget.onSubmit();
    }

    final InputDecorationThemeData fields = theme.inputDecorationTheme.copyWith(
      filled: true,
      isDense: true,
      contentPadding: tokens.transferFieldPadding,
      constraints: BoxConstraints(minHeight: tokens.fieldHeight),
      suffixIconColor: tokens.faint,
      hintStyle: tokens.plasmaFuseHintText,
    );
    return Theme(
      data: theme.copyWith(inputDecorationTheme: fields),
      child: FocusTraversalGroup(
        policy: OrderedTraversalPolicy(),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              padding: tokens.plasmaFuseFormPadding,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(
                    flex: 10,
                    child: _FieldGroup(
                      label: context.l10n.amount,
                      child: FocusTraversalOrder(
                        order: const NumericFocusOrder(1),
                        child: AmountRefusalScope(
                          controller: widget.amountController,
                          builder: (_, String? refusal) => TextField(
                            key: const Key('fuse_plasma_amount_field'),
                            controller: widget.amountController,
                            focusNode: widget.amountFocusNode,
                            enabled: widget.amountEnabled,
                            style: tokens.plasmaFuseAmountText.copyWith(
                              height: 1.2,
                            ),
                            textDirection: TextDirection.ltr,
                            textAlign: ltrTextAlign(context, TextAlign.start),
                            decoration: InputDecoration(
                              errorText: refusal ?? widget.amountError,
                              suffixIconConstraints: BoxConstraints(
                                minHeight: tokens.fieldHeight,
                              ),
                              suffixIcon: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: <Widget>[
                                  FocusTraversalOrder(
                                    order: const NumericFocusOrder(3),
                                    child: CardFieldAction(
                                      label: context.l10n.max,
                                      onPressed: widget.amountEnabled
                                          ? () {
                                              if (isCurrent()) widget.onMax();
                                            }
                                          : null,
                                    ),
                                  ),
                                  Padding(
                                    padding: EdgeInsetsDirectional.only(
                                      end: tokens.inlineGap,
                                    ),
                                    child: Text(
                                      'QSR',
                                      textDirection: TextDirection.ltr,
                                      style: tokens.dataText.copyWith(
                                        color: tokens.qsrInk,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            inputFormatters: const <TextInputFormatter>[
                              AmountInputFormatter(),
                            ],
                            onSubmitted: (_) => submit(),
                          ),
                        ),
                      ),
                    ),
                  ),
                  SizedBox(width: tokens.pageGap),
                  Expanded(
                    flex: 14,
                    child: _FieldGroup(
                      label: context.l10n.plasmaFuseFor,
                      child: _buildBeneficiary(context, isCurrent),
                    ),
                  ),
                  SizedBox(width: tokens.pageGap),
                  Flexible(
                    flex: 12,
                    child: _FieldGroup(
                      label: '',
                      child: FocusTraversalOrder(
                        order: const NumericFocusOrder(6),
                        child: KeyedSubtree(
                          key: const Key('fuse_plasma_submit_button'),
                          child: LoadingButton(
                            key: widget.buttonKey,
                            minimumSize: Size(
                              104,
                              tokens.plasmaFuseActionHeight,
                            ),
                            paddingAroundChild: EdgeInsets.symmetric(
                              horizontal:
                                  tokens.plasmaFuseFormPadding.horizontal / 2,
                            ),
                            circularBorderRadius: tokens.pillRadius,
                            onPressed: inputValid && isCurrent()
                                ? submit
                                : null,
                            child: _ActionAmount(
                              amount: widget.amount,
                              decimals: widget.decimals,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: tokens.plasmaFuseNotePadding,
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      context.l10n.plasmaFuseLockNote,
                      style: tokens.plasmaFuseHintText,
                    ),
                  ),
                  if (widget.showAnother)
                    OutlinedButton(
                      key: const Key('plasma_fuse_another'),
                      style: cardSecondaryButtonStyle(context),
                      onPressed: widget.onAnother == null
                          ? null
                          : () {
                              if (isCurrent()) widget.onAnother!();
                            },
                      child: Text(context.l10n.plasmaFuseAnotherAction),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBeneficiary(BuildContext context, bool Function() isCurrent) {
    final AppTokens tokens = AppTokens.of(context);
    if (_showAnother) {
      return FocusTraversalOrder(
        order: const NumericFocusOrder(2),
        child: TextField(
          key: const Key('fuse_plasma_beneficiary_address_field'),
          controller: _another,
          focusNode: _anotherFocus,
          style: tokens.dataText,
          textDirection: TextDirection.ltr,
          textAlign: ltrTextAlign(context, TextAlign.start),
          decoration: InputDecoration(
            errorText: widget.beneficiaryError,
            hintText: context.l10n.plasmaFuseAnotherAddress,
            suffixIconConstraints: BoxConstraints(
              minHeight: tokens.fieldHeight,
            ),
            suffixIcon: IconButtonTheme(
              data: IconButtonThemeData(
                style: IconButton.styleFrom(
                  minimumSize: Size.square(tokens.compactButtonHeight),
                  padding: EdgeInsets.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  FocusTraversalOrder(
                    order: const NumericFocusOrder(4),
                    child: FieldSuffixButtons(controller: _another),
                  ),
                  FocusTraversalOrder(
                    order: const NumericFocusOrder(5),
                    child: _buildMenu(context, isCurrent),
                  ),
                ],
              ),
            ),
          ),
          inputFormatters: <TextInputFormatter>[
            FilteringTextInputFormatter.allow(RegExp('[0-9a-z]')),
          ],
          onSubmitted: (_) {
            if (isCurrent()) widget.amountFocusNode.requestFocus();
          },
        ),
      );
    }
    final FusePlasmaBeneficiary chosen = _chosen!;
    return FocusTraversalOrder(
      order: const NumericFocusOrder(2),
      child: _buildMenu(
        context,
        isCurrent,
        child: InputDecorator(
          decoration: const InputDecoration(),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Tooltip(
                  message: chosen.address,
                  child: Text(
                    chosen.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textDirection: chosen.isAddress ? TextDirection.ltr : null,
                    style: chosen.isAddress ? tokens.dataText : tokens.bodyText,
                  ),
                ),
              ),
              SizedBox(width: tokens.inlineGap),
              Text(
                context.l10n.plasmaFuseAnotherAddress,
                style: tokens.plasmaFuseHintText,
              ),
              Icon(Icons.expand_more, size: tokens.heroIconSize),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMenu(
    BuildContext context,
    bool Function() isCurrent, {
    Widget? child,
  }) => PopupMenuButton<int>(
    key: const Key('fuse_plasma_beneficiary_selector'),
    tooltip: context.l10n.plasmaFuseFor,
    icon: child == null
        ? Icon(Icons.expand_more, size: AppTokens.of(context).heroIconSize)
        : null,
    enabled: isCurrent(),
    onSelected: (int index) => _pick(index, isCurrent),
    itemBuilder: (BuildContext context) => <PopupMenuEntry<int>>[
      for (int index = 0; index < widget.beneficiaries.length; index++)
        PopupMenuItem<int>(
          key: ValueKey<String>('fuse_plasma_beneficiary_option_$index'),
          value: index,
          child: Tooltip(
            message: widget.beneficiaries[index].address,
            child: Text(
              widget.beneficiaries[index].label,
              textDirection: widget.beneficiaries[index].isAddress
                  ? TextDirection.ltr
                  : null,
              style: widget.beneficiaries[index].isAddress
                  ? AppTokens.of(context).dataText
                  : AppTokens.of(context).bodyText,
            ),
          ),
        ),
      PopupMenuItem<int>(
        key: const Key('fuse_plasma_another_address_option'),
        value: -1,
        child: Text(context.l10n.plasmaFuseAnotherAddress),
      ),
    ],
    child: child,
  );
}

class _FieldGroup extends StatelessWidget {
  const _FieldGroup({required this.label, required this.child});
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = AppTokens.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        // A blank action label keeps controls aligned when validation adds
        // a line below either field.
        Text(
          label.isEmpty ? ' ' : label.toUpperCase(),
          style: tokens.ledgerText,
        ),
        SizedBox(height: tokens.transferRecentGap),
        child,
      ],
    );
  }
}

class _ActionAmount extends StatelessWidget {
  const _ActionAmount({required this.amount, required this.decimals});
  final BigInt amount;
  final int decimals;

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = AppTokens.of(context);
    const String marker = '\uFFFC';
    final String label = context.l10n.plasmaFuseAction(marker);
    final int index = label.indexOf(marker);
    return Text.rich(
      TextSpan(
        children: <InlineSpan>[
          TextSpan(text: label.substring(0, index)),
          WidgetSpan(
            alignment: PlaceholderAlignment.baseline,
            baseline: TextBaseline.alphabetic,
            child: AmountText(
              amount,
              decimals: decimals,
              style: monoStyle(tokens.buttonText),
            ),
          ),
          TextSpan(text: label.substring(index + marker.length)),
        ],
      ),
      style: tokens.buttonText,
    );
  }
}
