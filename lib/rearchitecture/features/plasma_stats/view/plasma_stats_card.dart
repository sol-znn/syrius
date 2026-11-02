import 'dart:math' as math;

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/blocs/blocs.dart';
import 'package:zenon_syrius_wallet_flutter/main.dart' show sl;
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/card_parts/card_parts.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/features.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/utils.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/disclosure.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/eye_toggle.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/page/empty_note.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/plasma_well.dart';
import 'package:zenon_syrius_wallet_flutter/utils/utils.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/widgets.dart'
    hide
        InfiniteScrollTable,
        InfiniteScrollTableCell,
        InfiniteScrollTableHeaderColumn;
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

/// The height of the line that names the list's two columns.
const double _kListHeadHeight = 36;

/// The width a row gives its meter, and its level's name.
const double _kRowMeterWidth = 72;
const double _kRowLevelWidth = 60;

/// The height of a row, which the loading bars are spaced by, and the
/// height of one such bar (`Skeleton`'s default). On the Plasma page the
/// rows are a section that opens under the mark, and are closer.
const double _kRowHeight = 48;
const double _kSkeletonBar = 12;

/// Display variants for [PlasmaStatsCard].
enum PlasmaStatsWidgetVersion {
  /// The list of addresses alone, read only.
  dashboardTab,

  /// The Plasma page's card: the plasma mark and the selected address's
  /// plasma, over the other addresses, closed until asked for, where a row
  /// picks the address to fuse for.
  plasmaTab,
}

/// The plasma of the wallet's addresses.
///
/// On the Plasma page it is the page's mark: the glowing bolt, and under it
/// what the selected address has. The other addresses are one click away.
///
/// Plasma is read one address at a time, so ten addresses are ten calls.
class PlasmaStatsCard extends StatelessWidget {
  /// Creates a Plasma stats card.
  const PlasmaStatsCard({
    this.version = PlasmaStatsWidgetVersion.dashboardTab,
    this.onAddressPicked,
    super.key,
  });

  /// Controls where the card is rendered and which interactions are enabled.
  final PlasmaStatsWidgetVersion version;

  /// On the Plasma page: called after a row made its address the one to
  /// fuse for, so the page can show the form that address went into.
  final VoidCallback? onAddressPicked;

  @override
  Widget build(BuildContext context) {
    if (version == PlasmaStatsWidgetVersion.plasmaTab) {
      return Panel(child: _PageBody(onAddressPicked: onAddressPicked));
    }
    return Panel(
      title: context.l10n.plasma,
      actions: <Widget>[
        RefreshButton(
          onPressed: () => context.read<PlasmaStatsBloc>().add(
            const InfiniteListRefreshRequested(),
          ),
        ),
      ],
      child: BlocBuilder<PlasmaStatsBloc, InfiniteListState<PlasmaInfoWrapper>>(
        builder: (_, InfiniteListState<PlasmaInfoWrapper> state) => _LevelsView(
          state: state,
          items: state.data ?? const <PlasmaInfoWrapper>[],
        ),
      ),
    );
  }
}

/// The Plasma page's card: the mark with the selected address's figures in
/// the height the other addresses leave, and those at the foot.
class _PageBody extends StatelessWidget {
  const _PageBody({required this.onAddressPicked});

  final VoidCallback? onAddressPicked;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final AppTokens tokens = AppTokens.of(context);
        final double height = constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : tokens.plasmaMarkSize + tokens.plasmaFiguresHeight;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const Expanded(child: _Mark()),
            const Divider(),
            _OtherAddresses(
              maxHeight: height * tokens.plasmaOtherShare,
              onPicked: onAddressPicked,
            ),
          ],
        );
      },
    );
  }
}

/// What the head of the card shows of one address's plasma. A record, so
/// the selector that reads it rebuilds only when a figure changed.
typedef _Reading = ({int current, BigInt fused});

/// The plasma mark, and the selected address's plasma under it.
class _Mark extends StatelessWidget {
  const _Mark();

