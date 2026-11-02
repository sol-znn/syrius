import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/main.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/card_parts/card_parts.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/features.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/utils.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/eye_toggle.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/ltr.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/segment.dart';
import 'package:zenon_syrius_wallet_flutter/utils/utils.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/reusable_widgets/buttons/primary_pill.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/reusable_widgets/buttons/sheen.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/reusable_widgets/input_fields/amount_input_field.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

const double _kDurationWidth = 300;
const double _kUnlockWidth = 140;
const double _kButtonMinWidth = 120;
const double _kInlineFormWidth = 1000;
const List<int> _kMonthPresets = <int>[1, 2, 3, 6, 9, 12];

String _unlockDate(BuildContext context, Duration duration) {
  final DateTime unlocks = DateTime.now().add(duration);
  final Locale locale = Localizations.localeOf(context);
  return locale.languageCode == 'en'
      ? DateFormat('d MMM yyyy', 'en').format(unlocks)
      : FormatUtils.formatDate(unlocks.millisecondsSinceEpoch, locale: locale);
}

/// Creates a stake from the selected address without replacing its live flow.
class CreateStakeCard extends StatelessWidget {
  /// Creates the stake form.
  const CreateStakeCard({
    required this.onStakeCreated,
    this.framed = true,
    this.createTransactionBloc,
    this.onStakePublished,
    super.key,
  });

  /// Called after the stake block is created successfully.
  final VoidCallback onStakeCreated;

  /// Observes the original accepted block without changing its result.
  final ValueChanged<AccountBlockTemplate>? onStakePublished;

  /// Whether a title surrounds the form. The page disclosure supplies its own.
  final bool framed;

  /// Overrides transaction construction while retaining the same event flow.
  /// The provider owns and closes the returned bloc.
  final SendTransactionBloc Function()? createTransactionBloc;

  @override
  Widget build(BuildContext context) => BlocProvider<SendTransactionBloc>(
    create: (_) => createTransactionBloc?.call() ?? SendTransactionBloc(),
    child: _View(
      onStakeCreated: onStakeCreated,
      onStakePublished: onStakePublished,
      framed: framed,
    ),
  );
}

class _View extends StatelessWidget {
  const _View({
    required this.onStakeCreated,
    required this.framed,
    this.onStakePublished,
  });

  final VoidCallback onStakeCreated;

  /// Observes the original accepted block without changing its result.
  final ValueChanged<AccountBlockTemplate>? onStakePublished;
  final bool framed;

  @override
  Widget build(BuildContext context) {
    context.watch<SelectedAddressNotifier>();
    final Widget body = BlocBuilder<MultipleBalanceBloc, MultipleBalanceState>(
      builder: (_, MultipleBalanceState state) {
        final AccountInfo? accountInfo = state.data?[kSelectedAddress];
        return StateSwitcher(
          child: switch (state.status) {
            MultipleBalanceStatus.failure => CardNote.error(
              state.error!,
              key: const ValueKey<String>('failure'),
            ),
            // A balance refresh retains the mounted draft.
            _ when accountInfo != null => _Populated(
              key: ValueKey<String?>('form_$kSelectedAddress'),
              accountInfo: accountInfo,
              onStakeCreated: onStakeCreated,
              onStakePublished: onStakePublished,
              framed: framed,
            ),
            _ => const _Loading(key: ValueKey<String>('loading')),
          },
        );
      },
    );
    return Panel(
      title: framed ? context.l10n.stakingNewStake : null,
      shrinkWrap: framed,
      child: body,
    );
  }
}

void _fetchBalance() {
  sl.get<MultipleBalanceBloc>().add(
    MultipleBalanceFetch(
      addresses: kDefaultAddressList
          .map((String? address) => address!)
          .toList(),
    ),
  );
}

