import 'dart:async';
import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:window_manager/window_manager.dart';
import 'package:zenon_syrius_wallet_flutter/seams/seam.dart';
import 'package:zenon_syrius_wallet_flutter/utils/app_theme.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

// Shared measures traced from 00-head.html and the Home motion table.
const int _sparkCount = AppTokens.zapSparkCount;
const Duration _sparkDuration = AppTokens.zapSparkDuration;
const double _sparkDiameter = AppTokens.zapSparkDiameter;
const double _sparkMinDistance = AppTokens.zapSparkMinDistance;
const double _sparkMaxDistance = AppTokens.zapSparkMaxDistance;
const double _sparkEndScale = AppTokens.zapSparkEndScale;

Hash _freezeReceiveHash(Hash hash) {
  final Hash frozen = Hash.fromBytes(List<int>.unmodifiable(hash.hash));
  if (frozen == emptyHash) {
    throw ArgumentError('A nonempty receive hash is required');
  }
  return frozen;
}

/// Stable ownership of a receipt, independent of node or unlock session.
///
/// The future receive backend must supply a durable wallet identity. A label,
/// selected address or temporary session id cannot stand in for that identity.
@immutable
class ZapReceiveOwner {
  /// Captures the backend's canonical wallet, chain and recipient identities.
  const ZapReceiveOwner({
    required this.walletId,
    required this.chainId,
    required this.recipient,
  });

  /// An opaque, stable wallet identity, never secret wallet material.
  final String walletId;

  /// The chain on which the incoming receipt was confirmed.
  final int chainId;

  /// The canonical recipient address within that wallet.
  final String recipient;

  @override
  bool operator ==(Object other) =>
      other is ZapReceiveOwner &&
      other.walletId == walletId &&
      other.chainId == chainId &&
      other.recipient == recipient;

  @override
  int get hashCode => Object.hash(walletId, chainId, recipient);
}

/// One exact, revocable receive context.
///
/// Construct a new instance after lock, wallet, address, chain or node changes.
/// Deliveries must retain this same instance and pass the live context guard.
@immutable
class ZapReceiveScope {
  /// Captures the durable owner and the node used to qualify the receipt.
  const ZapReceiveScope({required this.owner, required this.nodeId});

  /// The durable namespace used for initial history and receipt claims.
  final ZapReceiveOwner owner;

  /// The exact node context, excluded from the durable once-per-hash key.
  final String nodeId;
}

/// The exact incoming receive hash under its durable owner.
@immutable
class ZapReceiveIdentity {
  /// Captures a qualified receive block, not its paired send block.
  ZapReceiveIdentity({required this.owner, required Hash receiveHash})
    : receiveHash = _freezeReceiveHash(receiveHash);

  /// The receipt's stable wallet, chain and recipient namespace.
  final ZapReceiveOwner owner;

  /// The canonical confirmed receive hash supplied by the receive backend.
  final Hash receiveHash;

  @override
  bool operator ==(Object other) =>
      other is ZapReceiveIdentity &&
      other.owner == owner &&
      other.receiveHash == receiveHash;

  @override
  int get hashCode => Object.hash(owner, receiveHash);
}

/// The missing durable admission boundary for qualified Zap receipts.
///
/// No implementation is supplied by the current receive service. A future
/// implementation must serialize all writers for an owner, commit before
/// resolving, preserve claims across restarts and refuse uncertain writes.
/// An in-memory set or a read followed by an unlocked Hive put is insufficient.
abstract interface class ZapReceiveClaims {
  /// Durably records a complete first history snapshot without celebrating it.
  ///
  /// Preserve existing claims and make retries idempotent. Failure must leave
  /// admission unavailable until a complete baseline has been committed.
  Future<void> prime(ZapReceiveOwner owner, Set<Hash> receiveHashes);

  /// Atomically and durably claims [identity], returning true to one caller.
  ///
  /// False means already claimed. Never release a claim after hidden playback,
  /// disposal or an uncertain result. Node and session changes cannot rearm it.
  Future<bool> claim(ZapReceiveIdentity identity);
}

/// Admits explicit, qualified receive signals before starting decorative paint.
///
/// The default controller is dormant behind [Seam.zapReceive]. Its direct
/// receive and history calls throw too; mounting a widget never admits history.
class ZapSparksController extends ChangeNotifier {
  /// Creates the refusing boundary used by Home while Zap receive is missing.
  ZapSparksController() : _scope = null, _claims = null, _isCurrent = null;

