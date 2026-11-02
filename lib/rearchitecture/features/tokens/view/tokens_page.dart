import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/main.dart' as app;
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/all_tokens/all_tokens.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/create_token_stepper/create_token_stepper.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/home/widgets/amount_text.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/send/bloc/send_transaction/send_transaction_bloc.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/token_balance/token_balance.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/token_favorite/repository/favorite_tokens_repository.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/tokens/controller/tokens_page_controller.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/tokens/token_list_projection.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/tokens/view/tokens_card.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/extensions/buildcontext_extension.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/ltr.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/page/page_strip.dart';
import 'package:zenon_syrius_wallet_flutter/screens/screens.dart';
import 'package:zenon_syrius_wallet_flutter/utils/app_theme.dart';
import 'package:zenon_syrius_wallet_flutter/utils/global.dart';
import 'package:zenon_syrius_wallet_flutter/utils/wallet_context_revision.dart';
import 'package:zenon_syrius_wallet_flutter/utils/zts_utils.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/reusable_widgets/app_lottie.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/reusable_widgets/buttons/primary_pill.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/shell/page_refresh.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/shell/tabs.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

/// The strip and one token ledger replace the separate Balances card.
class TokensPage extends StatelessWidget {
  /// Keeps the existing create-token route and notification callback.
  const TokensPage({
    required this.onStepperNotificationSeeMorePressed,
    this.controller,
    this.balanceReader,
    this.favoriteRepository,
    this.onCreateToken,
    this.onSendToken,
    super.key,
  });

  /// Pure filter, query and scroll state retained by the session shell.
  final TokensPageController? controller;

  /// An isolated reader can provide real response semantics in source tests.
  final TokenBalanceCubit? balanceReader;

  /// Injectable persistence for presentation without opening a wallet profile.
  final FavoriteTokensRepository? favoriteRepository;

  /// Injectable entry callback; production keeps the existing stepper route.
  final VoidCallback? onCreateToken;

  /// The shell selects this exact asset and explicitly opens Send mode.
  final ValueChanged<String>? onSendToken;

  /// Existing stepper notification routing.
  final VoidCallback onStepperNotificationSeeMorePressed;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: WalletContextRevision.changes,
    builder: (BuildContext context, Widget? child) {
      if (kCurrentPage == Tabs.lock ||
          kSelectedAddress == null ||
          app.zenon == null) {
        return const SizedBox.shrink();
      }
      return _TokenSourcePage(
        key: ValueKey<Object>((
          kSelectedAddress,
          app.zenon,
          kCurrentNode,
          kNodeChainId,
          getChainIdentifier(),
          WalletContextRevision.value,
        )),
        options: this,
      );
    },
  );
}

class _TokenSourcePage extends StatefulWidget {
  const _TokenSourcePage({required this.options, super.key});

  final TokensPage options;

  @override
  State<_TokenSourcePage> createState() => _TokensPageState();
}

class _TokensPageState extends State<_TokenSourcePage> {
  TokenBalanceCubit? _balances;

  @override
  void initState() {
    super.initState();
    // A selection or revision boundary invalidates the shared catalog too.
    context.read<AllTokensBloc>().add(const AllTokensRequested());
    if (widget.options.balanceReader != null) {
      _balances = widget.options.balanceReader;
      return;
    }
    final Zenon? client = app.zenon;
    final String? address = kSelectedAddress;
    if (client != null && address != null) {
      _balances = TokenBalanceCubit(zenon: client, address: address)..refresh();
    }
  }

  @override
  void dispose() {
    if (widget.options.balanceReader == null) unawaited(_balances?.close());
    super.dispose();
  }

  void _refresh() {
    context.read<AllTokensBloc>().add(const AllTokensRequested());
    _balances?.refresh();
  }

  @override
  Widget build(BuildContext context) {
    final TokenBalanceCubit? balances = _balances;
    return PageRefreshAction(
      onRefresh: _refresh,
      child: BlocBuilder<AllTokensBloc, AllTokensState>(
        builder: (BuildContext context, AllTokensState catalog) =>
            balances == null
            ? _buildPage(catalog, const TokenBalanceState())
            : BlocBuilder<TokenBalanceCubit, TokenBalanceState>(
                bloc: balances,
                builder: (BuildContext context, TokenBalanceState balance) =>
                    _buildPage(catalog, balance),
              ),
      ),
    );
  }

  Widget _buildPage(AllTokensState catalog, TokenBalanceState balances) {
    final AppTokens tokens = AppTokens.of(context);
    final List<Token>? complete =
        catalog is AllTokensPopulated && catalog.isCurrent
        ? catalog.data
        : null;
    final int? held = balances.current?.heldCount;
    final int? issued = issuedTokenCount(complete, kSelectedAddress);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        PageStrip(
          key: const Key('tokens_strip'),
          lead: const AppLottie(AppLottieAsset.zts, size: kStripLeadSize),
          figures: <StripFigure>[
            StripFigure(
              label: context.l10n.tokensYouHold,
              value: Ltr(
                child: Text(
                  held?.toString() ?? '-',
                  key: const Key('tokens_figure_held'),
                ),
              ),
            ),
            StripFigure(
              label: context.l10n.tokensIssuedByYou,
              value: Ltr(
                child: Text(
                  issued?.toString() ?? '-',
                  key: const Key('tokens_figure_issued'),
                ),
              ),
            ),
            StripFigure(
              label: context.l10n.createTokenFeeLabel,
              value: AmountText(
                tokenZtsIssueFeeInZnn,
                decimals: coinDecimals,
                symbol: kZnnCoin.symbol,
                symbolColor: tokens.znnInk,
                style: tokens.stripAmountText,
              ),
            ),
          ],
          actions: <Widget>[
            PrimaryPill(
              key: const Key('tokens_create'),
              onPressed: _openStepper,
              icon: const Icon(Icons.add),
              child: Text(context.l10n.createTokenOpenLabel),
            ),
          ],
        ),
        SizedBox(height: tokens.pageGap),
        Expanded(
          child: TokensCard(
            controller: widget.options.controller,
            catalog: catalog,
            balances: balances,
            favoriteRepository: widget.options.favoriteRepository,
            onSendToken: widget.options.onSendToken,
          ),
        ),
      ],
    );
  }

  void _openStepper() {
    if (!mounted || !(ModalRoute.of(context)?.isCurrent ?? true)) return;
    if (widget.options.onCreateToken != null) {
      widget.options.onCreateToken!();
      return;
    }
    final SendTransactionBloc sender = context.read<SendTransactionBloc>();
    Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (BuildContext context) => StepperScreen(
          stepper: CreateTokenStepperPage(sender: sender),
          onStepperNotificationSeeMorePressed:
              widget.options.onStepperNotificationSeeMorePressed,
        ),
      ),
    );
  }
}
