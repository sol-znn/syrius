part of 'originals_card.dart';

class _OriginalsTiles extends StatelessWidget {
  const _OriginalsTiles({required this.isCurrent, this.artBuilder});

  final bool Function() isCurrent;
  final OriginalsArtBuilder? artBuilder;

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = AppTokens.of(context);
    final List<LocalKey> keys = <LocalKey>[
      for (final OriginalsArt art in OriginalsArt.values)
        ValueKey<OriginalsArt>(art),
    ];
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        ListEntrance(
          itemKeys: keys,
          child: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              final double minimum = MediaQuery.textScalerOf(
                context,
              ).scale(tokens.originalsTileMinWidth);
              final int columns =
                  ((constraints.maxWidth + tokens.originalsTileGap) /
                          (minimum + tokens.originalsTileGap))
                      .floor()
                      .clamp(1, 6);
              final double width =
                  (constraints.maxWidth -
                      (columns - 1) * tokens.originalsTileGap) /
                  columns;
              return Wrap(
                spacing: tokens.originalsTileGap,
                runSpacing: tokens.originalsBodyGap,
                children: <Widget>[
                  for (final OriginalsArt art in OriginalsArt.values)
                    SizedBox(
                      width: width,
                      child: ListEntranceItem(
                        key: ValueKey<OriginalsArt>(art),
                        child: _OriginalsTile(
                          art: art,
                          isCurrent: isCurrent,
                          artBuilder: artBuilder,
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
        SizedBox(height: tokens.originalsBodyGap),
        const Divider(height: 1),
        SizedBox(height: tokens.originalsBodyGap),
        Wrap(
          spacing: tokens.originalsMiniGroupGap,
          runSpacing: tokens.originalsTileGap,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: <Widget>[
            _OriginalsMini(
              asset: AppLottieAsset.plasmaGeneration,
              label: context.l10n.originalsPlasma,
              animate: artBuilder == null,
            ),
            _OriginalsMini(
              asset: AppLottieAsset.eye,
              label: context.l10n.originalsHidden,
              animate: artBuilder == null,
            ),
            _OriginalsMini(
              asset: AppLottieAsset.noData,
              label: context.l10n.originalsEmpty,
              animate: artBuilder == null,
            ),
            Text(context.l10n.originalsHover, style: tokens.settingsHintText),
          ],
        ),
      ],
    );
  }
}

class _OriginalsTile extends StatefulWidget {
  const _OriginalsTile({
    required this.art,
    required this.isCurrent,
    this.artBuilder,
  });

  final OriginalsArt art;
  final bool Function() isCurrent;
  final OriginalsArtBuilder? artBuilder;

  @override
  State<_OriginalsTile> createState() => _OriginalsTileState();
}

class _OriginalsTileState extends State<_OriginalsTile>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animation = AnimationController(
    vsync: this,
    animationBehavior: AnimationBehavior.preserve,
  );
  final LaunchFilmController _film = LaunchFilmController();
  Timer? _start;

  bool get _current =>
      mounted && widget.isCurrent() && TickerMode.valuesOf(context).enabled;

  void _play() {
    if (!_current || widget.artBuilder != null) return;
    _start?.cancel();
    if (widget.art == OriginalsArt.launch) {
      _film.play();
    } else if (_animation.duration != null) {
      _animation.forward(from: 0);
    }
  }

  void _loaded(LottieComposition composition) {
    if (!mounted) return;
    _animation.duration = composition.duration;
    _start?.cancel();
    _start = Timer(const Duration(milliseconds: 40) * widget.art.index, _play);
  }

  @override
  void initState() {
    super.initState();
    if (widget.art == OriginalsArt.launch && widget.artBuilder == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _play());
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = AppTokens.of(context);
    final (String title, String hint) = switch (widget.art) {
      OriginalsArt.launch => (
        context.l10n.originalsLaunch,
        context.l10n.originalsLaunchPlace,
      ),
      OriginalsArt.globe => (
        context.l10n.originalsGlobe,
        context.l10n.originalsGlobePlace,
      ),
      OriginalsArt.map => (
        context.l10n.originalsMap,
        context.l10n.originalsMapPlace,
      ),
      OriginalsArt.pillar => (
        context.l10n.originalsPillar,
        context.l10n.originalsPillarPlace,
      ),
      OriginalsArt.sentinel => (
        context.l10n.originalsSentinel,
        context.l10n.originalsSentinelPlace,
      ),
      OriginalsArt.zts => (
        context.l10n.originalsZts,
        context.l10n.originalsZtsPlace,
      ),
    };
    return MouseRegion(
      key: ValueKey<String>('originals_tile_${widget.art.name}'),
      onEnter: (_) => _play(),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Container(
            height: tokens.originalsArtHeight,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: widget.art == OriginalsArt.launch
                  ? tokens.launchStageBackground
                  : tokens.card2,
              border: Border.all(
                color: widget.art == OriginalsArt.launch
                    ? tokens.launchStageBackground
                    : tokens.line,
              ),
              borderRadius: BorderRadius.circular(tokens.cardRadius),
            ),
            child:
                widget.artBuilder?.call(context, widget.art) ??
                _buildArt(tokens),
          ),
          SizedBox(height: tokens.originalsTileCaptionGap),
          Text(title, style: tokens.originalsTileTitleText),
          SizedBox(height: tokens.originalsTileCaptionGap),
          Text(hint, style: tokens.settingsHintText),
        ],
      ),
    );
  }

  Widget _buildArt(AppTokens tokens) {
    if (widget.art == OriginalsArt.launch) {
      return LaunchFilm(
        asset: 'assets/images/launch_well.webp',
        autoplay: false,
        controller: _film,
        fit: BoxFit.cover,
      );
    }
    final AppLottieAsset asset = switch (widget.art) {
      OriginalsArt.globe => AppLottieAsset.globe,
      OriginalsArt.map => AppLottieAsset.map,
      OriginalsArt.pillar => AppLottieAsset.pillar,
      OriginalsArt.sentinel => AppLottieAsset.sentinel,
      OriginalsArt.zts => AppLottieAsset.zts,
      OriginalsArt.launch => throw StateError('Launch uses its original film'),
    };
    final double width = switch (widget.art) {
      OriginalsArt.globe => tokens.originalsGlobeWidth,
      OriginalsArt.map => tokens.originalsMapWidth,
      OriginalsArt.zts => tokens.originalsZtsSize,
      _ => tokens.originalsObjectSize,
    };
    final bool wide =
        widget.art == OriginalsArt.globe || widget.art == OriginalsArt.map;
    final double height = wide ? width / tokens.originalsWideArtAspect : width;
    return OverflowBox(
      maxWidth: width,
      maxHeight: height,
      child: SizedBox(
        width: width,
        height: height,
        child: AppLottie(
          asset,
          controller: _animation,
          repeat: false,
          fit: BoxFit.contain,
          onLoaded: _loaded,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _start?.cancel();
    _animation.dispose();
    _film.dispose();
    super.dispose();
  }
}

class _OriginalsMini extends StatefulWidget {
  const _OriginalsMini({
    required this.asset,
    required this.label,
    required this.animate,
  });

  final AppLottieAsset asset;
  final String label;
  final bool animate;

  @override
  State<_OriginalsMini> createState() => _OriginalsMiniState();
}

class _OriginalsMiniState extends State<_OriginalsMini>
    with SingleTickerProviderStateMixin {
  late final AnimationController _clock = AnimationController(
    vsync: this,
    animationBehavior: AnimationBehavior.preserve,
  );

  void _loaded(LottieComposition composition) {
    if (!mounted) return;
    _clock.duration = composition.duration;
    // The shipped eye's 232 frames include its idle opening. The gallery
    // repeats the same 30..200 blink interval as the original mockup.
    unawaited(
      widget.asset == AppLottieAsset.eye
          ? _clock.repeat(min: 30 / 232, max: 200 / 232)
          : _clock.repeat(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = AppTokens.of(context);
    final double size = widget.asset == AppLottieAsset.noData
        ? tokens.originalsEmptyMarkSize
        : tokens.originalsMiniMarkSize;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        SizedBox(
          width: size,
          height: size,
          child: widget.animate
              ? ClipRect(
                  child: OverflowBox(
                    maxWidth: widget.asset == AppLottieAsset.eye
                        ? tokens.originalsEyeSize
                        : size,
                    maxHeight: widget.asset == AppLottieAsset.eye
                        ? tokens.originalsEyeSize
                        : size,
                    child: AppLottie(
                      widget.asset,
                      size: widget.asset == AppLottieAsset.eye
                          ? tokens.originalsEyeSize
                          : size,
                      controller: _clock,
                      onLoaded: _loaded,
                    ),
                  ),
                )
              : const SizedBox.shrink(),
        ),
        SizedBox(width: tokens.originalsMiniMarkGap),
        Flexible(child: Text(widget.label, style: tokens.settingsHintText)),
      ],
    );
  }

  @override
  void dispose() {
    _clock.dispose();
    super.dispose();
  }
}