  /// Binds a future qualified backend to its exact owner and durable store.
  ///
  /// Call [primeHistory] with the initial confirmed snapshot before [receive].
  /// The guard must check lock and every captured wallet/node/chain/address
  /// context. Call [invalidate] as soon as that context is revoked, even if
  /// the same address will subsequently be unlocked again.
  ZapSparksController.qualified({
    required ZapReceiveScope scope,
    required ZapReceiveClaims this._claims,
    required bool Function() this._isCurrent,
  }) : _scope = scope {
    if (scope.owner.walletId.isEmpty ||
        scope.owner.recipient.isEmpty ||
        scope.nodeId.isEmpty) {
      throw ArgumentError('A complete receive owner and node are required');
    }
  }

  final ZapReceiveScope? _scope;
  final ZapReceiveClaims? _claims;
  final bool Function()? _isCurrent;
  Future<void> _tail = Future<void>.value();
  Completer<void>? _activeRelease;
  Object? _surface;
  bool Function()? _canPresent;
  bool _priming = false;
  bool _ready = false;
  bool _revoked = false;
  bool _disposed = false;
  int _epoch = 0;
  int _nextBurst = 0;
  int? _burst;

  /// The current service boundary. Only a qualified future binding removes it.
  Seam? get seam => _claims == null ? Seam.zapReceive : null;

  bool _current(ZapReceiveScope scope) {
    if (_disposed || _revoked || !identical(scope, _scope)) return false;
    bool current = false;
    try {
      current = _isCurrent?.call() ?? false;
    } on Object {
      // A broken guard cannot authorize an old context after it recovers.
    }
    if (!current) invalidate();
    return current;
  }

  bool _available(ZapReceiveScope scope, int epoch) =>
      epoch == _epoch &&
      _current(scope) &&
      _ready &&
      _surface != null &&
      (_canPresent?.call() ?? false);

  /// Silently seeds initial history without creating an amount, row or event.
  Future<bool> primeHistory({
    required ZapReceiveScope scope,
    required Iterable<Hash> receiveHashes,
  }) async {
    final ZapReceiveClaims claims =
        _claims ?? (throw const SeamNotBuilt(Seam.zapReceive));
    if (!_current(scope) || _priming) return false;
    if (_ready) return true;
    final int epoch = _epoch;
    final Set<Hash> snapshot = Set<Hash>.unmodifiable(
      receiveHashes.map(_freezeReceiveHash),
    );
    _priming = true;
    try {
      await claims.prime(scope.owner, snapshot);
      if (!_current(scope) || epoch != _epoch) return false;
      _ready = true;
      return true;
    } finally {
      _priming = false;
    }
  }

  /// Starts once after a confirmed, incoming, strictly decoded Zap signal.
  ///
  /// The backend supplies the exact receive hash; this method does not infer a
  /// receipt from activity, balance changes, a send hash or a message preview.
  /// Each queued delivery rechecks its scope after waiting and after the
  /// durable claim. The result reports whether paint actually began.
  Future<bool> receive({
    required ZapReceiveScope scope,
    required Hash receiveHash,
  }) async {
    final ZapReceiveClaims claims =
        _claims ?? (throw const SeamNotBuilt(Seam.zapReceive));
    final int epoch = _epoch;
    if (!_available(scope, epoch)) return false;
    // SDK hashes expose mutable bytes. Capture the exact delivery before
    // waiting for either the previous animation or the durable claim.
    final ZapReceiveIdentity identity = ZapReceiveIdentity(
      owner: scope.owner,
      receiveHash: receiveHash,
    );
    final Future<void> previous = _tail;
    final Completer<void> release = Completer<void>();
    _tail = release.future;
    bool playing = false;
    try {
      await previous;
      if (!_available(scope, epoch)) return false;
      final bool admitted = await claims.claim(identity);
      if (!admitted || !_available(scope, epoch)) return false;
      _activeRelease = release;
      playing = true;
      final int burst = ++_nextBurst;
      _burst = burst;
      notifyListeners();
      return _burst == burst;
    } finally {
      if (!playing) release.complete();
    }
  }

