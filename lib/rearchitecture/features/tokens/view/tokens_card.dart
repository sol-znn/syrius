import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/all_tokens/all_tokens.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/token_balance/token_balance.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/token_favorite/repository/favorite_tokens_repository.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/tokens/controller/tokens_page_controller.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/tokens/token_list_projection.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/tokens/widgets/widgets.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/extensions/buildcontext_extension.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/list_entrance.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/motion/motion.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/page/empty_note.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/page/page_widgets.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/row_detail.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/segment.dart';
import 'package:zenon_syrius_wallet_flutter/utils/app_theme.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

/// One token ledger. Search and filters share the same complete sources.
class TokensCard extends StatefulWidget {
  /// The session may retain presentation state while this view is unmounted.
  const TokensCard({
    this.controller,
    this.catalog,
    this.balances = const TokenBalanceState(),
    this.favoriteRepository,
    this.onSendToken,
    super.key,
  });

  /// The shell's pure presentation state, owned here when absent.
  final TokensPageController? controller;

  /// The complete catalog, with its live request context.
  final AllTokensState? catalog;

  /// Successful selected-account balances, or an explicit unknown state.
  final TokenBalanceState balances;

  /// Injectable persistence so presentation tests need no wallet or Hive files.
  final FavoriteTokensRepository? favoriteRepository;

  /// Opens the existing Send mode for one exact token standard.
  final ValueChanged<String>? onSendToken;

  @override
  State<TokensCard> createState() => _TokensCardState();
}

class _TokensCardState extends State<TokensCard> {
  late TokensPageController _controller;
  late TextEditingController _search;
  late ScrollController _scroll;
  late PersistedFavoriteTokensRepository _favorites;
  StreamSubscription<void>? _favoriteChanges;
  late TokensFilter _lastFilter;
  late String _lastQuery;
  final GlobalKey<RowDetailGroupState> _details =
      GlobalKey<RowDetailGroupState>();
  int _detailEpoch = 0;
  String? _rowIdentity;

  @override
  void initState() {
    super.initState();
    _attachFavorites();
    _attach();
  }

  void _attachFavorites() {
    unawaited(_favoriteChanges?.cancel());
    final FavoriteTokensRepository repository =
        widget.favoriteRepository ?? HiveFavoriteTokensRepository();
    _favorites = repository is PersistedFavoriteTokensRepository
        ? repository
        : PersistedFavoriteTokensRepository(repository);
    _favoriteChanges = _favorites.changes.listen((_) => _favoriteChanged());
  }

  void _attach() {
    _controller = widget.controller ?? TokensPageController();
    _lastFilter = _controller.filter;
    _lastQuery = _controller.query;
    _search = TextEditingController(text: _controller.query);
    _scroll = ScrollController(initialScrollOffset: _controller.scrollOffset)
      ..addListener(_rememberScroll);
    _controller.addListener(_presentationChanged);
  }

  void _detach({required bool ownsController}) {
    _controller.removeListener(_presentationChanged);
    _scroll
      ..removeListener(_rememberScroll)
      ..dispose();
    _search.dispose();
    if (ownsController) _controller.dispose();
  }

