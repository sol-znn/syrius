import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/l10n/app_localizations.dart';
import 'package:zenon_syrius_wallet_flutter/l10n/l10n.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/card_parts/card_parts.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/features.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/utils.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/eye_toggle.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/ltr.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/page/empty_note.dart';
import 'package:zenon_syrius_wallet_flutter/utils/utils.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

/// Stakes belonging to the selected address, with their unlock status.
class StakesCard extends StatelessWidget {
  /// Creates a stakes list card.
  const StakesCard({this.onRefresh, super.key});

  /// Refreshes the page's other figures when the list changes or is retried.
  final VoidCallback? onRefresh;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<StakesBloc, InfiniteListState<StakeEntry>>(
      builder: (BuildContext context, InfiniteListState<StakeEntry> state) {
        final List<StakeEntry> stakes = state.data ?? const <StakeEntry>[];
        void refresh() {
          _refreshStakes(context);
          onRefresh?.call();
        }

        return Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _Head(
                count: stakes.length,
                retry: state.status == InfiniteListStatus.failure
                    ? refresh
                    : null,
              ),
              const Divider(),
              Expanded(
                // The view owns arrival history, so reloading or emptying the
                // table cannot make old stake identities enter a second time.
                child: ListEntrance(
                  key: ValueKey<String>('stakes_$kSelectedAddress'),
                  itemKeys: stakes.map(_stakeKey).toList(),
                  child: StateSwitcher(
                    child: switch (state.status) {
                      InfiniteListStatus.initial => const _Loading(
                        key: ValueKey<String>('loading'),
                      ),
                      InfiniteListStatus.failure => CardNote.error(
                        state.error!,
                        key: const ValueKey<String>('failure'),
                      ),
                      InfiniteListStatus.success when stakes.isEmpty =>
                        EmptyNote(
                          text: context.l10n.noItemsFound,
                          key: const ValueKey<String>('empty'),
                        ),
                      InfiniteListStatus.success => _Populated(
                        key: const ValueKey<String>('table'),
                        hasReachedMax: state.hasReachedMax,
                        stakes: stakes,
                        onRefresh: refresh,
                      ),
                    },
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

LocalKey _stakeKey(StakeEntry entry) => ValueKey<String>(entry.id.toString());

class _Head extends StatelessWidget {
  const _Head({required this.count, required this.retry});

  final int count;
  final VoidCallback? retry;

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
          Text(context.l10n.stakesListTitle, style: panelTitleStyle(context)),
          if (count > 0) ...<Widget>[
            SizedBox(width: tokens.cardGap),
            Text(
              MaterialLocalizations.of(context).formatDecimal(count),
              key: const Key('staking_stakes_count'),
              style: tokens.dataText.copyWith(
                fontSize: 11,
                color: tokens.faint,
              ),
            ),
          ],
          if (retry != null) ...<Widget>[
            const Spacer(),
            RefreshButton(onPressed: retry!),
          ],
        ],
      ),
    );
  }
}

/// The table's head, and a row with a Cancel button in it, as the table
/// lays them out; the loading bars are spaced by them.
const double _kHeadHeight = 40;
const double _kRowHeight = 26 + kInfiniteTableHorizontalPadding;
const double _kSkeletonBar = 12;

/// The list while it loads: a bar where each of the first rows will be,
/// under the space the column names take.
class _Loading extends StatelessWidget {
  const _Loading({super.key});

  @override
  Widget build(BuildContext context) {
    // A short card shows fewer bars instead of overflowing.
    return const SingleChildScrollView(
      physics: NeverScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(
        kInfiniteTableHorizontalPadding,
        _kHeadHeight + 1 + (_kRowHeight - _kSkeletonBar) / 2,
        kInfiniteTableHorizontalPadding,
        0,
      ),
      child: SkeletonRows(gap: _kRowHeight + 1 - _kSkeletonBar),
    );
  }
}

class _Populated extends StatelessWidget {
  const _Populated({
    required this.hasReachedMax,
    required this.stakes,
    required this.onRefresh,
    super.key,
  });

  final bool hasReachedMax;
  final List<StakeEntry> stakes;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = AppTokens.of(context);
    return SizedBox.expand(
      child: InfiniteScrollTable<StakeEntry>(
        itemKeyGenerator: _stakeKey,
        rowBuilder: (StakeEntry entry, int index, Widget row) =>
            ListEntranceItem(key: _stakeKey(entry), child: row),
        items: stakes,
        hasReachedMax: hasReachedMax,
        columns: const <InfiniteScrollTableColumnType>[
          .amount,
          .duration,
          .date,
          .expiration,
          .blank,
        ],
        heads: <InfiniteScrollTableColumnType, InfiniteScrollTableHead>{
          .date: InfiniteScrollTableHead(name: context.l10n.stakingStarted),
          .expiration: InfiniteScrollTableHead(
            name: context.l10n.stakingUnlocks,
          ),
          .blank: const InfiniteScrollTableHead(flex: 2),
        },
        generateRowCells: (StakeEntry stakeEntry) => <Widget>[
          InfiniteScrollTableCell(
            // Aligned, so the flash is as wide as the amount and not as
            // the column. The row is keyed by the stake, so only a change
            // to this stake's amount flashes.
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: ValueFlash(
                value: stakeEntry.amount,
                color: tokens.znnInk,
                child: HiddenAmount(
                  child: Ltr(
                    child: AmountText(
                      stakeEntry.amount,
                      decimals: kZnnCoin.decimals,
                      style: cardValueStyle(context),
                      symbol: kZnnCoin.symbol,
                    ),
                  ),
                ),
              ),
            ),
          ),
          InfiniteScrollTableCell.withText(
            content: stakeDurationText(
              stakeEntry.expirationTimestamp - stakeEntry.startTimestamp,
              context.l10n,
            ),
            textStyle: tokens.dataText.copyWith(fontSize: 13),
          ),
          InfiniteScrollTableCell.withText(
            content: _startedText(stakeEntry, context),
            tooltipMessage: FormatUtils.formatDateTimeSeconds(
              stakeEntry.startTimestamp * Duration.millisecondsPerSecond,
              locale: Localizations.localeOf(context),
            ),
            textStyle: tokens.dataText.copyWith(
              fontSize: 13,
              color: tokens.dim,
            ),
          ),
          InfiniteScrollTableCell(
            child: Align(
              alignment: AlignmentDirectional.center,
              child: Tooltip(
                message: FormatUtils.formatDateTimeSeconds(
                  stakeEntry.expirationTimestamp *
                      Duration.millisecondsPerSecond,
                  locale: Localizations.localeOf(context),
                ),
                child: _Unlocks(stakeEntry: stakeEntry, onRefresh: onRefresh),
              ),
            ),
          ),
          InfiniteScrollTableCell(
            flex: 2,
            child: Align(
              alignment: AlignmentDirectional.centerEnd,
              child: _Action(stakeEntry: stakeEntry, onRefresh: onRefresh),
            ),
          ),
        ],
        onScrollReachedBottom: () {
          context.read<StakesBloc>().add(
            InfiniteListMoreRequested(
              address: Address.parse(kSelectedAddress!),
            ),
          );
        },
      ),
    );
  }
}