  /// Permanently retires this captured context before lock or context changes.
  void invalidate() {
    if (_disposed || _revoked) return;
    _revoked = true;
    _cancelPending();
  }

  void _attach(Object surface, bool Function() canPresent) {
    if (_disposed) throw StateError('A disposed Zap controller cannot attach');
    if (_surface != null && !identical(surface, _surface)) {
      throw StateError('A Zap controller can own only one surface');
    }
    _surface = surface;
    _canPresent = canPresent;
  }

  void _detach(Object surface) {
    if (!identical(surface, _surface)) return;
    _surface = null;
    _canPresent = null;
    _cancelPending();
  }

  void _finish(int? burst) {
    if (burst == null || _burst != burst) return;
    _burst = null;
    final Completer<void>? release = _activeRelease;
    _activeRelease = null;
    release?.complete();
    if (!_disposed) notifyListeners();
  }

  void _cancelPending() {
    _epoch += 1;
    _finish(_burst);
  }

  @override
  void dispose() {
    if (_disposed) return;
    _revoked = true;
    _cancelPending();
    _disposed = true;
    _surface = null;
    _canPresent = null;
    super.dispose();
  }
}

/// A pointer-free, semantics-free receive overlay that never autoplays.
///
/// Home can mount `const ZapSparks()` without owning another lifecycle. Only
/// an explicitly injected qualified controller can request future playback.
class ZapSparks extends StatefulWidget {
  /// Creates an idle seamed surface unless [controller] is supplied.
  const ZapSparks({this.controller, this.visible = true, super.key});

  /// The session owner. Omitted controllers are created and disposed here.
  final ZapSparksController? controller;

  /// An explicit page visibility guard in addition to route and window state.
  final bool visible;

  @override
  State<ZapSparks> createState() => _ZapSparksState();
}

class _ZapSparksState extends State<ZapSparks>
    with
        SingleTickerProviderStateMixin,
        WidgetsBindingObserver,
        WindowListener {
  late final AnimationController _animation;
  late ZapSparksController _controller;
  final Object _surface = Object();
  AppLifecycleState? _lifecycle;
  bool _ownsController = false;
  bool _visible = false;
  bool _focused = false;
  bool _presentable = false;
  int _focusRevision = 0;

  @override
  void initState() {
    super.initState();
    _animation =
        AnimationController(
            vsync: this,
            duration: _sparkDuration,
            value: 1,
            // Visible effects run regardless of OS animation flags.
            animationBehavior: AnimationBehavior.preserve,
          )
          ..addListener(_guardFrame)
          ..addStatusListener(_onAnimationStatus);
    _lifecycle = WidgetsBinding.instance.lifecycleState;
    WidgetsBinding.instance.addObserver(this);
    windowManager.addListener(this);
    _bindController();
  }

  void _bindController() {
    _ownsController = widget.controller == null;
    _controller = widget.controller ?? ZapSparksController();
    _controller
      .._attach(_surface, _canPresent)
      ..addListener(_onControllerChanged);
    if (_controller.seam == null) unawaited(_readWindowFocus());
  }

  void _unbindController() {
    _controller
      ..removeListener(_onControllerChanged)
      .._detach(_surface);
    if (_ownsController) _controller.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _visible =
        TickerMode.valuesOf(context).enabled &&
        (ModalRoute.of(context)?.isCurrent ?? true);
    _syncVisibility();
  }

  @override
  void didUpdateWidget(ZapSparks oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      _focusRevision += 1;
      _focused = false;
      _animation
        ..stop()
        ..value = 1;
      _unbindController();
      _bindController();
    }
    _syncVisibility();
  }

  bool _canPresent() =>
      mounted &&
      widget.visible &&
      _visible &&
      _focused &&
      (_lifecycle == null || _lifecycle == AppLifecycleState.resumed);

  void _syncVisibility() {
    final bool presentable = _canPresent();
    if (_presentable && !presentable) _controller._cancelPending();
    _presentable = presentable;
  }

  void _onControllerChanged() {
    if (_controller._burst == null) {
      _animation
        ..stop()
        ..value = 1;
    } else if (_canPresent()) {
      _animation.forward(from: 0);
    } else {
      _controller._cancelPending();
    }
  }

  void _guardFrame() {
    final ZapReceiveScope? scope = _controller._scope;
    if (_controller._burst == null) return;
    if (scope == null || !_controller._current(scope) || !_canPresent()) {
      _controller._cancelPending();
    } else if (_animation.value >= 1) {
      // The interpolation reports its final value before its done status.
      // Release the exact 900 ms paint boundary without another clock tick.
      _controller._finish(_controller._burst);
    }
  }

  void _onAnimationStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) {
      _controller._finish(_controller._burst);
    }
  }

  Future<void> _readWindowFocus() async {
    final int revision = ++_focusRevision;
    try {
      final bool focused = await windowManager.isFocused();
      if (!mounted || revision != _focusRevision) return;
      _focused = focused;
      _syncVisibility();
    } on Object {
      // A missing focus answer cannot authorize playback on a hidden window.
    }
  }

  @override
  void onWindowBlur() {
    _focusRevision += 1;
    _focused = false;
    _syncVisibility();
  }

  @override
  void onWindowFocus() {
    _focusRevision += 1;
    _focused = true;
    _syncVisibility();
  }

  @override
  void onWindowMinimize() => onWindowBlur();

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lifecycle = state;
    _focusRevision += 1;
    _syncVisibility();
    if (state == AppLifecycleState.resumed && _controller.seam == null) {
      _focused = false;
      _syncVisibility();
      unawaited(_readWindowFocus());
    }
  }

  @override
  void dispose() {
    _focusRevision += 1;
    windowManager.removeListener(this);
    WidgetsBinding.instance.removeObserver(this);
    _unbindController();
    _animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Widget paint = RepaintBoundary(
      child: AnimatedBuilder(
        animation: _animation,
        builder: (BuildContext context, Widget? child) => CustomPaint(
          key: const Key('home_zap_sparks_paint'),
          painter: ZapSparksPainter(
            progress: _animation.value,
            tokens: AppTokens.of(context),
          ),
          child: const SizedBox.expand(),
        ),
      ),
    );
    final Seam? seam = _controller.seam;
    if (seam != null) paint = SeamGate(seam: seam, child: paint);
    return IgnorePointer(
      key: const Key('home_zap_sparks'),
      child: ExcludeSemantics(child: paint),
    );
  }
}

