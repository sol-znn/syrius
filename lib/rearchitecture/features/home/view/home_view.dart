import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import 'package:zenon_syrius_wallet_flutter/main.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/features.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/home/cubit/home_collection_controller.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/home/view/home_hero.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/home/view/home_side_cards.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/transfer/view/transfer_page.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/blocs/infinite_list/infinite_list_bloc.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/extensions/buildcontext_extension.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/models/card/card.dart';
import 'package:zenon_syrius_wallet_flutter/utils/app_theme.dart';
import 'package:zenon_syrius_wallet_flutter/utils/global.dart';
import 'package:zenon_syrius_wallet_flutter/utils/notifiers/default_address_notifier.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/main_app_container.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/shell/page_refresh.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/shell/strip/flight.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

/// One address's balance, activity and session-owned collection summaries.
class HomeView extends StatelessWidget {
  /// Creates Home without constructing another transaction owner.
  const HomeView({
    required this.changePage,
    this.openTransfer,
    this.collectionOwner,
    this.collectionSession,
    super.key,
  });

  /// Moves to an existing wallet destination.
  final void Function(Tabs) changePage;

  /// Chooses the existing Transfer session mode before navigating.
  final ValueChanged<TransferMode>? openTransfer;

  /// Resolves the shell owner after every real selected-address change.
  final HomeCollectionController? Function()? collectionOwner;

  /// Captures the context before an explicit collection or snapshot read.
  final HomeCollectionSession? Function()? collectionSession;

  @override
  Widget build(BuildContext context) => Consumer<SelectedAddressNotifier>(
    builder: (BuildContext context, _, _) {
      final String address = kSelectedAddress!;
      final HomeCollectionController? collection = collectionOwner?.call();
      return BlocProvider<HomeCubit>(
        key: ValueKey<String>(address),
        create: (_) {
          final HomeCubit cubit = HomeCubit(
            read: () async {
              final Zenon client = zenon!;
              final HomeCollectionSession? session = collectionSession?.call();
              final HomeCollectionRead? read = collection?.beginRead();
              final HomeSnapshot snapshot = await HomeSnapshot.read(
                client,
                Address.parse(address),
              );
              if (read != null) {
                collection!.completeRead(
                  read,
                  isCurrent:
                      session != null &&
                      session.address == address &&
                      session.isCurrent(),
                  snapshot: snapshot,
                );
              }
              return snapshot;
            },
          );
          unawaited(cubit.refresh());
          return cubit;
        },
        child: _View(
          address: address,
          changePage: changePage,
          openTransfer: openTransfer,
          collection: collection,
          collectionSession: collectionSession,
        ),
      );
    },
  );
}

class _View extends StatelessWidget {
  const _View({
    required this.address,
    required this.changePage,
    this.openTransfer,
    this.collection,
    this.collectionSession,
  });

  final String address;
  final void Function(Tabs) changePage;
  final ValueChanged<TransferMode>? openTransfer;
  final HomeCollectionController? collection;
  final HomeCollectionSession? Function()? collectionSession;

  void _openTransfer(TransferMode mode) {
    if (openTransfer != null) {
      openTransfer!(mode);
    } else {
      changePage(Tabs.transfer);
    }
  }

  Widget _buildSideCards(BuildContext context, HomeState state) {
    final HomeCollectionController? owner = collection;
    Widget content() => HomeSideCards(
      snapshot: state.snapshot,
      failed: state.status == HomeStatus.failed,
      collectEnabled: owner?.canCollect(state.snapshot) ?? false,
      collectBusy: owner?.busy ?? false,
      collectionNotice: owner?.unresolved == null
          ? null
          : context.l10n.homeCollectionUncertain,
      onCollectAll: owner == null
          ? null
          : () {
              final HomeSnapshot? snapshot = state.snapshot;
              final HomeCollectionSession? session = collectionSession?.call();
              if (snapshot != null &&
                  session != null &&
                  session.address == address) {
                unawaited(owner.collect(snapshot: snapshot, session: session));
              }
            },
      flight:
          owner?.flight ??
          const AlwaysStoppedAnimation<List<InFlightBlock>>(<InFlightBlock>[]),
    );
    return owner == null
        ? content()
        : ListenableBuilder(listenable: owner, builder: (_, _) => content());
  }

  @override
  Widget build(BuildContext context) => PageRefreshAction(
    onRefresh: () {
      context.read<LatestTransactionsBloc>().add(
        InfiniteListRefreshRequested(address: Address.parse(address)),
      );
      unawaited(context.read<HomeCubit>().refresh());
    },
    child: BlocBuilder<HomeCubit, HomeState>(
      builder: (BuildContext context, HomeState state) {
        final double gap = AppTokens.of(context).homePanelGap;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            HomeHero(
              key: const Key('home_hero'),
              address: address,
              snapshot: state.snapshot,
              failed: state.status == HomeStatus.failed,
              onOpenTransfer: _openTransfer,
            ),
            SizedBox(height: gap),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Expanded(
                    flex: 8,
                    child: LatestTransactionsCard(
                      type: CardType.latestTransactionsDashboard,
                      address: address,
                      chainId: collection?.chainId,
                    ),
                  ),
                  SizedBox(width: gap),
                  Expanded(flex: 5, child: _buildSideCards(context, state)),
                ],
              ),
            ),
          ],
        );
      },
    ),
  );
}
