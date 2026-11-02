import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/blocs/blocs.dart';
import 'package:zenon_syrius_wallet_flutter/main.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/utils.dart';
import 'package:zenon_syrius_wallet_flutter/utils/utils.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

class ReceiveCell extends StatefulWidget {
  const ReceiveCell({required this.hash, this.sourceIsCurrent, super.key});

  final Hash hash;
  final bool Function()? sourceIsCurrent;

  @override
  State<ReceiveCell> createState() => _ReceiveCellState();
}

class _ReceiveCellState extends State<ReceiveCell> with WidgetsBindingObserver {
  AutoReceiveTxWorker? _worker;
  ModalRoute<dynamic>? _route;
  NavigatorState? _navigator;
  int _epoch = 0;
  bool _visible = false;
  bool _resumed = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final AppLifecycleState? state = WidgetsBinding.instance.lifecycleState;
    _resumed = state == null || state == AppLifecycleState.resumed;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final ModalRoute<dynamic>? route = ModalRoute.of(context);
    final NavigatorState? navigator = Navigator.maybeOf(context);
    final bool visible =
        TickerMode.valuesOf(context).enabled && (route?.isCurrent ?? true);
    if (!identical(route, _route) ||
        !identical(navigator, _navigator) ||
        visible != _visible) {
      _epoch++;
    }
    _route = route;
    _navigator = navigator;
    _visible = visible;
  }

  @override
  void didUpdateWidget(ReceiveCell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.hash != widget.hash ||
        !identical(oldWidget.sourceIsCurrent, widget.sourceIsCurrent)) {
      _epoch++;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final bool resumed = state == AppLifecycleState.resumed;
    if (resumed == _resumed) return;
    setState(() {
      _epoch++;
      _resumed = resumed;
    });
  }

  @override
  void dispose() {
    _epoch++;
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AutoReceiveTxWorker worker = sl<AutoReceiveTxWorker>();
    if (!identical(worker, _worker)) {
      _epoch++;
      _worker = worker;
    }
    final int epoch = _epoch;
    final String hash = widget.hash.toString();
    final ModalRoute<dynamic>? route = _route;
    final NavigatorState? navigator = _navigator;
    final bool Function()? sourceIsCurrent = widget.sourceIsCurrent;
    bool current() =>
        mounted &&
        epoch == _epoch &&
        identical(worker, _worker) &&
        hash == widget.hash.toString() &&
        identical(route, _route) &&
        identical(navigator, _navigator) &&
        (route?.isCurrent ?? true) &&
        _visible &&
        _resumed &&
        (sourceIsCurrent?.call() ?? true);
    final ReceiveOrigin? origin = current()
        ? worker.captureOrigin(sourceIsCurrent: current)
        : null;

    Future<void> receive() async {
      if (!current() || origin == null || !origin.isCurrent) return;
      try {
        await worker.autoReceiveTransactionHash(
          Hash.parse(hash),
          origin: origin,
          sourceIsCurrent: current,
        );
      } on Object {
        // The worker retains the original outcome and owns notifications.
      }
    }

    return InfiniteScrollTableCell(
      child: Align(
        alignment: Alignment.centerLeft,
        // Original admitted outcomes remain held when their row returns.
        child: ValueListenableBuilder<Set<Hash>>(
          valueListenable: worker.inFlight,
          builder: (BuildContext context, Set<Hash> inFlight, _) {
            final bool busy = inFlight.contains(Hash.parse(hash));
            return IconButton(
              key: ValueKey<String>('receive_$hash'),
              tooltip: busy ? null : context.l10n.pressToReceive,
              icon: busy
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.call_received_rounded),
              color: AppColors.znnColor,
              onPressed: busy || origin == null || !current()
                  ? null
                  : () => unawaited(receive()),
            );
          },
        ),
      ),
    );
  }
}