/// The measured burst paint, also usable for deterministic isolated previews.
class ZapSparksPainter extends CustomPainter {
  /// Takes linear elapsed progress; the reference ease is applied once here.
  ZapSparksPainter({required this.progress, required this.tokens});

  /// Elapsed fraction of the complete 900 ms effect, from zero to one.
  final double progress;

  /// Theme-owned colours and the reference `(.4,0,.2,1)` ease.
  final AppTokens tokens;

  /// Fixed radial destinations, in logical pixels from the shared origin.
  ///
  /// The reference chooses random angles and distances. Equal angle coverage
  /// and a coprime radius permutation keep its measured bounds reproducible
  /// without reading receipt identity or using runtime randomness.
  static final List<Offset> destinations = List<Offset>.unmodifiable(
    List<Offset>.generate(_sparkCount, (int index) {
      final double angle = 2 * math.pi * index / _sparkCount;
      final double distance =
          _sparkMinDistance +
          (_sparkMaxDistance - _sparkMinDistance) *
              ((index * 11) % _sparkCount) /
              (_sparkCount - 1);
      return Offset(math.cos(angle) * distance, math.sin(angle) * distance);
    }),
  );

  @override
  void paint(Canvas canvas, Size size) {
    if (progress >= 1 || size.isEmpty) return;
    final double eased = tokens.ease.transform(
      progress.clamp(0.0, 1.0),
    );
    final double radius =
        _sparkDiameter / 2 * (1 + (_sparkEndScale - 1) * eased);
    // The CSS origin is the window centre and the 6px boxes begin there;
    // their transform origin is the centre of each box, three pixels onward.
    final Offset origin = size.center(
      const Offset(_sparkDiameter / 2, _sparkDiameter / 2),
    );
    final List<Color> palette = <Color>[tokens.qsrInk, tokens.pink, tokens.znn];
    for (int index = 0; index < destinations.length; index++) {
      final Color color = palette[index % palette.length];
      canvas.drawCircle(
        origin + destinations[index] * eased,
        radius,
        Paint()..color = color.withValues(alpha: color.a * (1 - eased)),
      );
    }
  }

  @override
  bool shouldRepaint(ZapSparksPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.tokens != tokens;
}
