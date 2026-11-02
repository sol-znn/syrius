import 'dart:async';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/receive/receive_header_controller.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/receive/receive_request.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/extensions/buildcontext_extension.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/extensions/token_extension.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/functions/tokens.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/disclosure.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/ltr.dart';
import 'package:zenon_syrius_wallet_flutter/utils/app_theme.dart';
import 'package:zenon_syrius_wallet_flutter/utils/format_utils.dart';
import 'package:zenon_syrius_wallet_flutter/utils/global.dart';
import 'package:zenon_syrius_wallet_flutter/utils/toast_utils.dart';
import 'package:zenon_syrius_wallet_flutter/utils/zts_utils.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/reusable_widgets/buttons/primary_pill.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/reusable_widgets/input_fields/amount_input_field.dart'
    show AmountRefusalScope;
import 'package:zenon_syrius_wallet_flutter/widgets/reusable_widgets/receive_qr_image.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/shell/page_dismiss.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

/// The receiving address, with a QR and optional amount opened on demand.
class ReceivePopulated extends StatefulWidget {
  /// Creates a Receive form. Optional callbacks keep native operations at
  /// the boundary when the form is hosted by a test or another surface.
  const ReceivePopulated({
    required this.assets,
    this.addresses,
    this.addressLabels,
    this.initialAddress,
    this.onCopyAddress,
    this.onShareImage,
    this.onSaveImage,
    this.encodeImage,
    this.headerController,
    this.isCurrent,
    super.key,
  });

  /// The QR panel follows the mockup's disclosure clock in both directions.
  static const Duration qrRevealDuration = Duration(milliseconds: 240);

  /// Available network tokens, including native coins.
  final List<Token> assets;

  /// Defaults to the open wallet's address list.
  final List<String>? addresses;

  /// Defaults to the open wallet's address labels.
  final Map<String, String>? addressLabels;

  /// Defaults to the selected wallet address when it is available.
  final String? initialAddress;

  /// Replaces the platform text clipboard operation.
  final Future<void> Function(String)? onCopyAddress;

  /// Replaces the existing native image sharing operation.
  final Future<void> Function(Uint8List)? onShareImage;

  /// Replaces the existing cached-image save and open operation.
  final Future<void> Function(Uint8List)? onSaveImage;

  /// Replaces QR rasterization without changing the encoded request.
  final ReceiveQrEncoder? encodeImage;

  /// Publishes this form's choices to Transfer's optional header picker.
  final ReceiveHeaderController? headerController;

  /// Revokes header and QR callbacks when the embedding mode changes.
  final bool Function()? isCurrent;

  @override
  State<ReceivePopulated> createState() => _ReceivePopulatedState();
}

