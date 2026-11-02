import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:rxdart/rxdart.dart';
import 'package:zenon_syrius_wallet_flutter/blocs/blocs.dart';
import 'package:zenon_syrius_wallet_flutter/main.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/extensions/buildcontext_extension.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/ltr.dart';
import 'package:zenon_syrius_wallet_flutter/utils/app_theme.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/reusable_widgets/app_lottie.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/shell/strip/priority_row.dart';

/// Time that only goes forward, read as the time since some fixed moment.
///
/// Not `DateTime.now`: the wall clock is stepped by the system (a sync, a
/// resume from sleep), and a generation timed across a step came out
/// negative or an hour long.
typedef Uptime = Duration Function();

final Stopwatch _sinceStart = Stopwatch()..start();

Duration _uptime() => _sinceStart.elapsed;

/// How long the last few plasma generations took on this computer.
///
/// Kept in memory for the session and not stored: the time depends on the
/// machine and on what else it is doing, so last week's figure is no better
/// a guide than the first one of today, and the strip says nothing about a
/// typical time until it has measured one.
class PlasmaTimes {
  /// Creates an empty record.
  PlasmaTimes();

  /// The record of this run of the wallet. It outlives the strip, which is
  /// taken down while the wallet is locked.
  static final PlasmaTimes session = PlasmaTimes();

  /// How many generations are remembered. Few, so that a change in the
  /// machine's load shows within a handful of blocks.
  static const int kept = 8;

  final List<Duration> _recent = <Duration>[];

  /// Records one finished generation.
  void add(Duration took) {
    if (took <= Duration.zero) return;
    _recent.add(took);
    if (_recent.length > kept) {
      _recent.removeAt(0);
    }
  }

  /// The median of what is remembered; null before the first generation.
  ///
  /// The median and not the mean: one generation run beside a build takes
  /// several times as long and would pull a mean of eight well off.
  Duration? get typical {
    if (_recent.isEmpty) {
      return null;
    }
    final List<Duration> sorted = <Duration>[..._recent]..sort();
    final int middle = sorted.length ~/ 2;
    return sorted.length.isOdd
        ? sorted[middle]
        : (sorted[middle - 1] + sorted[middle]) ~/ 2;
  }
}

/// The plasma mark. While the wallet generates plasma (proof of work for a
/// block) it is the original bolt tracing its outline, with the seconds so
/// far and how long it usually takes. Idle work adds no strip decoration,
/// matching the mockup; the Plasma page owns the larger glow.
class GenerationStatus extends StatefulWidget {
  /// Creates the plasma mark. Everything is the wallet's own when left out.
  const GenerationStatus({this.status, this.uptime, this.times, super.key});

  /// Says when a generation starts and ends; the wallet's
  /// [PowGeneratingStatusBloc] when null.
  final Stream<PowGenerationState>? status;

  /// The clock the seconds are counted on.
  final Uptime? uptime;

  /// Where finished generations are recorded; [PlasmaTimes.session] when
  /// null.
  final PlasmaTimes? times;

  @override
  State<GenerationStatus> createState() => _GenerationStatusState();
}

class _GenerationStatusState extends State<GenerationStatus> {
  StreamSubscription<PowGenerationState>? _subscription;
  Timer? _ticker;
  Duration? _startedAt;
  PowWorkToken? _activeWork;
  PowWorkToken? _joinedWork;
  int _seconds = 0;
  bool _recorded = true;
  bool _lowerBound = false;
  int _epoch = 0;

  Uptime get _now => widget.uptime ?? _uptime;

  PlasmaTimes get _times => widget.times ?? PlasmaTimes.session;

  @override
  void initState() {
    super.initState();
    _listen();
  }

