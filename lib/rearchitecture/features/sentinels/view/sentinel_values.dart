import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/extensions/buildcontext_extension.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/ltr.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/motion/skeleton.dart';
import 'package:zenon_syrius_wallet_flutter/utils/app_theme.dart';
import 'package:zenon_syrius_wallet_flutter/utils/format_utils.dart';
import 'package:zenon_syrius_wallet_flutter/utils/global.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

/// The owner's label or shortened address, with its full value on hover.
class SentinelOwnerText extends StatelessWidget {
  /// Creates the identifier without consulting the selected address.
  const SentinelOwnerText({required this.address, this.style, super.key});

  /// The complete address from the displayed record.
  final String address;

  /// A strip can give the identifier its larger data style.
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final String shortened = address.length <= 13
        ? address
        : '${address.substring(0, 7)}…${address.substring(address.length - 6)}';
    final String text = kAddressLabelMap[address] ?? shortened;
    return Tooltip(
      message: address,
      child: Ltr(
        child: Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: style ?? AppTokens.of(context).dataText,
        ),
      ),
    );
  }
}

/// The chain's registration state. Active does not claim node uptime.
class SentinelStatusChip extends StatelessWidget {
  /// Creates a status or an ownership mark beside an owner address.
  const SentinelStatusChip({
    required this.active,
    this.yours = false,
    this.compact = false,
    super.key,
  });

  /// Whether the record is active according to the sentinel API.
  final bool active;

  /// Marks an exact selected-owner match instead of repeating its status.
  final bool yours;

  /// The strip and ownership mark use the smaller chip height.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = AppTokens.of(context);
    final Color ink = active ? tokens.znnInk : tokens.dim;
    return _FactChip(
      label: yours
          ? context.l10n.sentinelYours
          : active
          ? context.l10n.nodesActive
          : context.l10n.nodesRevoked,
      icon: yours
          ? Icons.person_outline_rounded
          : active
          ? Icons.check_rounded
          : Icons.remove_circle_outline_rounded,
      ink: ink,
      fill: active ? tokens.znn.withValues(alpha: 0.12) : tokens.card,
      line: active ? tokens.znn.withValues(alpha: 0) : tokens.line,
      compact: compact || yours,
    );
  }
}

/// The registration age, with the complete localized timestamp on hover.
class SentinelRegistrationTime extends StatelessWidget {
  /// Creates a value from the API's timestamp in seconds.
  const SentinelRegistrationTime({
    required this.timestamp,
    this.now,
    super.key,
  });

  /// Unix seconds, not milliseconds.
  final int timestamp;

  /// An explicit clock for a deterministic presentation test.
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = AppTokens.of(context);
    // Invalid records do not become a plausible age or overflow DateTime.
    if (timestamp < 0 || timestamp > 8640000000000) {
      return Text(context.l10n.nodesUnavailable, style: tokens.compactText);
    }
    final int millis = timestamp * Duration.millisecondsPerSecond;
    final Locale locale = Localizations.localeOf(context);
    final DateTime registered = DateTime.fromMillisecondsSinceEpoch(millis);
    final Duration age = (now ?? DateTime.now()).difference(registered);
    final String text;
    if (age.isNegative) {
      text = FormatUtils.formatDate(millis, locale: locale);
    } else if (age.inDays >= 365) {
      text = context.l10n.nodesAgoDuration(
        context.l10n.durationYears(age.inDays ~/ 365),
      );
    } else if (age.inDays >= 30) {
      text = context.l10n.nodesAgoDuration(
        context.l10n.durationMonths(age.inDays ~/ 30),
      );
    } else if (age.inSeconds == 0) {
      text = context.l10n.nodesNow;
    } else {
      text = context.l10n.nodesAgoDuration(
        FormatUtils.formatDurationCoarse(context.l10n, age),
      );
    }
    return Tooltip(
      message: FormatUtils.formatDateTimeSeconds(millis, locale: locale),
      child: Ltr(
        child: Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: tokens.dataText.copyWith(color: tokens.dim),
        ),
      ),
    );
  }
}

/// A revocation window from one read, refreshed rather than inferred at zero.
class SentinelRevocationTime extends StatefulWidget {
  /// Creates the value for either a table cell or the strip's clock chip.
  const SentinelRevocationTime({
    required this.sentinel,
    this.onRefresh,
    this.chip = false,
    this.now,
    super.key,
  });

  /// The proven read whose cooldown starts when this record arrives.
  final SentinelInfo sentinel;

  /// Reads the new window after the known one expires.
  final VoidCallback? onRefresh;

  /// Whether the value sits in the strip's clock chip.
  final bool chip;

  /// The clock for an isolated test; ordinary views use the system clock.
  final DateTime Function()? now;

  @override
  State<SentinelRevocationTime> createState() => _SentinelRevocationTimeState();
}

