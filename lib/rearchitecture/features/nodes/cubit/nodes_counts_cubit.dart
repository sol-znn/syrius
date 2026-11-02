import 'package:bloc/bloc.dart';

/// Reported network totals. A missing value includes a failed read.
typedef NodesCounts = ({int? pillars, int? sentinels});

/// Reads each reported total once, through the original context's transport.
///
/// The owner supplies bounded count requests and a context predicate. There is
/// no persisted state or polling: a refresh discards both previous totals.
class NodesCountsCubit extends Cubit<NodesCounts> {
  /// Creates an idle reader. Call [refresh] to request current totals.
  NodesCountsCubit({
    required this._loadPillars,
    required this._loadSentinels,
    required this._isCurrent,
  }) : super((pillars: null, sentinels: null));

  final Future<int> Function() _loadPillars;
  final Future<int> Function() _loadSentinels;
  final bool Function() _isCurrent;
  Object? _request;
  bool _revoked = false;
  bool _closing = false;

  /// Starts two independent reads and supersedes every earlier reply.
  Future<void> refresh() async {
    if (!_ownsContext()) return;
    final Object request = Object();
    _request = request;
    emit((pillars: null, sentinels: null));
    await Future.wait<void>(<Future<void>>[
      _load(request, _loadPillars, pillars: true),
      _load(request, _loadSentinels, pillars: false),
    ]);
  }

  bool _ownsContext() {
    if (_closing || isClosed || _revoked) return false;
    bool current;
    try {
      current = _isCurrent();
    } on Object {
      current = false;
    }
    if (_closing || isClosed) return false;
    if (!current) {
      // Observing a changed context is permanent for this reader, even if the
      // owner's selection later returns to the same visible values.
      _revoked = true;
      _request = null;
      emit((pillars: null, sentinels: null));
    }
    return current;
  }

  bool _accepts(Object request) =>
      identical(request, _request) &&
      _ownsContext() &&
      identical(request, _request);

  Future<void> _load(
    Object request,
    Future<int> Function() loader, {
    required bool pillars,
  }) async {
    if (!_accepts(request)) return;
    int? count;
    try {
      final int reported = await loader();
      if (reported >= 0) count = reported;
    } on Object {
      // An unavailable total stays unknown. The other source can still answer.
    }
    if (!_accepts(request)) return;
    emit((
      pillars: pillars ? count : state.pillars,
      sentinels: pillars ? state.sentinels : count,
    ));
  }

  @override
  Future<void> close() {
    _closing = true;
    _request = null;
    return super.close();
  }
}