  @override
  Widget build(BuildContext context) {
    // The selected address can change while the page is open.
    context.watch<SelectedAddressNotifier>();
    final String? selected = kSelectedAddress;
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final AppTokens tokens = AppTokens.of(context);
        // The mark gives way before the figures do: they are what is read.
        final double size = (constraints.maxHeight - tokens.plasmaFiguresHeight)
            .clamp(tokens.plasmaMarkMinSize, tokens.plasmaMarkSize);
        // A scroll view that does not scroll: a card shorter than the least
        // mark and the figures cuts them instead of overflowing.
        return SingleChildScrollView(
          physics: const NeverScrollableScrollPhysics(),
          padding: tokens.plasmaMarkPadding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              // The mark paints in its own layer (PlasmaGlow holds the
              // RepaintBoundary), so its frames repaint nothing else here.
              // In the light theme the well gives it the dark ground it was
              // drawn for, a disc as wide as its square: the halo has faded
              // out about 90 px from the middle, inside the disc's 100.
              Center(
                child: _WithPlasmaGeneration(
                  builder: ({required bool generating}) => PlasmaWell(
                    child: PlasmaGlow(
                      key: const Key('plasma_page_mark'),
                      size: size,
                      innerGlow: generating
                          ? tokens.plasmaGeneratingInnerGlow
                          : .5,
                      outerGlow: generating
                          ? tokens.plasmaGeneratingOuterGlow
                          : .3,
                      contour: generating ? tokens.plasmaGeneratingContour : .5,
                    ),
                  ),
                ),
              ),
              BlocSelector<
                PlasmaStatsBloc,
                InfiniteListState<PlasmaInfoWrapper>,
                _Reading?
              >(
                selector: (InfiniteListState<PlasmaInfoWrapper> state) {
                  final PlasmaStatsBloc source = context
                      .read<PlasmaStatsBloc>();
                  if (state.status != InfiniteListStatus.success) {
                    return null;
                  }
                  final PlasmaInfoWrapper? reading = source.currentReading(
                    selected ?? '',
                  );
                  return reading == null
                      ? null
                      : (
                          current: reading.plasmaInfo.currentPlasma,
                          fused: reading.plasmaInfo.qsrAmount,
                        );
                },
                builder: (_, _Reading? reading) => _Figures(reading: reading),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// The selected address's level, plasma and fused QSR. While they are not
/// known the same lines stand empty, so the card does not jump when they
/// arrive; the meter then fills from nothing.
class _Figures extends StatelessWidget {
  const _Figures({required this.reading});

  final _Reading? reading;

  @override
  Widget build(BuildContext context) {
    final _Reading? r = reading;
    final AppTokens tokens = AppTokens.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Center(
          child: ValueFlash(
            key: ValueKey<bool>(r == null),
            value: r?.current,
            color: tokens.qsrInk,
            child: HiddenAmount(
              style: tokens.plasmaAmountText,
              child: r == null
                  ? Text(context.l10n.plasmaPageUnknown, style: tokens.bodyText)
                  : AmountText(
                      BigInt.from(r.current),
                      key: const Key('plasma_page_available'),
                      decimals: 0,
                      style: tokens.plasmaAmountText,
                    ),
            ),
          ),
        ),
        SizedBox(height: tokens.plasmaLevelGap),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Text(
              '${context.l10n.plasma.toUpperCase()} · ',
              style: tokens.ledgerText,
            ),
            PlasmaLevelLabel(plasma: r?.current),
          ],
        ),
        SizedBox(height: tokens.pageGap),
        _WithPlasmaGeneration(
          builder: ({required bool generating}) =>
              PlasmaLevelMeter(plasma: r?.current ?? 0, generating: generating),
        ),
        SizedBox(height: tokens.plasmaLevelGap),
        Row(
          children: <Widget>[
            Text('${context.l10n.plasmaPageFused} ', style: tokens.dollarText),
            Flexible(
              child: HiddenAmount(
                style: tokens.dataText,
                child: r == null
                    ? Text(
                        context.l10n.plasmaPageUnknown,
                        style: tokens.dollarText,
                      )
                    : AmountText(
                        r.fused,
                        key: const Key('plasma_page_fused'),
                        decimals: coinDecimals,
                        style: tokens.dataText,
                        symbol: kQsrCoin.symbol,
                      ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _WithPlasmaGeneration extends StatelessWidget {
  const _WithPlasmaGeneration({required this.builder});
  final Widget Function({required bool generating}) builder;

  @override
  Widget build(BuildContext context) {
    final PowGeneratingStatusBloc? source =
        sl.isRegistered<PowGeneratingStatusBloc>()
        ? sl.get<PowGeneratingStatusBloc>()
        : null;
    return StreamBuilder<PowGenerationState>(
      stream: source?.stream,
      initialData: source?.value ?? const PowGenerationState.idle(),
      builder: (_, AsyncSnapshot<PowGenerationState> state) =>
          builder(generating: state.data?.isGenerating ?? false),
    );
  }
}

/// The wallet's addresses other than the selected one, closed until asked
/// for: at rest the page says only how many there are and how many are low.
class _OtherAddresses extends StatelessWidget {
  const _OtherAddresses({required this.maxHeight, required this.onPicked});

  /// The most height the open list may take.
  final double maxHeight;

  final VoidCallback? onPicked;

  @override
  Widget build(BuildContext context) {
    // The selected address can change while the page is open.
    context.watch<SelectedAddressNotifier>();
    final String? selected = kSelectedAddress;
    return BlocBuilder<PlasmaStatsBloc, InfiniteListState<PlasmaInfoWrapper>>(
      builder:
          (BuildContext context, InfiniteListState<PlasmaInfoWrapper> state) {
            final PlasmaStatsBloc source = context.read<PlasmaStatsBloc>();
            final AppTokens tokens = AppTokens.of(context);
            final bool loaded =
                state.status == InfiniteListStatus.success &&
                source.hasCurrentRead;
            final List<PlasmaInfoWrapper> others = <PlasmaInfoWrapper>[
              for (final PlasmaInfoWrapper w in source.currentReadings)
                if (w.address != selected) w,
            ];
            final int low = others
                .where(
                  (PlasmaInfoWrapper w) =>
                      PlasmaLevel.of(w.plasmaInfo.currentPlasma) ==
                      PlasmaLevel.low,
                )
                .length;
            // Compact rows have no dividers. The list scrolls only after
            // its rows and body inset use the space beneath the figures.
            final double wanted = loaded && others.isNotEmpty
                ? others.length * tokens.plasmaOtherRowHeight +
                      tokens.plasmaOtherListPadding.vertical
                : loaded
                ? tokens.plasmaOtherRowHeight +
                      tokens.plasmaOtherListPadding.vertical
                : tokens.plasmaOtherRowHeight * 2 +
                      tokens.plasmaOtherListPadding.vertical;
            return Disclosure(
              key: const Key('plasma_other_addresses'),
              title: context.l10n.plasmaPageOtherAddresses,
              count: loaded ? others.length : null,
              summary: low > 0 ? context.l10n.plasmaPageLowCount(low) : null,
              storeKey: 'plasma.other_addresses',
              keyPrefix: 'plasma_other_addresses',
              // Mounted while closed: the list is what asks for the next page
              // of addresses, and the selected one may be on it.
              keepAlive: true,
              child: SizedBox(
                height: math.min(wanted, maxHeight),
                child: Padding(
                  padding: tokens.plasmaOtherListPadding,
                  child: _LevelsView(
                    state: loaded || state.status == InfiniteListStatus.failure
                        ? state
                        : const InfiniteListState<PlasmaInfoWrapper>.initial(),
                    items: others,
                    onPage: true,
                    onPicked: onPicked,
                  ),
                ),
              ),
            );
          },
    );
  }
}

/// The level of every address in [items]: loading, failed, empty or listed.
class _LevelsView extends StatelessWidget {
  const _LevelsView({
    required this.state,
    required this.items,
    this.onPage = false,
    this.onPicked,
  });

  final InfiniteListState<PlasmaInfoWrapper> state;

  /// The addresses to list: all the state holds, or those but one.
  final List<PlasmaInfoWrapper> items;

  /// Whether this is the Plasma page's section: closer rows with no column
  /// names over them, where a row picks the address to fuse for.
  final bool onPage;

  final VoidCallback? onPicked;

  @override
  Widget build(BuildContext context) {
    return StateSwitcher(
      child: switch (state.status) {
        InfiniteListStatus.initial => _LevelsLoading(
          key: const ValueKey<String>('loading'),
          onPage: onPage,
        ),
        InfiniteListStatus.failure => CardNote.error(
          state.error!,
          key: const ValueKey<String>('failure'),
        ),
        InfiniteListStatus.success when items.isEmpty && onPage => Align(
          key: const ValueKey<String>('empty'),
          alignment: AlignmentDirectional.centerStart,
          child: EmptyNote.line(text: context.l10n.noItemsFound),
        ),
        InfiniteListStatus.success when items.isEmpty => SyriusErrorWidget(
          context.l10n.noItemsFound,
          key: const ValueKey<String>('empty'),
        ),
        InfiniteListStatus.success => _LevelList(
          key: const ValueKey<String>('list'),
          items: items,
          hasReachedMax: state.hasReachedMax,
          onPage: onPage,
          onPicked: onPicked,
        ),
      },
    );
  }
}

/// The list while it loads: a bar where each of the first rows will be, at
/// the rows' pitch and under the space the column names take, so the list
/// arrives where the bars stood.
class _LevelsLoading extends StatelessWidget {
  const _LevelsLoading({required this.onPage, super.key});

  final bool onPage;

  /// How many rows stand in for the list.
  static const int _rows = 4;

  @override
  Widget build(BuildContext context) {
    final double row = onPage
        ? AppTokens.of(context).plasmaOtherRowHeight
        : _kRowHeight;
    // A short card shows fewer bars instead of overflowing.
    return SingleChildScrollView(
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsetsDirectional.fromSTEB(
        onPage ? 0 : 16,
        (onPage ? 0 : _kListHeadHeight + 1) + (row - _kSkeletonBar) / 2,
        onPage ? 0 : 16,
        0,
      ),
      child: SkeletonRows(
        rows: onPage ? 2 : _rows,
        gap: row + (onPage ? 0 : 1) - _kSkeletonBar,
      ),
    );
  }
}

class _LevelList extends StatefulWidget {
  const _LevelList({
    required this.items,
    required this.hasReachedMax,
    required this.onPage,
    required this.onPicked,
    super.key,
  });

  final List<PlasmaInfoWrapper> items;
  final bool hasReachedMax;
  final bool onPage;
  final VoidCallback? onPicked;

  @override
  State<_LevelList> createState() => _LevelListState();
}

class _LevelListState extends State<_LevelList> {
  final ScrollController _controller = ScrollController();
  bool _requested = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onScroll);
    _requestMoreIfNotFilled();
  }

  @override
  void didUpdateWidget(_LevelList oldWidget) {
    super.didUpdateWidget(oldWidget);
    // By length too: on the Plasma page the list is filtered anew at every
    // build, so it is never the same object twice.
    if (oldWidget.items.length != widget.items.length ||
        (!widget.onPage && !identical(oldWidget.items, widget.items)) ||
        oldWidget.hasReachedMax != widget.hasReachedMax) {
      _requested = false;
      _requestMoreIfNotFilled();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onScroll() {
    final ScrollPosition position = _controller.position;
    if (position.pixels >= position.maxScrollExtent * 0.9) {
      _requestMore();
    }
  }

  /// A first page that fits leaves nothing to scroll, so nothing would ever
  /// ask for the second; ask once the rows are laid out.
  void _requestMoreIfNotFilled() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_controller.hasClients) return;
      if (_controller.position.maxScrollExtent == 0) {
        _requestMore();
      }
    });
  }

  void _requestMore() {
    if (_requested || widget.hasReachedMax) return;
    _requested = true;
    context.read<PlasmaStatsBloc>().add(const InfiniteListMoreRequested());
  }

  @override
  Widget build(BuildContext context) {
    final TextStyle label = ledgerLabelStyle(context);
    Widget itemBuilder(BuildContext context, int index) => _LevelRow(
      key: ValueKey<String>(widget.items[index].address),
      item: widget.items[index],
      onPage: widget.onPage,
      onPicked: widget.onPicked,
    );
    final Widget list = widget.onPage
        ? ListView.builder(
            controller: _controller,
            padding: EdgeInsets.zero,
            itemCount: widget.items.length,
            itemBuilder: itemBuilder,
          )
        : ListView.separated(
            controller: _controller,
            padding: EdgeInsets.zero,
            itemCount: widget.items.length,
            separatorBuilder: (_, _) => const Divider(),
            itemBuilder: itemBuilder,
          );
    if (widget.onPage) {
      return SizedBox.expand(child: list);
    }
    return SizedBox.expand(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SizedBox(
            height: _kListHeadHeight,
            child: Padding(
              padding: const EdgeInsetsDirectional.symmetric(horizontal: 16),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      context.l10n.address.toUpperCase(),
                      style: label,
                    ),
                  ),
                  Text(context.l10n.level.toUpperCase(), style: label),
                ],
              ),
            ),
          ),
          const Divider(),
          Expanded(child: list),
        ],
      ),
    );
  }
}

