import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/main.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/home/widgets/amount_text.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/extensions/buildcontext_extension.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/ltr.dart';
import 'package:zenon_syrius_wallet_flutter/utils/app_theme.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/shell/strip/status_dot.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

/// A block the wallet published that no momentum has taken in yet.
@immutable
class InFlightBlock {
  /// Creates the record of a published send.
  const InFlightBlock({
    required this.hash,
    required this.amount,
    this.decimals,
    this.symbol,
  });

  /// The published block's hash.
  final Hash hash;

  /// What it sends, in the token's smallest unit.
  final BigInt amount;

  /// The token's known decimals, absent when metadata is unavailable.
  final int? decimals;

  /// The token's known symbol, absent when metadata is unavailable.
  final String? symbol;
}

/// Asks the node whether a momentum has taken the block in.
typedef ConfirmationLookup = Future<bool> Function(Hash hash);

Future<bool> _askNode(Hash hash) async {
  final AccountBlock? block = await zenon!.ledger.getAccountBlockByHash(hash);
  return block?.hash == hash && block?.confirmationDetail != null;
}

/// The sends that are waiting for their momentum, for the strip's chip.
///
/// Nothing in the wallet followed a block after it was published: the send
/// flow reported "published" and stopped, and the page showed a fixed wait.
/// This is the one place that knows, with two calls for whoever publishes:
///
///  * [sent], with the block the node accepted;
///  * [settle], only by a caller that learns of the confirmation itself.
///
/// A caller that does not is covered by [check], which the strip runs at
/// each new momentum and which asks the node about every block held here.
class InFlightBlocks extends ChangeNotifier
    implements ValueListenable<List<InFlightBlock>> {
  /// Creates an empty set. [lookup] is the node's ledger when null.
  InFlightBlocks({ConfirmationLookup? lookup}) : _lookup = lookup ?? _askNode;

  /// The wallet's own, shown by the strip unless it is given another.
  static final InFlightBlocks wallet = InFlightBlocks();

  final ConfirmationLookup _lookup;
  List<InFlightBlock> _blocks = const <InFlightBlock>[];
  final Set<Hash> _confirmed = <Hash>{};
  int _epoch = 0;
  int? _checkingEpoch;
  bool _disposed = false;

  /// The blocks in flight, oldest first.
  @override
  List<InFlightBlock> get value => _blocks;

  /// Positive exact-hash evidence, separate from absence in the pending list.
  bool hasConfirmed(Hash hash) => !_disposed && _confirmed.contains(hash);

  /// Revokes node-context evidence while retaining every unresolved hash.
  void invalidateEvidence() {
    if (_disposed) return;
    _epoch++;
    _checkingEpoch = null;
    _confirmed.clear();
    notifyListeners();
  }

  /// Records a send the node has accepted. Call it with the published
  /// block's hash, as soon as the send returns.
  void sent({
    required Hash hash,
    required BigInt amount,
    int? decimals,
    String? symbol,
  }) {
    if (_disposed || _blocks.any((InFlightBlock block) => block.hash == hash)) {
      return;
    }
    _blocks = List<InFlightBlock>.unmodifiable(<InFlightBlock>[
      ..._blocks,
      InFlightBlock(
        hash: hash,
        amount: amount,
        decimals: decimals,
        symbol: symbol,
      ),
    ]);
    notifyListeners();
  }

  /// Takes [hash] out only when the caller has learned its exact confirmation.
  void settle(Hash hash) {
    if (_disposed) return;
    final List<InFlightBlock> rest = <InFlightBlock>[
      for (final InFlightBlock block in _blocks)
        if (block.hash != hash) block,
    ];
    if (rest.length != _blocks.length) {
      _confirmed.add(hash);
      _blocks = List<InFlightBlock>.unmodifiable(rest);
      notifyListeners();
    }
  }

  /// Starts a different tracking session or node epoch. Lock alone is not
  /// settlement: the shell hides the chip while retaining unresolved hashes.
  void clear() {
    if (_disposed) return;
    _epoch++;
    _confirmed.clear();
    if (_blocks.isNotEmpty) {
      _blocks = const <InFlightBlock>[];
      notifyListeners();
    }
  }

  /// Asks about each block held and settles the confirmed ones.
  ///
  /// A node that does not answer leaves the block where it is: "waiting" is
  /// still the truth as far as the wallet can tell.
  Future<void> check() async {
    if (_disposed || _checkingEpoch == _epoch || _blocks.isEmpty) {
      return;
    }
    final int epoch = _epoch;
    _checkingEpoch = epoch;
    try {
      for (final InFlightBlock block in _blocks.toList()) {
        if (_disposed || epoch != _epoch) break;
        try {
          final bool confirmed = await _lookup(block.hash);
          // The same hash may have been registered in a different node epoch
          // while this request was outstanding. Its answer cannot settle it.
          if (_disposed || epoch != _epoch) break;
          if (confirmed) {
            settle(block.hash);
          }
        } on Object {
          continue;
        }
      }
    } finally {
      if (_checkingEpoch == epoch) _checkingEpoch = null;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _epoch++;
    _checkingEpoch = null;
    super.dispose();
  }
}

/// Says what is being sent while it waits for a momentum; nothing when no
/// block is in flight.
class FlightChip extends StatelessWidget {
  /// Creates the chip over [blocks].
  const FlightChip({required this.blocks, super.key});

  /// The sends in flight.
  final ValueListenable<List<InFlightBlock>> blocks;

  /// Stands in the translated sentence where the amount goes, so the
  /// amount can be drawn left to right wherever the language puts it.
  static const String _slot = '\u{FFFC}';

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<InFlightBlock>>(
      valueListenable: blocks,
      builder: (BuildContext context, List<InFlightBlock> blocks, _) {
        if (blocks.isEmpty) {
          return const SizedBox.shrink();
        }
        final AppTokens tokens = AppTokens.of(context);
        final TextStyle dim = Theme.of(
          context,
        ).textTheme.titleMedium!.copyWith(fontSize: 13, color: tokens.dim);
        final List<InlineSpan> what;
        bool generic = false;
        if (blocks.length == 1) {
          final InFlightBlock block = blocks.single;
          final int? decimals = block.decimals;
          final String? symbol = block.symbol;
          // Malformed metadata must not allocate an unbounded power of ten.
          // Unknown units and zero-amount contract calls still keep their hash.
          if (block.amount <= BigInt.zero ||
              decimals == null ||
              decimals < 0 ||
              decimals > 255 ||
              symbol == null ||
              symbol.trim().isEmpty) {
            generic = true;
            what = <InlineSpan>[
              TextSpan(text: context.l10n.stripWaitingConfirmation),
            ];
          } else {
            final (String digits, _) = splitAmount(block.amount, decimals);
            final List<String> around = context.l10n
                .stripSending(_slot)
                .split(_slot);
            what = <InlineSpan>[
              TextSpan(text: around.first),
              WidgetSpan(
                alignment: PlaceholderAlignment.baseline,
                baseline: TextBaseline.alphabetic,
                child: Ltr(
                  child: Text(
                    '$digits $symbol',
                    style: monoStyle(dim),
                  ),
                ),
              ),
              if (around.length > 1) TextSpan(text: around.last),
            ];
          }
        } else {
          what = <InlineSpan>[
            TextSpan(text: context.l10n.stripSendingMany(blocks.length)),
          ];
        }
        return Row(
          key: const Key('strip_flight'),
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            StatusDot(color: tokens.qsr),
            SizedBox(width: tokens.statusDotSize),
            Flexible(
              child: Text.rich(
                TextSpan(
                  style: dim,
                  children: <InlineSpan>[
                    ...what,
                    if (!generic)
                      TextSpan(
                        text: ' · ${context.l10n.stripWaitingMomentum}',
                        style: TextStyle(color: tokens.faint),
                      ),
                  ],
                ),
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        );
      },
    );
  }
}