String _startedText(StakeEntry entry, BuildContext context) {
  final int elapsed =
      DateTime.now().millisecondsSinceEpoch ~/ Duration.millisecondsPerSecond -
      entry.startTimestamp;
  if (elapsed < 0) {
    return FormatUtils.formatDate(
      entry.startTimestamp * Duration.millisecondsPerSecond,
      locale: Localizations.localeOf(context),
    );
  }
  if (elapsed >= stakeTimeUnitSec) {
    return context.l10n.stakingStartedMonthsAgo(elapsed ~/ stakeTimeUnitSec);
  }
  final Duration age = Duration(seconds: elapsed);
  if (age.inDays > 0) return context.l10n.stakingStartedDaysAgo(age.inDays);
  return FormatUtils.formatDataShort(
    age.inMilliseconds,
    locale: Localizations.localeOf(context),
  );
}

int _secondsLeft(StakeEntry entry) =>
    entry.expirationTimestamp -
    DateTime.now().millisecondsSinceEpoch ~/ Duration.millisecondsPerSecond;

class _Unlocks extends StatelessWidget {
  const _Unlocks({required this.stakeEntry, required this.onRefresh});

  final StakeEntry stakeEntry;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final int secondsLeft = _secondsLeft(stakeEntry);
    if (secondsLeft <= 0) {
      return _UnlockChip(text: context.l10n.stakingUnlocked, unlocked: true);
    }
    return CancelCountdown(
      key: ValueKey<int>(stakeEntry.expirationTimestamp),
      duration: Duration(seconds: secondsLeft),
      onFinished: onRefresh,
      builder: (BuildContext context, String left) {
        final int remaining = _secondsLeft(stakeEntry);
        final String text = remaining >= stakeTimeUnitSec
            ? context.l10n.stakingUnlockMonthsDays(
                remaining ~/ stakeTimeUnitSec,
                Duration(seconds: remaining % stakeTimeUnitSec).inDays,
              )
            : left;
        return _UnlockChip(text: text, unlocked: false);
      },
    );
  }
}