/// One address and its level. On the Plasma page a click makes it the
/// address the Fuse form fuses for, and the row that is stays marked.
class _LevelRow extends StatelessWidget {
  const _LevelRow({
    required this.item,
    required this.onPage,
    required this.onPicked,
    super.key,
  });

  final PlasmaInfoWrapper item;
  final bool onPage;
  final VoidCallback? onPicked;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final AppTokens tokens = AppTokens.of(context);
    final String address = item.address;
    final String? name = kAddressLabelMap[address];
    final int plasma = item.plasmaInfo.currentPlasma;
    final Widget row = SizedBox(
      height: onPage ? tokens.plasmaOtherRowHeight : _kRowHeight,
      child: Padding(
        padding: onPage
            ? EdgeInsets.zero
            : const EdgeInsetsDirectional.symmetric(horizontal: 16),
        child: Row(
          children: <Widget>[
            // The name and its copy button take all the row leaves after the
            // meter and the level. As a Flexible beside a Spacer the name got
            // half of that, and "Address 4" was cut with the row half empty.
            Expanded(
              child: Row(
                children: <Widget>[
                  Flexible(
                    child: Tooltip(
                      message: address,
                      waitDuration: Durations.long2,
                      child: Text(
                        name ?? Address.parse(address).toShortString(),
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.ellipsis,
                        // An address reads left to right in every language;
                        // a name keeps the app's direction.
                        textDirection: name == null ? TextDirection.ltr : null,
                        style: name == null
                            ? monoStyle(cardValueStyle(context))
                            : cardValueStyle(context),
                      ),
                    ),
                  ),
                  Tooltip(
                    message: context.l10n.commonCopy,
                    child: onPage
                        ? IconButtonTheme(
                            data: IconButtonThemeData(
                              style: IconButton.styleFrom(
                                minimumSize: Size.square(
                                  tokens.plasmaOtherRowHeight,
                                ),
                                padding: EdgeInsets.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                            ),
                            child: CopyToClipboardButton(address, iconSize: 15),
                          )
                        : CopyToClipboardButton(address, iconSize: 15),
                  ),
                ],
              ),
            ),
            SizedBox(
              width: onPage ? tokens.plasmaOtherMeterWidth : _kRowMeterWidth,
              child: PlasmaLevelMeter(plasma: plasma),
            ),
            SizedBox(
              width: _kRowLevelWidth,
              child: Align(
                alignment: AlignmentDirectional.centerEnd,
                child: PlasmaLevelLabel(plasma: plasma),
              ),
            ),
          ],
        ),
      ),
    );
    if (!onPage) {
      return _HoverFill(color: tokens.hover, child: row);
    }
    return BlocSelector<PlasmaBeneficiaryAddressCubit, String?, bool>(
      selector: (String? beneficiary) => beneficiary == address,
      builder: (BuildContext context, bool chosen) => AnimatedContainer(
        duration: Durations.short4,
        curve: Easing.standard,
        color: chosen
            ? theme.colorScheme.primaryContainer
            : theme.colorScheme.primaryContainer.withValues(alpha: 0),
        // The ink goes on a Material above the fill, or the fill hides it.
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            mouseCursor: SystemMouseCursors.click,
            hoverColor: tokens.hover,
            onTap: () {
              context.read<PlasmaBeneficiaryAddressCubit>().changeAddress(
                address,
              );
              onPicked?.call();
            },
            child: row,
          ),
        ),
      ),
    );
  }
}

/// Lays [color] under [child] while the pointer is over it: the hover of a
/// row that is read and not clicked, where an InkWell would show nothing.
class _HoverFill extends StatefulWidget {
  const _HoverFill({required this.color, required this.child});

  final Color color;
  final Widget child;

  @override
  State<_HoverFill> createState() => _HoverFillState();
}

class _HoverFillState extends State<_HoverFill> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: Durations.short3,
        curve: Easing.standard,
        color: _hovered ? widget.color : widget.color.withValues(alpha: 0),
        child: widget.child,
      ),
    );
  }
}
