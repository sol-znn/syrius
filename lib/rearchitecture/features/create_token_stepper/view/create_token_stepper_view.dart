import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/model/new_token_data.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/create_token_stepper/model/token_create_preflight.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/create_token_stepper/model/token_create_supply.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/create_token_stepper/widgets/token_create_frame.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/create_token_stepper/widgets/token_create_rail.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/features.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/registration_success/registration_confirmation.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/registration_success/registration_success_surface.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/utils.dart';
import 'package:zenon_syrius_wallet_flutter/utils/utils.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/widgets.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

/// Four retained steps with the original six validation facts still enforced.
class CreateTokenStepperView extends StatefulWidget {
  /// Readers and optional presentation callbacks make fixtures wallet-free.
  const CreateTokenStepperView({
    required this.preflight,
    this.confirmation,
    this.onIssue,
    this.receipt,
    this.canStartIssue,
    this.isIssueUncertain,
    super.key,
  });

  /// The page's single captured owner and independently bound SDK readers.
  final TokenCreatePreflight preflight;

  /// The original publication and positive confirmation owner.
  final RegistrationConfirmation? confirmation;

  /// Fixtures observe a draft without constructing a signer or a real wallet.
  final ValueChanged<NewTokenData>? onIssue;

  /// A presentation-only receipt can be supplied by isolated widget fixtures.
  final Widget? receipt;

  /// The captured publisher refuses replacement of an admitted original
  /// attempt.
  final bool Function()? canStartIssue;

  /// An original uncertain failure keeps the draft and offers no Issue retry.
  final bool Function()? isIssueUncertain;

  @override
  State<CreateTokenStepperView> createState() => _CreateTokenStepperViewState();
}

class _CreateTokenStepperViewState extends State<CreateTokenStepperView> {
  final TextEditingController _name = TextEditingController();
  final TextEditingController _symbol = TextEditingController();
  final TextEditingController _domain = TextEditingController();
  final TextEditingController _total = TextEditingController();
  final TextEditingController _maximum = TextEditingController();
  late final ValueNotifier<NewTokenData> _draft;
  late final Listenable _changes;
  int _step = 0;
  int _run = 0;
  int _operation = 0;
  bool _busy = false;
  bool _published = false;
  String? _error;
  String? _submittedName;

  bool get _current => mounted && widget.preflight.isCurrent;

  bool get _canStartIssue =>
      (widget.canStartIssue?.call() ?? true) && !_issueUncertain;

  bool get _issueUncertain => widget.isIssueUncertain?.call() ?? false;

  bool get _detailsValid =>
      _name.text.isNotEmpty &&
      _symbol.text.isNotEmpty &&
      Validations.tokenName(_name.text) == null &&
      Validations.tokenSymbol(_symbol.text) == null &&
      (_domain.text.isEmpty || InputValidators.checkUrl(_domain.text) == null);

  NewTokenData? get _supply => tokenCreateSupplyDraft(
    draft: _draft.value,
    total: _total.text,
    maximum: _maximum.text,
  );

  @override
  void initState() {
    super.initState();
    _draft = ValueNotifier<NewTokenData>(
      NewTokenData.initial(address: widget.preflight.session.owner),
    );
    _changes = Listenable.merge(<Listenable>[
      _name,
      _symbol,
      _domain,
      _total,
      _maximum,
      _draft,
      widget.preflight,
    ]);
    unawaited(widget.preflight.refresh());
  }

  @override
  Widget build(BuildContext context) {
    final Widget flow = ListenableBuilder(
      listenable: _changes,
      builder: (BuildContext context, _) => RegistrationRetainedFlow(
        published: _published,
        form: _buildForm(context),
        receipt:
            widget.receipt ??
            TokenCreatedSuccess(
              confirmation: widget.confirmation,
              onCreateAnotherTokenPressed: _another,
              onViewTokensPressed: () => Navigator.pop(context),
            ),
      ),
    );
    if (widget.onIssue != null) return flow;
    return BlocListener<IssueTokenBloc, IssueTokenState>(
      listener: (_, IssueTokenState state) => _onIssueState(state),
      child: flow,
    );
  }

