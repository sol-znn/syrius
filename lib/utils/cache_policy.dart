import 'package:zenon_syrius_wallet_flutter/utils/constants.dart';

/// Only reproducible network state is disposable during ordinary maintenance.
///
/// Derived address membership, labels, favorites, contacts, settings, custom
/// nodes, notifications and swap recovery data are user state, not a cache.
/// The existing explicit reset list remains a separate policy.
const List<String> kOrdinaryCacheBoxesToBeDeleted = <String>[
  kAcceleratorProjectsBox,
  kLastCheckedHtlcBlockBox,
];