  @override
  void didUpdateWidget(GenerationStatus oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.status != widget.status ||
        oldWidget.uptime != widget.uptime ||
        oldWidget.times != widget.times) {
      unawaited(_subscription?.cancel());
      _listen();
    }
  }

  void _listen() {
    final int epoch = ++_epoch;
    _ticker?.cancel();
    _ticker = null;
    _startedAt = null;
    _activeWork = null;
    _seconds = 0;
    _lowerBound = false;
    _recorded = false;
    final Stream<PowGenerationState> stream =
        widget.status ?? sl.get<PowGeneratingStatusBloc>().stream;
    // The bloc repeats its last event to a new listener. A strip built
    // while generation runs can only count a lower bound from when it joined.
    // That generation is not a typical-time sample: it would be too short.
    final PowGenerationState? replay = stream is ValueStream<PowGenerationState>
        ? stream.valueOrNull
        : null;
    _joinedWork = (replay?.isGenerating ?? false) ? replay!.work : null;
    _subscription = stream.listen(
      (PowGenerationState status) {
        if (mounted && epoch == _epoch) _onStatus(status);
      },
      // An unavailable source cannot supply a complete generation interval.
      onError: (Object _) {
        if (mounted && epoch == _epoch) {
          _joinedWork = null;
          _finish(completed: false);
        }
      },
      onDone: () {
        if (mounted && epoch == _epoch) _finish(completed: false);
      },
    );
  }

  void _onStatus(PowGenerationState status) {
    final PowWorkToken? work = status.work;
    if (status.isGenerating && work != null) {
      if (_startedAt != null && identical(_activeWork, work)) {
        return;
      }
      _finish(completed: false);
      _lowerBound = identical(_joinedWork, work);
      _recorded = !_lowerBound;
      _joinedWork = null;
      setState(() {
        _activeWork = work;
        _startedAt = _now();
        _seconds = 0;
      });
      final int epoch = _epoch;
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted && epoch == _epoch) _tick();
      });
      return;
    }
    _joinedWork = null;
    if (status.phase == PowGenerationPhase.idle) {
      _finish(completed: false);
    } else if (status.phase == PowGenerationPhase.completed &&
        identical(_activeWork, work)) {
      _finish(completed: true);
    }
  }

  void _finish({required bool completed}) {
    _ticker?.cancel();
    _ticker = null;
    final Duration? startedAt = _startedAt;
    _activeWork = null;
    if (startedAt == null) {
      return;
    }
    if (completed && _recorded) {
      _times.add(_now() - startedAt);
    }
    _recorded = false;
    setState(() {
      _startedAt = null;
      _lowerBound = false;
      _seconds = 0;
    });
  }

  void _tick() {
    final Duration? startedAt = _startedAt;
    if (startedAt == null) {
      return;
    }
    final int elapsed = (_now() - startedAt).inSeconds;
    final int seconds = elapsed < 0 ? 0 : elapsed;
    if (seconds != _seconds) {
      setState(() => _seconds = seconds);
    }
  }

  @override
  void dispose() {
    _epoch++;
    unawaited(_subscription?.cancel());
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_startedAt == null) {
      return const SizedBox.shrink();
    }
    final AppTokens tokens = AppTokens.of(context);
    final TextStyle dim = Theme.of(
      context,
    ).textTheme.titleMedium!.copyWith(fontSize: 13, color: tokens.dim);
    final Duration? typical = _times.typical;
    // The label gives way before the seconds do, and the typical time
    // before either: on a narrow strip the bolt and its count are the news.
    return PriorityRow(
      gap: tokens.statusDotSize,
      fill: false,
      children: <Prioritized>[
        const Prioritized(
          priority: 0,
          // Green and grey strokes, drawn for either ground: it needs no
          // well. 18 px, the size of the strip's text line.
          child: AppLottie(
            AppLottieAsset.plasmaGeneration,
            key: Key('strip_plasma'),
            size: 18,
          ),
        ),
        Prioritized(
          priority: 2,
          shrink: true,
          minWidth: 48,
          child: Text(
            context.l10n.stripGeneratingPlasma,
            style: dim,
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        Prioritized(
          priority: 1,
          child: Ltr(
            child: Text(
              _lowerBound
                  ? context.l10n.stripSecondsAtLeast(_seconds)
                  : context.l10n.stripSeconds(_seconds),
              key: const Key('strip_plasma_elapsed'),
              style: monoStyle(dim),
            ),
          ),
        ),
        if (typical != null)
          Prioritized(
            priority: 3,
            child: Text(
              // Never "about 0 s": a generation under half a second is
              // still about one.
              '· ${context.l10n.stripPlasmaTypical(_wholeSeconds(typical))}',
              key: const Key('strip_plasma_typical'),
              style: dim.copyWith(color: tokens.faint),
            ),
          ),
      ],
    );
  }

  static int _wholeSeconds(Duration duration) {
    final int rounded = (duration.inMilliseconds / 1000).round();
    return rounded < 1 ? 1 : rounded;
  }
}