  Widget _buildForm(BuildContext context) {
    final AppTokens tokens = AppTokens.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        TokenCreateRail(
          step: _step,
          preflight: widget.preflight,
          name: _name.text,
          symbol: _symbol.text,
          busy: _busy,
          onRetry: () => unawaited(widget.preflight.refresh()),
        ),
        Expanded(
          child: Align(
            alignment: AlignmentDirectional.topStart,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: tokens.tokenCreateBodyMaxWidth,
              ),
              child: Padding(
                padding: EdgeInsetsDirectional.symmetric(
                  horizontal: tokens.registrationBodyInset,
                  vertical: tokens.tokenCreateVerticalInset,
                ),
                child: StepSwitcher.retained(
                  step: _step,
                  showContent: !_published,
                  layoutBuilder: (_, List<Widget> entries) => Stack(
                    fit: StackFit.expand,
                    children: entries,
                  ),
                  children: <Widget>[
                    _buildDetails(context),
                    _buildSupply(context),
                    _buildOptions(context),
                    _buildIssue(context),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDetails(BuildContext context) {
    final AppTokens tokens = AppTokens.of(context);
    return TokenCreateFrame(
      key: const Key('token_create_details'),
      active: _step == 0 && _current,
      busy: _busy,
      label: context.l10n.continueText,
      onSubmit: _detailsValid && widget.preflight.sufficient
          ? _continueDetails
          : null,
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: tokens.registrationActionGap,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                flex: 8,
                child: AccField(
                  label: context.l10n.name,
                  child: TextField(
                    key: const Key('token_name_field'),
                    controller: _name,
                    style: tokens.bodyText,
                    decoration: InputDecoration(
                      errorText: _name.text.isEmpty
                          ? null
                          : Validations.tokenName(_name.text),
                    ),
                  ),
                ),
              ),
              SizedBox(width: tokens.pageGap),
              Expanded(
                flex: 5,
                child: AccField(
                  label: context.l10n.tokenCreateSymbol,
                  child: TextField(
                    key: const Key('token_symbol_field'),
                    controller: _symbol,
                    textDirection: TextDirection.ltr,
                    style: tokens.dataText,
                    decoration: InputDecoration(
                      errorText: _symbol.text.isEmpty
                          ? null
                          : Validations.tokenSymbol(_symbol.text),
                    ),
                  ),
                ),
              ),
            ],
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: tokens.registrationGap,
            children: <Widget>[
              AccField(
                label: context.l10n.tokenCreateDomain,
                child: TextField(
                  key: const Key('token_domain_field'),
                  controller: _domain,
                  textDirection: TextDirection.ltr,
                  style: tokens.bodyText,
                  decoration: InputDecoration(
                    hintText: context.l10n.createTokenDomainHint,
                    errorText: _domain.text.isEmpty
                        ? null
                        : InputValidators.checkUrl(_domain.text),
                  ),
                ),
              ),
              Text(
                context.l10n.tokenCreateDomainNote,
                style: tokens.registrationCaptionText,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSupply(BuildContext context) {
    final AppTokens tokens = AppTokens.of(context);
    final NewTokenData data = _draft.value;
    return TokenCreateFrame(
      key: const Key('token_create_supply'),
      active: _step == 1 && _current,
      busy: _busy,
      onBack: _back,
      onSubmit: _supply != null ? _continueSupply : null,
      label: context.l10n.continueText,
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: tokens.registrationActionGap,
        children: <Widget>[
          CustomSlider(
            key: ValueKey<int>(_run),
            sliderKey: const Key('token_decimals_slider'),
            description: context.l10n.numberOfDecimals(data.decimals),
            startValue: data.decimals.toDouble(),
            min: 0,
            maxValue: 18,
            activeColor: tokens.znnInk,
            callback: (double value) {
              if (_step == 1 && _current && !_busy) {
                _draft.value = _draft.value.copyWith(decimals: value.toInt());
              }
            },
          ),
          if (data.isMintable)
            _buildAmount(
              context,
              _maximum,
              label: context.l10n.maxSupply,
              fieldKey: const Key('token_max_supply_field'),
            ),
          _buildAmount(
            context,
            _total,
            label: context.l10n.totalSupply,
            fieldKey: const Key('token_total_supply_field'),
          ),
        ],
      ),
    );
  }

  Widget _buildAmount(
    BuildContext context,
    TextEditingController controller, {
    required String label,
    required Key fieldKey,
  }) => AccField(
    label: label,
    child: AmountRefusalScope(
      controller: controller,
      builder: (_, String? refusal) => TextField(
        key: fieldKey,
        controller: controller,
        textDirection: TextDirection.ltr,
        style: AppTokens.of(context).dataText,
        inputFormatters: FormatUtils.getAmountTextInputFormatters(
          controller.text,
        ),
        decoration: InputDecoration(
          errorText:
              refusal ??
              (controller.text.isEmpty || _supply != null
                  ? null
                  : context.l10n.validatorEnterValidAmount),
        ),
      ),
    ),
  );

  Widget _buildOptions(BuildContext context) {
    final AppTokens tokens = AppTokens.of(context);
    final NewTokenData data = _draft.value;
    return TokenCreateFrame(
      key: const Key('token_create_options'),
      active: _step == 2 && _current,
      busy: _busy,
      onBack: _back,
      onSubmit: _continueOptions,
      label: _supply == null
          ? context.l10n.tokenCreateReviewSupply
          : context.l10n.continueText,
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: tokens.registrationActionGap,
        children: <Widget>[
          TokenStepToggle(
            checkboxKey: const Key('token_mintable_checkbox'),
            label: context.l10n.mintable,
            help: context.l10n.tokenMintableTooltip,
            value: data.isMintable,
            onChanged: (bool value) =>
                _option(data.copyWith(isMintable: value)),
          ),
          TokenStepToggle(
            checkboxKey: const Key('token_burnable_checkbox'),
            label: context.l10n.burnableToken,
            help: context.l10n.tokenBurnTooltip,
            value: data.isBurnable,
            onChanged: (bool value) =>
                _option(data.copyWith(isBurnable: value)),
          ),
          TokenStepToggle(
            checkboxKey: const Key('token_utility_checkbox'),
            label: context.l10n.utilityToken,
            help: context.l10n.tokenStatusUtilityTooltip,
            value: data.isUtility,
            onChanged: (bool value) => _option(data.copyWith(isUtility: value)),
          ),
        ],
      ),
    );
  }

  Widget _buildIssue(BuildContext context) {
    final AppTokens tokens = AppTokens.of(context);
    final NewTokenData data = _draft.value;
    final String? message = _issueUncertain
        ? context.l10n.tokensActionUnknown
        : _error;
    return TokenCreateFrame(
      key: const Key('token_create_issue'),
      active: _step == 3 && _current,
      busy: _busy,
      onBack: _back,
      onSubmit:
          !_published && _canStartIssue && _detailsValid && _supply != null
          ? _issue
          : null,
      label: context.l10n.tokenCreateIssue,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        spacing: tokens.registrationGap,
        children: <Widget>[
          _ReviewRow(
            label: context.l10n.address,
            child: Tooltip(
              message: data.address,
              child: Text(
                data.address,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textDirection: TextDirection.ltr,
                style: tokens.dataText,
              ),
            ),
          ),
          _ReviewRow(
            label: context.l10n.name,
            child: Text(data.tokenName, style: tokens.bodyText),
          ),
          _ReviewRow(
            label: context.l10n.tokenCreateSymbol,
            child: Text(
              data.tokenSymbol,
              textDirection: TextDirection.ltr,
              style: tokens.dataText,
            ),
          ),
          if (data.tokenDomain.isNotEmpty)
            _ReviewRow(
              label: context.l10n.tokenCreateDomain,
              child: Text(
                data.tokenDomain,
                textDirection: TextDirection.ltr,
                style: tokens.bodyText,
              ),
            ),
          _ReviewRow(
            label: context.l10n.createTokenDecimalsLabel,
            child: Text(
              '${data.decimals}',
              textDirection: TextDirection.ltr,
              style: tokens.dataText,
            ),
          ),
          _ReviewRow(
            label: context.l10n.totalSupply,
            child: AmountText(
              data.totalSupply,
              decimals: data.decimals,
              symbol: data.tokenSymbol,
              style: tokens.dataText,
            ),
          ),
          _ReviewRow(
            label: context.l10n.maxSupply,
            child: AmountText(
              data.maxSupply,
              decimals: data.decimals,
              symbol: data.tokenSymbol,
              style: tokens.dataText,
            ),
          ),
          _ReviewRow(
            label: context.l10n.mintable,
            child: Text(
              data.isMintable ? context.l10n.yes : context.l10n.no,
              style: tokens.bodyText,
            ),
          ),
          _ReviewRow(
            label: context.l10n.burnableToken,
            child: Text(
              data.isBurnable ? context.l10n.yes : context.l10n.no,
              style: tokens.bodyText,
            ),
          ),
          _ReviewRow(
            label: context.l10n.utilityToken,
            child: Text(
              data.isUtility ? context.l10n.yes : context.l10n.no,
              style: tokens.bodyText,
            ),
          ),
          if (message != null)
            Text(
              message,
              style: tokens.bodyText.copyWith(
                color: _issueUncertain ? tokens.warn : tokens.error,
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _continueDetails() async {
    if (_step != 0 || !_current || _busy || !_detailsValid) return;
    final int operation = ++_operation;
    setState(() => _busy = true);
    final bool enough = await widget.preflight.refresh();
    if (!_current || operation != _operation) return;
    setState(() {
      _busy = false;
      if (enough && _detailsValid) {
        _saveDetails();
        _step = 1;
      }
    });
  }

  void _saveDetails() {
    _draft.value = _draft.value.copyWith(
      tokenName: _name.text,
      tokenSymbol: _symbol.text,
      tokenDomain: _domain.text,
    );
  }

  void _continueSupply() {
    if (_step != 1 || !_current || _busy) return;
    final NewTokenData? data = _supply;
    if (data == null) return;
    _draft.value = data;
    setState(() => _step = 2);
  }

  void _option(NewTokenData data) {
    if (_step == 2 && _current && !_busy) _draft.value = data;
  }

  void _continueOptions() {
    if (_step != 2 || !_current || _busy) return;
    final NewTokenData? data = _supply;
    if (data != null) _draft.value = data;
    setState(() => _step = data == null ? 1 : 3);
  }

  void _back() {
    if (_step > 0 && _current && !_busy && !_published) {
      setState(() => _step--);
    }
  }

  Future<void> _issue() async {
    if (_step != 3 || !_current || _busy || _published || !_canStartIssue) {
      return;
    }
    if (!_detailsValid || _supply == null) {
      setState(() => _step = _detailsValid ? 1 : 0);
      return;
    }
    final int operation = ++_operation;
    final String failureMessage = context.l10n.commonSomethingWentWrong;
    setState(() {
      _busy = true;
      _error = null;
    });
    final bool enough = await widget.preflight.refresh();
    if (!mounted || !_current || operation != _operation) return;
    final NewTokenData? data = _supply;
    if (!enough || !_canStartIssue || !_detailsValid || data == null) {
      setState(() {
        _busy = false;
        if (!_detailsValid) _step = 0;
        if (data == null) _step = 1;
      });
      return;
    }
    _saveDetails();
    final NewTokenData submitted = data.copyWith(
      tokenName: _name.text,
      tokenSymbol: _symbol.text,
      tokenDomain: _domain.text,
    );
    _draft.value = submitted;
    _submittedName = submitted.tokenName;
    try {
      if (widget.onIssue case final ValueChanged<NewTokenData> observe) {
        observe(submitted);
      } else {
        context.read<IssueTokenBloc>().add(
          IssueTokenRequested(tokenData: submitted),
        );
      }
    } on Object {
      if (_current) {
        setState(() {
          _busy = false;
          _error = failureMessage;
        });
      }
    }
  }

  void _onIssueState(IssueTokenState state) {
    if (_published || _submittedName == null) return;
    if (state is IssueTokenLoading) {
      setState(() => _busy = true);
    } else if (state is IssueTokenDone) {
      final String name = _submittedName ?? _draft.value.tokenName;
      try {
        widget.confirmation?.accept(
          RegistrationPublication(
            accountBlock: state.accountBlock,
            name: name,
          ),
        );
      } on Object {
        // Receipt listeners cannot replace the original accepted result.
      }
      setState(() {
        _published = true;
        _busy = false;
      });
      unawaited(_saveFavorite(state.newTokenStandard, name));
      try {
        if (_current) {
          context.read<AllTokensBloc>().add(const AllTokensRequested());
        }
      } on Object {
        // Catalog observation cannot replace the original issuance result.
      }
    } else if (state is IssueTokenFailure && _current) {
      setState(() {
        _busy = false;
        _error = context.l10n.commonSomethingWentWrong;
      });
    }
  }

  Future<void> _saveFavorite(TokenStandard standard, String name) async {
    if (!_current) return;
    final String failureMessage = context.l10n.errorAddingTokenToFavorites(
      name,
    );
    try {
      await context.read<FavoriteTokensRepository>().add(standard);
    } on Object catch (error) {
      if (!_current) return;
      try {
        await NotificationUtils.sendNotificationError(
          error,
          failureMessage,
        );
      } on Object {
        // Optional favorite persistence never replaces accepted issuance.
      }
    }
  }

  void _another() {
    if (!(widget.confirmation?.resetForAnother() ?? false)) return;
    _operation++;
    _run++;
    _name.clear();
    _symbol.clear();
    _domain.clear();
    _total.clear();
    _maximum.clear();
    _draft.value = NewTokenData.initial(
      address: widget.preflight.session.owner,
    );
    setState(() {
      _step = 0;
      _published = false;
      _busy = false;
      _error = null;
      _submittedName = null;
    });
    unawaited(widget.preflight.refresh());
  }

  @override
  void dispose() {
    _operation++;
    widget.preflight.closePresentation();
    _name.dispose();
    _symbol.dispose();
    _domain.dispose();
    _total.dispose();
    _maximum.dispose();
    _draft.dispose();
    super.dispose();
  }
}

class _ReviewRow extends StatelessWidget {
  const _ReviewRow({required this.label, required this.child});
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = AppTokens.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SizedBox(
          width: tokens.tokenCreateReviewLabelWidth,
          child: Text(
            label.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: tokens.ledgerText,
          ),
        ),
        SizedBox(width: tokens.inlineGap),
        Expanded(child: child),
      ],
    );
  }
}