class _ReceivePopulatedState extends State<ReceivePopulated>
    with SingleTickerProviderStateMixin {
  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();
  final TextEditingController _tokenController = TextEditingController();
  final FocusNode _amountFocus = FocusNode();
  final DisclosureController _request = DisclosureController();
  late final AnimationController _qrMotion;
  late Token _selectedToken;
  String? _selectedAddress;
  bool _showQr = false;
  bool _copying = false;
  bool _copyFailed = false;
  int _requestRevision = 0;
  String _observedAmount = '';
  ModalRoute<dynamic>? _route;
  bool _tickerEnabled = true;
  int _headerEpoch = 0;

  bool get _qrPresent => _showQr || !_qrMotion.isDismissed;

  List<String> get _addresses =>
      widget.addresses ?? kDefaultAddressList.whereType<String>().toList();

  Map<String, String> get _labels => widget.addressLabels ?? kAddressLabelMap;

  List<Token> get _tokens => sortAssets(
    widget.assets.isEmpty ? <Token>[kZnnCoin] : List<Token>.of(widget.assets),
  );

  String? get _payload => receiveRequestData(
    address: _selectedAddress ?? '',
    token: _selectedToken,
    amount: _amountController.text,
  );

  @override
  void initState() {
    super.initState();
    _selectedToken = _defaultToken();
    _selectAvailableAddress();
    _amountController.addListener(_amountChanged);
    widget.headerController?.addListener(_headerChanged);
    // The owner requires the full reveal clock regardless of OS settings.
    _qrMotion = AnimationController(
      vsync: this,
      duration: ReceivePopulated.qrRevealDuration,
      animationBehavior: AnimationBehavior.preserve,
    )..addStatusListener(_qrStatusChanged);
  }

  bool get _headerCurrent => mounted && _tickerEnabled &&
      (_route?.isCurrent ?? true) && (widget.isCurrent?.call() ?? true);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _route = ModalRoute.of(context);
    _tickerEnabled = TickerMode.of(context);
    if (!_headerCurrent) {
      _requestRevision += 1;
      _headerEpoch += 1;
      widget.headerController?.detach(this);
    }
  }

  void _headerChanged() {
    if (!mounted) return;
    _requestRevision += 1;
    setState(() {});
  }

  bool _selectHeaderAddress(String address) {
    final ReceiveHeaderController? header = widget.headerController;
    if (header == null || !_headerCurrent || !header.ownsCurrent(this) ||
        !_addresses.contains(address)) {
      return false;
    }
    _selectAddress(address);
    return true;
  }

  void _selectAddress(String address) {
    setState(() {
      if (_selectedAddress != address) _requestRevision += 1;
      _selectedAddress = address;
      _addressController.text = _labels[address] ?? address;
      _copyFailed = false;
    });
  }

  void _scheduleHeader() {
    final ReceiveHeaderController? header = widget.headerController;
    if (header == null) return;
    if (!_headerCurrent || _selectedAddress == null) {
      header.detach(this);
      return;
    }
    final int epoch = ++_headerEpoch;
    final int revision = header.revision;
    WidgetsBinding.instance.addPostFrameCallback((Duration _) {
      if (!mounted || epoch != _headerEpoch || !_headerCurrent ||
          !identical(widget.headerController, header)) {
        return;
      }
      final String? selected = _selectedAddress;
      if (selected == null) return;
      header.publish(
        owner: this,
        expectedRevision: revision,
        labels: <String, String>{
          for (final String address in _addresses)
            address: _labels[address] ?? address,
        },
        selected: selected,
        isCurrent: () => _headerCurrent,
        onSelected: _selectHeaderAddress,
      );
    });
  }

  Token _defaultToken() => _tokens.firstWhere(
    (Token token) => token.tokenStandard.toString() == znnTokenStandard,
    orElse: () => _tokens.first,
  );

  void _selectAvailableAddress() {
    final List<String> addresses = _addresses;
    if (!addresses.contains(_selectedAddress)) {
      final String? preferred = widget.initialAddress ?? kSelectedAddress;
      _selectedAddress = addresses.contains(preferred)
          ? preferred
          : addresses.firstOrNull;
    }
    _addressController.text = _selectedAddress == null
        ? ''
        : _labels[_selectedAddress] ?? _selectedAddress!;
  }

  @override
  void didUpdateWidget(ReceivePopulated oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.headerController != widget.headerController) {
      oldWidget.headerController
        ?..removeListener(_headerChanged)
        ..detach(this);
      widget.headerController?.addListener(_headerChanged);
      _requestRevision += 1;
      _headerEpoch += 1;
    }
    final String? previousPayload = _payload;
    _selectAvailableAddress();
    _selectedToken = _tokens.firstWhere(
      (Token token) => token.tokenStandard == _selectedToken.tokenStandard,
      orElse: _defaultToken,
    );
    _tokenController.text = _tokenLabel(_selectedToken);
    if (_payload != previousPayload) _requestRevision += 1;
    if (!_headerCurrent) widget.headerController?.detach(this);
  }

  void _amountChanged() {
    final String amount = _amountController.text;
    if (amount != _observedAmount) {
      // Revocation is synchronous. Waiting for the next frame lets a
      // pending encoder export a request that the user has already edited.
      _requestRevision += 1;
      _observedAmount = amount;
    }
    setState(() {});
  }

  void _qrStatusChanged(AnimationStatus status) {
    if (status == AnimationStatus.dismissed && mounted) setState(() {});
  }

  void _setShowQr(bool show) {
    if (show == _showQr) return;
    setState(() {
      _requestRevision += 1;
      _showQr = show;
    });
    if (show) {
      _qrMotion.forward();
    } else {
      _qrMotion.reverse();
    }
  }

  @override
  void dispose() {
    _headerEpoch += 1;
    widget.headerController
      ?..removeListener(_headerChanged)
      ..detach(this);
    _amountController
      ..removeListener(_amountChanged)
      ..dispose();
    _addressController.dispose();
    _tokenController.dispose();
    _amountFocus.dispose();
    _request.dispose();
    _qrMotion
      ..removeStatusListener(_qrStatusChanged)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _scheduleHeader();
    final AppTokens tokens = AppTokens.of(context);
    return Theme(
      data: Theme.of(context).copyWith(
        inputDecorationTheme: _buildInputTheme(tokens),
      ),
      child: PageDismissAction(
        open: _showQr,
        onDismiss: () => _setShowQr(false),
        child: Padding(
          key: const Key('receive_screen_marker'),
          padding: tokens.receiveFormPadding,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              if (widget.headerController == null) ...<Widget>[
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: SizedBox(
                    width: tokens.receiveAddressWidth,
                    child: _buildAddressPicker(tokens),
                  ),
                ),
                SizedBox(height: tokens.receiveGap),
              ],
              if (_qrPresent)
                _buildExpanded(tokens)
              else
                _buildDetails(tokens, centered: true),
            ],
          ),
        ),
      ),
    );
  }

  InputDecorationThemeData _buildInputTheme(AppTokens tokens) {
    final OutlineInputBorder border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(tokens.transferControlRadius),
      borderSide: BorderSide(color: tokens.line),
    );
    return Theme.of(context).inputDecorationTheme.copyWith(
      filled: true,
      fillColor: tokens.card2,
      border: border,
      enabledBorder: border,
      focusedBorder: border.copyWith(
        borderSide: BorderSide(color: tokens.focusRing),
      ),
      errorBorder: border.copyWith(borderSide: BorderSide(color: tokens.error)),
      focusedErrorBorder: border.copyWith(
        borderSide: BorderSide(color: tokens.error),
      ),
    );
  }

  Widget _buildAddressPicker(AppTokens tokens) => DropdownMenu<String>(
    key: const Key('receive_address_picker'),
    controller: _addressController,
    initialSelection: _selectedAddress,
    expandedInsets: EdgeInsets.zero,
    enableFilter: true,
    label: Text(context.l10n.address),
    textStyle: tokens.bodyText,
    dropdownMenuEntries: <DropdownMenuEntry<String>>[
      for (final String address in _addresses)
        DropdownMenuEntry<String>(
          value: address,
          label: _labels[address] ?? address,
        ),
    ],
    filterCallback: (List<DropdownMenuEntry<String>> entries, String query) =>
        entries.where((DropdownMenuEntry<String> entry) {
          final String term = query.toLowerCase();
          return entry.label.toLowerCase().contains(term) ||
              entry.value.toLowerCase().contains(term);
        }).toList(),
    onSelected: (String? address) {
      if (address == null) return;
      _selectAddress(address);
    },
  );

  Widget _buildExpanded(AppTokens tokens) => LayoutBuilder(
    builder: (BuildContext context, BoxConstraints constraints) {
      final double scale =
          MediaQuery.textScalerOf(context).scale(
            tokens.receiveRequestText.fontSize!,
          ) /
          tokens.receiveRequestText.fontSize!;
      final double qrWidth = tokens.receiveQrSize + tokens.receiveQrInset * 2;
      final Widget qr = _buildQrReveal(tokens);
      final Widget details = _buildDetails(tokens, centered: false);
      if (constraints.maxWidth <
          qrWidth + tokens.receiveGap + tokens.receiveTokenWidth * 2 * scale) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Align(child: qr),
            SizedBox(height: tokens.receiveGap),
            details,
          ],
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          qr,
          SizedBox(width: tokens.receiveGap),
          Expanded(child: details),
        ],
      );
    },
  );

  Widget _buildQrReveal(AppTokens tokens) => IgnorePointer(
    ignoring: !_showQr,
    child: ExcludeSemantics(
      excluding: !_showQr,
      child: ExcludeFocus(
        excluding: !_showQr,
        child: AnimatedBuilder(
          key: const Key('receive_qr_reveal'),
          animation: _qrMotion,
          child: _buildQr(tokens),
          builder: (BuildContext context, Widget? child) {
            final double reveal = tokens.spring.transform(_qrMotion.value);
            return ClipRect(
              clipBehavior: _qrMotion.isCompleted ? Clip.none : Clip.hardEdge,
              child: Align(
                heightFactor: reveal,
                child: Transform.translate(
                  key: const Key('receive_qr_slide'),
                  offset: Offset(0, -tokens.receiveQrSlide * (1 - reveal)),
                  child: Opacity(opacity: reveal, child: child),
                ),
              ),
            );
          },
        ),
      ),
    ),
  );

  Widget _buildQr(AppTokens tokens) {
    final String? payload = _payload;
    final int revision = _requestRevision;
    final ReceiveHeaderController? header = widget.headerController;
    final int? headerRevision = header?.revision;
    return Container(
      key: payload == null ? null : const Key('receive_qr_screen_marker'),
      width: tokens.receiveQrSize + tokens.receiveQrInset * 2,
      padding: EdgeInsetsDirectional.all(tokens.receiveQrInset),
      decoration: BoxDecoration(
        color: tokens.card2,
        borderRadius: BorderRadius.circular(tokens.transferControlRadius),
      ),
      child: payload == null
          ? SizedBox.square(
              dimension: tokens.receiveQrSize,
              child: _buildError(context.l10n.receiveInvalidAmount, tokens),
            )
          : ReceiveQrImage(
              key: const Key('receive_qr_image'),
              data: payload,
              size: tokens.receiveQrSize,
              tokenStandard: _selectedToken.tokenStandard,
              enabled: _showQr,
              isRequestCurrent: () =>
                  mounted &&
                  _showQr &&
                  revision == _requestRevision &&
                  (header == null ||
                      (identical(widget.headerController, header) &&
                          header.revision == headerRevision &&
                          header.ownsCurrent(this) &&
                          _addresses.contains(_selectedAddress))) &&
                  _payload == payload,
              onShareImage: widget.onShareImage,
              onSaveImage: widget.onSaveImage,
              encodeImage: widget.encodeImage,
            ),
    );
  }

  Widget _buildDetails(AppTokens tokens, {required bool centered}) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: centered
        ? CrossAxisAlignment.center
        : CrossAxisAlignment.stretch,
    children: <Widget>[
      ConstrainedBox(
        constraints: BoxConstraints(maxWidth: tokens.receiveAddressWidth),
        child: SelectableText(
          _selectedAddress ?? '',
          key: const Key('receive_address'),
          textDirection: TextDirection.ltr,
          textAlign: centered ? TextAlign.center : ltrTextAlign(context),
          style: centered
              ? tokens.receiveAddressText
              : tokens.receiveQrAddressText,
        ),
      ),
      SizedBox(height: tokens.receiveGap),
      Wrap(
        alignment: centered ? WrapAlignment.center : WrapAlignment.start,
        spacing: tokens.receiveActionGap,
        runSpacing: tokens.receiveActionGap,
        children: <Widget>[
          PrimaryPill(
            key: const Key('receive_copy_address'),
            onPressed: _selectedAddress == null || _copying
                ? null
                : () => unawaited(_copyAddress()),
            style: OutlinedButton.styleFrom(
              visualDensity: VisualDensity.standard,
              minimumSize: Size(
                0,
                centered ? tokens.buttonHeight : tokens.compactButtonHeight,
              ),
              padding: centered
                  ? tokens.heroActionPadding
                  : tokens.homeSideButtonPadding,
              textStyle: centered
                  ? tokens.buttonText
                  : tokens.compactText.copyWith(fontWeight: FontWeight.w500),
            ),
            icon: Icon(
              Icons.copy_rounded,
              size: centered ? tokens.heroIconSize : tokens.heroCopyIconSize,
            ),
            child: Text(context.l10n.receiveCopyAddress),
          ),
          OutlinedButton.icon(
            key: const Key('receive_qr_toggle'),
            style: OutlinedButton.styleFrom(
              foregroundColor: tokens.foreground,
              iconColor: tokens.foreground,
              backgroundColor: tokens.card2,
              side: BorderSide(color: tokens.line),
              shape: const StadiumBorder(),
              visualDensity: VisualDensity.standard,
              minimumSize: Size(
                0,
                centered ? tokens.buttonHeight : tokens.compactButtonHeight,
              ),
              padding: centered
                  ? tokens.heroActionPadding
                  : tokens.homeSideButtonPadding,
              textStyle: centered
                  ? tokens.buttonText
                  : tokens.compactText.copyWith(fontWeight: FontWeight.w500),
            ),
            onPressed: _selectedAddress == null
                ? null
                : () => _setShowQr(!_showQr),
            icon: Icon(
              Icons.qr_code_rounded,
              size: centered ? tokens.heroIconSize : tokens.heroCopyIconSize,
            ),
            label: Text(
              _showQr ? context.l10n.receiveHideQr : context.l10n.receiveShowQr,
            ),
          ),
        ],
      ),
      if (_copyFailed) ...<Widget>[
        SizedBox(height: tokens.receiveMicroGap),
        _buildError(context.l10n.receiveCopyFailed, tokens),
      ],
      SizedBox(height: tokens.receiveGap),
      Divider(height: 1, color: tokens.line),
      Disclosure(
        controller: _request,
        keepAlive: true,
        keyPrefix: 'receive_request',
        title: context.l10n.receiveRequestAmount,
        child: _buildRequestFields(tokens),
      ),
    ],
  );

  Widget _buildRequestFields(AppTokens tokens) => LayoutBuilder(
    builder: (BuildContext context, BoxConstraints constraints) {
      final Widget amount = AmountRefusalScope(
        controller: _amountController,
        builder: (_, String? refusal) => TextField(
          key: const Key('receive_amount_field'),
          controller: _amountController,
          focusNode: _amountFocus,
          style: tokens.receiveAmountText,
          textDirection: TextDirection.ltr,
          textAlign: ltrTextAlign(context),
          decoration: InputDecoration(
            hintText: context.l10n.amount,
            errorMaxLines: 3,
            errorText:
                refusal ??
                (_amountController.text.isNotEmpty && _payload == null
                    ? context.l10n.receiveInvalidAmount
                    : null),
          ),
          inputFormatters: FormatUtils.getAmountTextInputFormatters(
            _amountController.text,
          ),
        ),
      );
      final Widget token = _buildTokenPicker(tokens);
      final double scale =
          MediaQuery.textScalerOf(context).scale(
            tokens.receiveAmountText.fontSize!,
          ) /
          tokens.receiveAmountText.fontSize!;
      if (constraints.maxWidth <
          tokens.receiveTokenWidth * 2 * scale + tokens.receiveFieldGap) {
        return Column(
          children: <Widget>[
            amount,
            SizedBox(height: tokens.receiveFieldGap),
            token,
          ],
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(child: amount),
          SizedBox(width: tokens.receiveFieldGap),
          SizedBox(width: tokens.receiveTokenWidth, child: token),
        ],
      );
    },
  );

  String _tokenLabel(Token token) =>
      token.isCoin ? token.symbol : '${token.symbol} (${token.tokenStandard})';

  Widget _buildTokenPicker(AppTokens tokens) => DropdownMenu<Token>(
    key: const Key('receive_token_picker'),
    controller: _tokenController,
    initialSelection: _selectedToken,
    expandedInsets: EdgeInsets.zero,
    enableFilter: true,
    textStyle: tokens.dataText,
    dropdownMenuEntries: <DropdownMenuEntry<Token>>[
      for (final Token token in _tokens)
        DropdownMenuEntry<Token>(value: token, label: _tokenLabel(token)),
    ],
    filterCallback: (List<DropdownMenuEntry<Token>> entries, String query) =>
        entries.where((DropdownMenuEntry<Token> entry) {
          final String term = query.toLowerCase();
          return entry.label.toLowerCase().contains(term) ||
              entry.value.tokenStandard.toString().contains(term);
        }).toList(),
    onSelected: (Token? token) {
      if (token == null) return;
      setState(() {
        _requestRevision += 1;
        _selectedToken = token;
        _tokenController.text = _tokenLabel(token);
      });
    },
  );

  Widget _buildError(String message, AppTokens tokens) => Semantics(
    liveRegion: true,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(Icons.error_outline_rounded, color: tokens.error),
        SizedBox(width: tokens.receiveMicroGap),
        Flexible(
          child: Text(
            message,
            style: tokens.receiveRequestText.copyWith(color: tokens.error),
          ),
        ),
      ],
    ),
  );

  Future<void> _copyAddress() async {
    final String? address = _selectedAddress;
    if (address == null || _copying) return;
    setState(() {
      _copying = true;
      _copyFailed = false;
    });
    try {
      final Future<void> Function(String)? copy = widget.onCopyAddress;
      if (copy == null) {
        await Clipboard.setData(ClipboardData(text: address));
      } else {
        await copy(address);
      }
      if (mounted && copy == null) {
        ToastUtils.showToast(context, context.l10n.copied);
      }
    } on Object catch (_) {
      if (mounted) setState(() => _copyFailed = true);
    } finally {
      if (mounted) setState(() => _copying = false);
    }
  }
}