class _Loading extends StatelessWidget {
  const _Loading({super.key});

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = AppTokens.of(context);
    return Padding(
      padding: tokens.stripPadding.copyWith(
        top: tokens.panelGap,
        bottom: tokens.panelGap,
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Skeleton(
              height: tokens.fieldHeight,
              radius: tokens.cardRadius,
            ),
          ),
          SizedBox(width: tokens.panelGap),
          Skeleton(
            width: _kButtonMinWidth,
            height: tokens.fieldHeight,
            radius: tokens.pillRadius,
          ),
        ],
      ),
    );
  }
}

class _Populated extends StatefulWidget {
  const _Populated({
    required this.accountInfo,
    required this.onStakeCreated,
    required this.framed,
    this.onStakePublished,
    super.key,
  });

  final AccountInfo accountInfo;
  final VoidCallback onStakeCreated;

  /// Observes the original accepted block without changing its result.
  final ValueChanged<AccountBlockTemplate>? onStakePublished;
  final bool framed;

  @override
  State<_Populated> createState() => _PopulatedState();
}

class _PopulatedState extends State<_Populated> {
  final TextEditingController _amountController = TextEditingController();
  final FocusNode _amountFocusNode = FocusNode();
  final SheenController _submitSheen = SheenController();
  Duration? _selectedStakeDuration;
  bool _submitting = false;

  BigInt get _maxZnnAmount =>
      widget.accountInfo.getBalance(kZnnCoin.tokenStandard);

  String get _amount => _amountController.text;

  String? get _amountErrorText => _amount.isNotEmpty
      ? InputValidators.correctValue(
          _amount,
          _maxZnnAmount,
          kZnnCoin.decimals,
          stakeMinZnnAmount,
          canBeEqualToMin: true,
        )
      : null;

  bool get _isInputValid {
    final int? seconds = _selectedStakeDuration?.inSeconds;
    return seconds != null &&
        seconds >= stakeTimeUnitSec &&
        seconds <= stakeTimeMaxSec &&
        seconds % stakeTimeUnitSec == 0 &&
        _amount.isNotEmpty &&
        _amountErrorText == null;
  }