class _UnlockChip extends StatelessWidget {
  const _UnlockChip({required this.text, required this.unlocked});

  final String text;
  final bool unlocked;

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = AppTokens.of(context);
    final Color ink = unlocked ? tokens.znnInk : tokens.qsrInk;
    return DecoratedBox(
      decoration: ShapeDecoration(
        color: (unlocked ? tokens.znn : tokens.qsr).withValues(alpha: 0.14),
        shape: const StadiumBorder(),
      ),
      child: SizedBox(
        height: tokens.smallButtonHeight,
        child: Padding(
          padding: EdgeInsetsDirectional.symmetric(horizontal: tokens.cardGap),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                unlocked ? Icons.check_rounded : Icons.schedule_rounded,
                size: 12,
                color: ink,
              ),
              SizedBox(width: tokens.fieldLabelGap),
              Flexible(
                child: Text(
                  text,
                  style: tokens.dataText.copyWith(fontSize: 12, color: ink),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Action extends StatelessWidget {
  const _Action({required this.stakeEntry, required this.onRefresh});

  final StakeEntry stakeEntry;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = AppTokens.of(context);
    final ButtonStyle style = cardSecondaryButtonStyle(context).copyWith(
      visualDensity: VisualDensity.standard,
      minimumSize: WidgetStatePropertyAll<Size>(
        Size(0, tokens.smallButtonHeight),
      ),
      padding: WidgetStatePropertyAll<EdgeInsetsGeometry>(
        EdgeInsetsDirectional.symmetric(horizontal: tokens.cardGap),
      ),
      textStyle: WidgetStatePropertyAll<TextStyle>(
        tokens.bodyText.copyWith(fontSize: 12),
      ),
    );
    if (_secondsLeft(stakeEntry) > 0) {
      return OutlinedButton(
        key: ValueKey<String>('staking_cancel_locked_${stakeEntry.id}'),
        style: style,
        onPressed: null,
        child: Text(context.l10n.cancel),
      );
    }
    return CancelStakeButton(
      key: ValueKey<String>('staking_withdraw_${stakeEntry.id}'),
      stakeHash: stakeEntry.id,
      amount: stakeEntry.amount,
      onCancelled: onRefresh,
      label: context.l10n.stakingCancelWithdraw,
      style: style,
    );
  }
}

/// A stake's length in the months it was made for: `1 month`, `12 months`.
///
/// In [l10n]'s language, which a widget passes as `context.l10n`; without
/// it, in the app's language of the moment.
String stakeDurationText(int seconds, [AppLocalizations? l10n]) =>
    (l10n ?? currentL10n).stakeDurationMonths(seconds ~/ stakeTimeUnitSec);

void _refreshStakes(BuildContext context) {
  context.read<StakesBloc>().add(
    InfiniteListRefreshRequested(address: Address.parse(kSelectedAddress!)),
  );
}