  @override
  void didUpdateWidget(TokensCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      _detach(ownsController: oldWidget.controller == null);
      _attach();
    }
    if (oldWidget.favoriteRepository != widget.favoriteRepository) {
      _attachFavorites();
    }
  }

  void _rememberScroll() {
    if (_scroll.hasClients) _controller.rememberScroll(_scroll.offset);
  }

  void _presentationChanged() {
    final bool selectionChanged =
        _lastFilter != _controller.filter || _lastQuery != _controller.query;
    _lastFilter = _controller.filter;
    _lastQuery = _controller.query;
    if (_search.text != _controller.query) {
      _search.value = TextEditingValue(
        text: _controller.query,
        selection: TextSelection.collapsed(offset: _controller.query.length),
      );
    }
    if (selectionChanged && _scroll.hasClients) _scroll.jumpTo(0);
    if (selectionChanged) {
      _detailEpoch++;
      _details.currentState?.close();
    }
    setState(() {});
  }

  @override
  void dispose() {
    _detailEpoch++;
    unawaited(_favoriteChanges?.cancel());
    _detach(ownsController: widget.controller == null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AllTokensState? provided = widget.catalog;
    if (provided == null) {
      return BlocBuilder<AllTokensBloc, AllTokensState>(
        builder: (BuildContext context, AllTokensState state) =>
            _buildCard(state),
      );
    }
    return _buildCard(provided);
  }

  Widget _buildCard(AllTokensState catalogState) {
    final AppTokens tokens = AppTokens.of(context);
    final AllTokensPopulated? complete =
        catalogState is AllTokensPopulated && catalogState.isCurrent
        ? catalogState
        : null;
    final TokenBalanceSnapshot? balances = widget.balances.current;
    final Set<String> favorites = <String>{
      for (final Token token in <Token>[
        ...complete?.data ?? <Token>[],
        ...balances?.heldTokens ?? <Token>[],
      ])
        if (_favorites.contains(token.tokenStandard))
          token.tokenStandard.toString(),
    };
    final List<Token>? rows = TokenListProjection(
      catalog: complete?.data,
      balances: balances,
      favorites: favorites,
      filter: _controller.filter,
      query: _controller.query,
    ).rows;
    final String? rowIdentity = rows
        ?.map((Token token) => token.tokenStandard.toString())
        .join(':');
    if (rowIdentity != _rowIdentity) {
      _rowIdentity = rowIdentity;
      _detailEpoch++;
    }
    final int detailEpoch = _detailEpoch;
    final bool failed = _controller.filter == TokensFilter.held
        ? widget.balances.failed
        : catalogState is AllTokensFailure;

    return Panel(
      key: const Key('tokens_list'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: tokens.panelHeaderPadding,
            child: LayoutBuilder(
              builder: (BuildContext context, BoxConstraints constraints) {
                final Widget segment = Segment<TokensFilter>(
                  keyPrefix: 'tokens_filter',
                  selected: _controller.filter,
                  onChanged: _controller.selectFilter,
                  items: <SegmentItem<TokensFilter>>[
                    SegmentItem<TokensFilter>(
                      value: TokensFilter.held,
                      label: context.l10n.tokensHeld,
                    ),
                    SegmentItem<TokensFilter>(
                      value: TokensFilter.favorites,
                      label: context.l10n.tokensFavorites,
                    ),
                    SegmentItem<TokensFilter>(
                      value: TokensFilter.all,
                      label: context.l10n.tokensAll,
                    ),
                  ],
                );
                final Widget search = SizedBox(
                  width: tokens.tokenSearchWidth,
                  height: tokens.tokenSearchHeight,
                  child: _SearchField(
                    controller: _search,
                    onChanged: _controller.setQuery,
                  ),
                );
                if (constraints.maxWidth < tokens.tokenSearchWidth * 2) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      segment,
                      SizedBox(height: tokens.inlineGap),
                      search,
                    ],
                  );
                }
                return Row(children: <Widget>[segment, const Spacer(), search]);
              },
            ),
          ),
          const Divider(height: 1),
          ConstrainedBox(
            constraints: BoxConstraints(minHeight: tokens.tokenHeaderHeight),
            child: const TokenListHeader(),
          ),
          const Divider(height: 1),
          Expanded(
            child: RowDetailGroup(
              key: _details,
              onChanged: (_) {
                _detailEpoch++;
                if (mounted) setState(() {});
              },
              child: ListEntrance(
                itemKeys: <LocalKey>[
                  for (final Token token in rows ?? <Token>[])
                    ValueKey<String>(token.tokenStandard.toString()),
                ],
                child: rows == null
                    ? failed
                          ? Center(
                              child: Text(
                                _controller.filter == TokensFilter.held
                                    ? context.l10n.tokensBalanceUnavailable
                                    : context.l10n.tokensCatalogUnavailable,
                                style: tokens.compactText.copyWith(
                                  color: tokens.dim,
                                ),
                              ),
                            )
                          : Padding(
                              padding: tokens.cardPadding,
                              child: const SkeletonRows(),
                            )
                    : rows.isEmpty
                    ? EmptyNote(text: context.l10n.noItemsFound)
                    : ListView.builder(
                        key: const Key('tokens_rows'),
                        controller: _scroll,
                        itemCount: rows.length,
                        itemBuilder: (BuildContext context, int index) {
                          final Token token = rows[index];
                          return ListEntranceItem(
                            key: ValueKey<String>(
                              token.tokenStandard.toString(),
                            ),
                            child: Column(
                              children: <Widget>[
                                TokenCard(
                                  key: ValueKey<String>(
                                    'token_row_${token.tokenStandard}',
                                  ),
                                  token: token,
                                  balance: balances?.unitsFor(
                                    token.tokenStandard,
                                  ),
                                  favoriteRepository: _favorites,
                                  favoritesCallback: _favoriteChanged,
                                  onSendToken: widget.onSendToken,
                                  detailIsCurrent: () =>
                                      mounted &&
                                      detailEpoch == _detailEpoch &&
                                      _details.currentState?.openId ==
                                          token.tokenStandard.toString(),
                                  isCurrent: () =>
                                      mounted &&
                                      complete != null &&
                                      complete.isCurrent,
                                ),
                                const Divider(height: 1),
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _favoriteChanged() {
    if (mounted) setState(() {});
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({required this.controller, required this.onChanged});

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = AppTokens.of(context);
    return TextField(
      key: const Key('tokens_search_field'),
      controller: controller,
      style: tokens.compactText,
      decoration: InputDecoration(
        isDense: true,
        contentPadding: EdgeInsetsDirectional.symmetric(
          horizontal: tokens.pageGap,
        ),
        hintText: context.l10n.tokensSearchHint,
        prefixIcon: const Icon(Icons.search, size: kTokenRowActionIconSize),
        prefixIconConstraints: BoxConstraints.tightFor(
          width: tokens.tokenSearchHeight,
          height: tokens.tokenSearchHeight,
        ),
        suffixIconConstraints: BoxConstraints.tightFor(
          width: tokens.tokenSearchHeight,
          height: tokens.tokenSearchHeight,
        ),
        suffixIcon: controller.text.isEmpty
            ? null
            : TokenRowAction(
                tooltip: context.l10n.tokensSearchClear,
                icon: const Icon(Icons.close),
                onPressed: () {
                  controller.clear();
                  onChanged('');
                },
              ),
      ),
      onChanged: onChanged,
    );
  }
}
