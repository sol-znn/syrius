import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/card_parts/card_parts.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/motion/motion.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/page/page_widgets.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/plasma_meter.dart';
import 'package:zenon_syrius_wallet_flutter/utils/app_theme.dart';
import 'package:zenon_syrius_wallet_flutter/utils/constants.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

/// Plasma one whole QSR gives its beneficiary: the rate the node applies,
/// as `PlasmaApi.getPlasmaByQsr` in the SDK has it.
const int kPlasmaPerQsr = 2100;

/// What an amount of plasma is enough for.
///
/// The steps are the ones the wallet has always drawn: under the network's
/// minimum a block needs proof of work; from [kIssueTokenPlasmaAmountNeeded]
/// a token can be issued; from [kPillarPlasmaAmountNeeded] anything can be
/// sent, a Pillar registration included.
enum PlasmaLevel {
  /// Under the minimum: every block needs proof of work.
  none('None'),

  /// Enough for plain sends.
  low('Low'),

  /// Enough to issue a token.
  medium('Medium'),

  /// Enough for any block.
  high('High');

  const PlasmaLevel(this.label);

  /// The level's name, as shown.
  final String label;

  /// The level [plasma] reaches.
  static PlasmaLevel of(int plasma) {
    if (plasma >= kPillarPlasmaAmountNeeded) return PlasmaLevel.high;
    if (plasma >= kIssueTokenPlasmaAmountNeeded) return PlasmaLevel.medium;
    if (plasma >= minPlasmaAmount.toInt()) return PlasmaLevel.low;
    return PlasmaLevel.none;
  }
}

/// The plasma that fusing [rawQsr] gives, where [rawQsr] is in QSR's
/// smallest unit with [decimals] decimals.
BigInt plasmaForQsrExact(BigInt rawQsr, int decimals) =>
    rawQsr * BigInt.from(kPlasmaPerQsr) ~/ BigInt.from(10).pow(decimals);

/// Refuses an unrepresentable display integer instead of silently saturating.
int plasmaForQsr(BigInt rawQsr, int decimals) {
  final BigInt exact = plasmaForQsrExact(rawQsr, decimals);
  final int value = exact.toInt();
  if (BigInt.from(value) != exact) {
    throw RangeError('Plasma exceeds integer range');
  }
  return value;
}

/// How full a meter is for [plasma]: full at the highest level.
double plasmaMeterValue(int plasma) =>
    (plasma / kPillarPlasmaAmountNeeded).clamp(0, 1).toDouble();

/// A bar that fills with an amount of plasma, and moves to a new amount
/// instead of jumping to it.
class PlasmaLevelMeter extends StatelessWidget {
  /// Creates a meter showing [plasma].
  const PlasmaLevelMeter({
    required this.plasma,
    this.generating = false,
    super.key,
  });

  /// The plasma to show.
  final int plasma;

  /// Only genuine owned proof-of-work makes the meter's light flow.
  final bool generating;

  @override
  Widget build(BuildContext context) {
    // The fill is QSR's brand blue, the same in both themes; [PlasmaMeter]
    // moves to a new level and runs the light through it.
    return PlasmaMeter(
      value: plasmaMeterValue(plasma),
      active: generating,
      trackColor: cardLineColor(context),
    );
  }
}

/// The name of the level an amount of plasma reaches, as a ledger label
/// that flashes once when the level changes.
class PlasmaLevelLabel extends StatelessWidget {
  /// Creates the label for [plasma]; empty while [plasma] is null.
  const PlasmaLevelLabel({required this.plasma, super.key});

  /// The plasma, or null while it is not known.
  final int? plasma;

  @override
  Widget build(BuildContext context) {
    final int? plasma = this.plasma;
    final String label = plasma == null ? '' : PlasmaLevel.of(plasma).label;
    return ValueFlash(
      // A flash per load state: the first value read is not a change.
      key: ValueKey<bool>(plasma == null),
      value: label,
      color: AppTokens.of(context).qsrInk,
      child: Text(label.toUpperCase(), style: ledgerLabelStyle(context)),
    );
  }
}