class _SentinelRevocationTimeState extends State<SentinelRevocationTime> {
  static const Duration _refreshInterval = Duration(minutes: 1);
  static const int _maxTimestampSeconds = 8640000000000;

  DateTime? _deadline;
  Timer? _timer;
  bool _visible = true;
  bool _expired = false;
  bool _invalid = false;
  bool _notified = false;

  DateTime _now() => widget.now?.call() ?? DateTime.now();

  @override
  void initState() {
    super.initState();
    _bindRead();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _visible = TickerMode.valuesOf(context).enabled;
    _followClock();
  }

  @override
  void didUpdateWidget(SentinelRevocationTime oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.sentinel, widget.sentinel)) {
      _bindRead();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _bindRead() {
    _timer?.cancel();
    _notified = false;
    final SentinelInfo sentinel = widget.sentinel;
    final int remainingRange =
        _maxTimestampSeconds -
        _now().millisecondsSinceEpoch ~/ Duration.millisecondsPerSecond;
    _invalid =
        sentinel.active &&
        (sentinel.revokeCooldown < 0 ||
            sentinel.revokeCooldown >= remainingRange);
    _expired =
        sentinel.active &&
        !_invalid &&
        !sentinel.isRevocable &&
        sentinel.revokeCooldown <= 0;
    _deadline = sentinel.active && !_invalid && sentinel.revokeCooldown > 0
        ? _now().add(Duration(seconds: sentinel.revokeCooldown))
        : null;
    _followClock();
  }

  void _followClock() {
    _timer?.cancel();
    if (!_visible) return;
    final DateTime? deadline = _deadline;
    if (deadline != null && !deadline.isAfter(_now())) _expired = true;
    if (_expired) {
      if (!_notified) {
        _notified = true;
        WidgetsBinding.instance.addPostFrameCallback((Duration _) {
          if (mounted) widget.onRefresh?.call();
        });
      }
      return;
    }
    if (deadline == null) return;
    final Duration remaining = deadline.difference(_now());
    final Duration next =
        widget.sentinel.isRevocable || remaining < _refreshInterval
        ? remaining
        : _refreshInterval;
    _timer = Timer(next, () {
      if (!mounted) return;
      setState(_followClock);
    });
  }

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = AppTokens.of(context);
    if (_invalid) {
      return Text(context.l10n.nodesUnavailable, style: tokens.compactText);
    }
    if (_expired) {
      return const Skeleton(width: 80);
    }
    final SentinelInfo sentinel = widget.sentinel;
    if (!sentinel.active) {
      return Text(context.l10n.nodesRevoked, style: tokens.compactText);
    }
    final Duration remaining = _deadline?.difference(_now()) ?? Duration.zero;
    final String text = sentinel.isRevocable
        ? context.l10n.nodesNow
        : context.l10n.nodesInDuration(
            FormatUtils.formatDuration(context.l10n, remaining),
          );
    if (!widget.chip) {
      return Ltr(
        child: Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: tokens.dataText.copyWith(color: tokens.dim),
        ),
      );
    }
    return _FactChip(
      label: text,
      icon: sentinel.isRevocable ? Icons.check_rounded : Icons.schedule_rounded,
      ink: sentinel.isRevocable ? tokens.znnInk : tokens.qsrInk,
      fill: (sentinel.isRevocable ? tokens.znn : tokens.qsr).withValues(
        alpha: 0.12,
      ),
      line: tokens.line.withValues(alpha: 0),
      compact: true,
      data: true,
    );
  }
}

class _FactChip extends StatelessWidget {
  const _FactChip({
    required this.label,
    required this.icon,
    required this.ink,
    required this.fill,
    required this.line,
    required this.compact,
    this.data = false,
  });

  final String label;
  final IconData icon;
  final Color ink;
  final Color fill;
  final Color line;
  final bool compact;
  final bool data;

  @override
  Widget build(BuildContext context) {
    final AppTokens tokens = AppTokens.of(context);
    return Container(
      constraints: BoxConstraints(
        minHeight: compact
            ? tokens.pillarOwnedChipHeight
            : tokens.pillarActionHeight,
      ),
      padding: EdgeInsetsDirectional.symmetric(horizontal: tokens.inlineGap),
      decoration: BoxDecoration(
        color: fill,
        border: Border.all(color: line),
        borderRadius: BorderRadius.circular(tokens.pillRadius),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: tokens.settingsIconSize, color: ink),
          SizedBox(width: tokens.fieldLabelGap),
          Text(
            label,
            textDirection: data ? TextDirection.ltr : null,
            style: (data ? tokens.dataText : tokens.captionText).copyWith(
              fontSize: tokens.captionText.fontSize,
              color: ink,
            ),
          ),
        ],
      ),
    );
  }
}
