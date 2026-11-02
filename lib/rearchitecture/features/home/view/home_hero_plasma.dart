part of 'home_hero.dart';

class _HomeHeroPlasma extends StatelessWidget {
  const _HomeHeroPlasma({required this.snapshot, required this.status});

  final HomeSnapshot? snapshot;
  final Stream<PowGenerationState> status;

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = AppTokens.of(context);
    final TextStyle label = ledgerLabelStyle(context);
    final HomeSnapshot? current = snapshot;
    final double ratio = current == null || current.maxPlasma <= 0
        ? 0
        : (current.currentPlasma / current.maxPlasma).clamp(0, 1).toDouble();
    final String level = current == null
        ? ''
        : current.maxPlasma <= 0
        ? context.l10n.homePlasmaNone
        : ratio >= 0.66
        ? context.l10n.homePlasmaHigh
        : ratio >= 0.33
        ? context.l10n.homePlasmaMedium
        : context.l10n.homePlasmaLow;
    final String note = current == null
        ? ''
        : current.sendsCovered <= 0
        ? context.l10n.homePlasmaNeedsWork
        : context.l10n.homePlasmaSends(current.sendsCovered);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(context.l10n.plasma.toUpperCase(), style: label),
            ),
            ValueFlash(
              key: ValueKey<bool>(current == null),
              value: level,
              color: tokens.qsrInk,
              child: Text(
                level.toUpperCase(),
                key: const Key('home_plasma_level'),
                style: label,
              ),
            ),
          ],
        ),
        SizedBox(height: tokens.heroSymbolGap),
        StreamBuilder<PowGenerationState>(
          stream: status,
          builder:
              (BuildContext context, AsyncSnapshot<PowGenerationState> work) =>
                  PlasmaMeter(
                    key: const Key('home_plasma_meter'),
                    value: ratio,
                    trackColor: tokens.line,
                    active:
                        !work.hasError &&
                        work.connectionState != ConnectionState.done &&
                        (work.data?.isGenerating ?? false),
                  ),
        ),
        SizedBox(height: tokens.heroSymbolGap),
        ValueFlash(
          key: ValueKey<bool>(current == null),
          value: note,
          color: tokens.qsrInk,
          child: Text(
            note,
            key: const Key('home_plasma_note'),
            style: tokens.compactText.copyWith(color: tokens.dim),
          ),
        ),
      ],
    );
  }
}