  @override
  void dispose() {
    _amountController.dispose();
    _amountFocusNode.dispose();
    _submitSheen.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = AppTokens.of(context);
    final bool busy =
        _submitting ||
        context.select<SendTransactionBloc, bool>(
          (SendTransactionBloc bloc) =>
              bloc.state.status == SendTransactionStatus.loading,
        );
    final int? selectedMonths = _selectedStakeDuration == null
        ? null
        : _selectedStakeDuration!.inSeconds ~/ stakeTimeUnitSec;
    // A held valid draft also survives a change to the displayed presets.
    final List<int> months = <int>{
      ..._kMonthPresets.where(
        (int month) => month * stakeTimeUnitSec <= stakeTimeMaxSec,
      ),
      if (selectedMonths != null &&
          selectedMonths > 0 &&
          selectedMonths * stakeTimeUnitSec <= stakeTimeMaxSec)
        selectedMonths,
    }.toList()..sort();
    final Widget duration = FocusTraversalOrder(
      order: const NumericFocusOrder(1),
      child: _Control(
        label: context.l10n.duration,
        child: IgnorePointer(
          ignoring: busy,
          child: ExcludeFocus(
            excluding: busy,
            child: Segment<int>(
              keyPrefix: 'create_stake_months',
              items: <SegmentItem<int>>[
                for (final int month in months)
                  SegmentItem<int>(
                    value: month,
                    label: month == months.last
                        ? context.l10n.stakeDurationMonths(month)
                        : MaterialLocalizations.of(
                            context,
                          ).formatDecimal(month),
                  ),
              ],
              selected: selectedMonths,
              onChanged: (int month) => _onStakeDurationChanged(
                Duration(seconds: month * stakeTimeUnitSec),
              ),
            ),
          ),
        ),
      ),
    );
    final Widget amount = FocusTraversalOrder(
      order: const NumericFocusOrder(2),
      child: _Control(
        label: context.l10n.amount,
        child: ValueListenableBuilder<TextEditingValue>(
          valueListenable: _amountController,
          builder: (_, TextEditingValue value, _) => AmountRefusalScope(
            controller: _amountController,
            builder: (_, String? refusal) => TextField(
              key: const Key('create_stake_amount_field'),
              controller: _amountController,
              focusNode: _amountFocusNode,
              enabled: !busy,
              textDirection: TextDirection.ltr,
              style: tokens.dataText.copyWith(fontSize: 18),
              decoration: InputDecoration(
                errorText: refusal ?? _amountErrorText,
                hintText: '0',
                filled: true,
                fillColor: tokens.card2,
                isDense: true,
                constraints: BoxConstraints(minHeight: tokens.fieldHeight),
                contentPadding: EdgeInsetsDirectional.symmetric(
                  horizontal: tokens.pageGap,
                  vertical: tokens.inlineGap,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(tokens.cardRadius),
                  borderSide: BorderSide(color: tokens.line),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(tokens.cardRadius),
                  borderSide: BorderSide(color: tokens.line),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(tokens.cardRadius),
                  borderSide: BorderSide(color: tokens.faint),
                ),
                suffixIconConstraints: BoxConstraints(
                  maxWidth: 220,
                  minHeight: tokens.fieldHeight,
                ),
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    TextButton(
                      key: const Key('create_stake_max_button'),
                      style: TextButton.styleFrom(
                        foregroundColor: tokens.znnInk,
                        disabledForegroundColor: tokens.faint,
                        minimumSize: Size(0, tokens.fieldHeight),
                        padding: EdgeInsetsDirectional.symmetric(
                          horizontal: tokens.inlineGap,
                        ),
                      ),
                      onPressed: !busy && _maxZnnAmount > BigInt.zero
                          ? _onMaxPressed
                          : null,
                      child: Text(context.l10n.max),
                    ),
                    Flexible(
                      child: Padding(
                        padding: EdgeInsetsDirectional.only(
                          end: tokens.pageGap,
                        ),
                        child: ValueFlash(
                          key: ValueKey<String?>('balance_$kSelectedAddress'),
                          value: _maxZnnAmount,
                          color: tokens.znnInk,
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: HiddenAmount(
                              style: tokens.dataText.copyWith(fontSize: 13),
                              child: Ltr(
                                child: Text(
                                  context.l10n.stakingAmountOf(
                                    cardAmount(
                                      _maxZnnAmount,
                                      kZnnCoin.decimals,
                                      '',
                                    ),
                                  ),
                                  maxLines: 1,
                                  style: tokens.dataText.copyWith(
                                    fontSize: 13,
                                    color: tokens.dim,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              inputFormatters: FormatUtils.getAmountTextInputFormatters(
                value.text,
              ),
              onSubmitted: (_) => _onStakePressed(),
            ),
          ),
        ),
      ),
    );
    final Duration? selected = _selectedStakeDuration;
    final Widget unlocks = _Control(
      label: context.l10n.stakingUnlocks,
      child: SizedBox(
        height: tokens.fieldHeight,
        child: Align(
          alignment: AlignmentDirectional.centerStart,
          child: Ltr(
            child: Text(
              selected == null ? '' : _unlockDate(context, selected),
              key: const Key('create_stake_unlock_date'),
              style: tokens.dataText,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ),
    );
    final Widget submit = FocusTraversalOrder(
      order: const NumericFocusOrder(3),
      child: ListenableBuilder(
        listenable: _amountController,
        builder: (_, _) => PrimaryPill(
          key: const Key('create_stake_submit_button'),
          sheen: _submitSheen,
          style: OutlinedButton.styleFrom(
            minimumSize: Size(_kButtonMinWidth, tokens.fieldHeight),
            padding: EdgeInsetsDirectional.symmetric(
              horizontal: tokens.pageGap,
            ),
          ),
          onPressed: !busy && _isInputValid ? _onStakePressed : null,
          child: busy
              ? SizedBox.square(
                  dimension: tokens.inlineGap * 2,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: tokens.primaryButtonForeground,
                  ),
                )
              : Text(
                  _isInputValid
                      ? context.l10n.stakingStakeAmount(
                          cardAmount(
                            _amount.extractDecimals(kZnnCoin.decimals),
                            kZnnCoin.decimals,
                            '',
                          ),
                        )
                      : context.l10n.stake,
                  maxLines: 1,
                ),
        ),
      ),
    );
    return BlocListener<SendTransactionBloc, SendTransactionState>(
      listener: (_, SendTransactionState state) =>
          _onTransactionStateChanged(state),
      child: FocusTraversalGroup(
        policy: OrderedTraversalPolicy(),
        child: Padding(
          padding: tokens.stripPadding.copyWith(
            top: tokens.panelGap,
            bottom: tokens.panelGap,
          ),
          child: LayoutBuilder(
            builder: (_, BoxConstraints constraints) {
              if (!widget.framed && constraints.maxWidth >= _kInlineFormWidth) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: <Widget>[
                    SizedBox(width: _kDurationWidth, child: duration),
                    SizedBox(width: tokens.panelGap),
                    Expanded(child: amount),
                    SizedBox(width: tokens.panelGap),
                    SizedBox(width: _kUnlockWidth, child: unlocks),
                    SizedBox(width: tokens.panelGap),
                    submit,
                  ],
                );
              }
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: <Widget>[
                      Expanded(child: duration),
                      SizedBox(width: tokens.panelGap),
                      SizedBox(width: _kUnlockWidth, child: unlocks),
                    ],
                  ),
                  SizedBox(height: tokens.panelGap),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: <Widget>[
                      Expanded(child: amount),
                      SizedBox(width: tokens.panelGap),
                      submit,
                    ],
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  void _onStakeDurationChanged(Duration value) {
    if (_submitting) return;
    setState(() => _selectedStakeDuration = value);
    _amountFocusNode.requestFocus();
  }

  void _onMaxPressed() {
    _amountController.text = _maxZnnAmount.addDecimals(kZnnCoin.decimals);
  }

  void _onStakePressed() {
    final SendTransactionBloc bloc = context.read<SendTransactionBloc>();
    // The keyboard can submit before the loading state reaches the button.
    if (_submitting ||
        bloc.state.status == SendTransactionStatus.loading ||
        !_isInputValid) {
      return;
    }
    final AccountBlockTemplate block = zenon!.embedded.stake.stake(
      _selectedStakeDuration!.inSeconds,
      _amount.extractDecimals(kZnnCoin.decimals),
    );
    setState(() => _submitting = true);
    bloc.add(
      SendTransactionInitiateFromBlock(
        block: block,
        fromAddress: kSelectedAddress!,
        reasonForGeneratingPlasma: context.l10n.plasmaPurposeCreateStake,
      ),
    );
  }

  void _onTransactionStateChanged(SendTransactionState state) {
    if (state.status == SendTransactionStatus.success) {
      _submitSheen.pass();
      setState(() {
        _submitting = false;
        _amountController.clear();
        _selectedStakeDuration = null;
      });
      final AccountBlockTemplate? original = state.data;
      try {
        if (original != null) widget.onStakePublished?.call(original);
      } on Object {
        // A read-only observer cannot change the accepted result or form flow.
      }
      widget.onStakeCreated();
      _fetchBalance();
    } else if (state.status == SendTransactionStatus.failure) {
      setState(() => _submitting = false);
      unawaited(
        NotificationUtils.sendNotificationError(
          state.error!,
          context.l10n.errorWhileGeneratingStake,
        ),
      );
    }
  }
}

class _Control extends StatelessWidget {
  const _Control({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: <Widget>[
      Text(label.toUpperCase(), style: ledgerLabelStyle(context)),
      SizedBox(height: AppTokens.of(context).fieldLabelGap),
      child,
    ],
  );
}
