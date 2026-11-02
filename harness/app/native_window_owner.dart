import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

/// Private harness transport. No native handle is returned by this protocol.
const String nativeWindowOwnerChannel =
    'network.zenon.syrius/harness/native_window_owner';

/// A finite refusal that is safe to put in an anonymous harness summary.
final class NativeWindowRefused implements Exception {
  /// Keeps platform diagnostics in the original call instead of public text.
  const NativeWindowRefused(this.code);

  /// The proof that could not be admitted.
  final String code;

  @override
  String toString() => 'NativeWindowRefused($code)';
}

/// Proof from the original runner's first-show engine callback.
/// This is neither a wallet-initialization receipt nor a frozen image lease.
final class NativeWindowStartupReceipt {
  const NativeWindowStartupReceipt._({
    required this.processId,
    required this.processInstance,
    required this.owner,
  });

  /// OS process identity, checked against this Dart process by the adapter.
  final int processId;

  /// The OS process creation identity, without an executable or profile path.
  final String processInstance;

  /// One opaque original parent, child, view, engine and controller generation.
  final String owner;

  /// Only the existing runner's first-show callback establishes this proof.
  int get firstFrameCallback => 1;

  /// An observed native callback count, never a decoded image frame index.
  int get callbackSerial => 1;
}

/// A later completed native frame on the identical original controller.
final class NativeWindowFrameReceipt {
  const NativeWindowFrameReceipt._({
    required this.startup,
    required this.request,
    required this.callbackSerial,
  });

  /// The identical positively admitted startup receipt.
  final NativeWindowStartupReceipt startup;

  /// The original method request, reserved before dispatch.
  final int request;

  /// Counts observed callbacks; animations can draw other intervening frames.
  final int callbackSerial;
}

/// Retains one actual platform Future independently of caller or route life.
final class NativeWindowCall<T> {
  NativeWindowCall._(this.request);

  /// Zero means startup; positive values identify admitted frame requests.
  final int request;
  final Completer<void> _settled = Completer<void>();
  Future<Object?>? _original;
  Object? _value;
  Object? _error;
  StackTrace? _trace;
  Object? _failure;
  StackTrace? _failureTrace;
  T? _receipt;

  /// The identical MethodChannel Future. A local refusal has no native Future.
  Future<Object?>? get original => _original;

  /// Settles only after the original reports an outcome, including late ones.
  Future<void> get settled => _settled.future;

  /// A pending original is never replaced by a deadline or local revocation.
  bool get isSettled => _settled.isCompleted;

  /// The unchanged successful MethodChannel value, even after a local hold.
  Object? get value => _value;

  /// The exact original platform failure, including its private diagnostics.
  /// Public summaries should use [NativeWindowOwner.heldUnknown] instead.
  Object? get error => _error;

  /// The trace actually delivered with [error].
  StackTrace? get stackTrace => _trace;

  /// A validated successful receipt can be retained after a later revocation.
  /// Its presence alone does not clear the owner's monotonic hold.
  T? get receipt => _receipt;

  /// The protocol refusal or unchanged platform failure for this call.
  Object? get failure => _failure;

  /// Lazy creation keeps an unobserved startup failure safely journaled.
  late final Future<T> completion = _settled.future.then<T>((_) {
    final Object? failure = _failure;
    if (failure != null) {
      Error.throwWithStackTrace(failure, _failureTrace!);
    }
    return _receipt as T;
  });

  void _refuse(Object failure, [StackTrace? trace]) {
    _failure ??= failure;
    _failureTrace ??= trace ?? StackTrace.current;
  }

  void _start({
    required Future<Object?> Function() invoke,
    required void Function(Object?) accept,
    required void Function() hold,
  }) {
    try {
      final Future<Object?> original = invoke();
      _original = original;
      unawaited(
        original.then<void>(
          (Object? value) {
            _value = value;
            try {
              accept(value);
            } on Object catch (error, trace) {
              _refuse(error, trace);
              hold();
            } finally {
              _settled.complete();
            }
          },
          onError: (Object error, StackTrace trace) {
            _error = error;
            _trace = trace;
            _refuse(error, trace);
            hold();
            _settled.complete();
          },
        ),
      );
    } on Object catch (error, trace) {
      _error = error;
      _trace = trace;
      _refuse(error, trace);
      hold();
      _settled.complete();
    }
  }
}

/// One retained scope per messenger and channel, shared by every construction.
/// The native process also refuses another startup after a Dart hot restart.
final class NativeWindowOwner {
  /// A supplied channel supports isolated mock-channel tests without a host.
  /// Replacing a channel object with the same messenger/name retains this scope.
  factory NativeWindowOwner({MethodChannel? channel}) {
    final MethodChannel selected =
        channel ?? const MethodChannel(nativeWindowOwnerChannel);
    final BinaryMessenger messenger = selected.binaryMessenger;
    final Map<String, NativeWindowOwner> scopes = _scopes[messenger] ??=
        <String, NativeWindowOwner>{};
    return scopes.putIfAbsent(
      selected.name,
      () => NativeWindowOwner._(selected),
    );
  }

  NativeWindowOwner._(this._channel);

  /// The original process scope. Construction requires an initialized binding.
  factory NativeWindowOwner.process() => NativeWindowOwner();

  static final Expando<Map<String, NativeWindowOwner>> _scopes =
      Expando<Map<String, NativeWindowOwner>>();

  /// Retained evidence is bounded, independently of capture catalog size.
  static const int maxFrameRequests = 128;

  final MethodChannel _channel;
  final List<NativeWindowCall<NativeWindowFrameReceipt>> _frames =
      <NativeWindowCall<NativeWindowFrameReceipt>>[];
  NativeWindowCall<NativeWindowStartupReceipt>? _startup;
  NativeWindowCall<NativeWindowFrameReceipt>? _pendingFrame;
  bool _held = false;
  int _lastCallbackSerial = 1;

  /// Malformed, foreign or failed platform replies permanently hold this scope.
  bool get heldUnknown => _held;

  /// Every admitted original frame call, including pending and failed outcomes.
  List<NativeWindowCall<NativeWindowFrameReceipt>> get frames =>
      List<NativeWindowCall<NativeWindowFrameReceipt>>.unmodifiable(_frames);

  /// Reserves before invoking the platform, so synchronous reentry reuses it.
  /// Starting before runApp is allowed; await only after a real frame can draw.
  NativeWindowCall<NativeWindowStartupReceipt> startup() {
    final NativeWindowCall<NativeWindowStartupReceipt>? original = _startup;
    if (original != null) {
      return original;
    }
    final NativeWindowCall<NativeWindowStartupReceipt> call =
        NativeWindowCall<NativeWindowStartupReceipt>._(0);
    _startup = call;
    if (_held) {
      return _refused(call, 'native-owner-held');
    }
    call._start(
      invoke: () => _channel.invokeMethod<Object?>(
        'startup',
        <String, Object>{'protocol': 1},
      ),
      accept: (Object? value) {
        final Map<Object?, Object?> receipt = _receiptMap(value, 'startup', 0);
        if (receipt['callbackSerial'] != 1) {
          throw const NativeWindowRefused('native-first-frame-unproven');
        }
        call._receipt = NativeWindowStartupReceipt._(
          processId: receipt['processId']! as int,
          processInstance: receipt['processInstance']! as String,
          owner: receipt['owner']! as String,
        );
        if (_held) {
          call._refuse(const NativeWindowRefused('native-owner-held'));
        }
      },
      hold: revoke,
    );
    return call;
  }

  /// Whether this exact retained first-frame proof remains locally admitted.
  /// A fresh [requestFrame] must also complete to verify the native owner now.
  bool isCurrent(NativeWindowStartupReceipt original) =>
      !_held &&
      identical(_startup?.receipt, original) &&
      original.processId == pid &&
      original.firstFrameCallback == 1;

  /// Keeps one pending native frame request and its original Future.
  /// Busy or unproved startup refusals dispatch nothing and do not retry.
  NativeWindowCall<NativeWindowFrameReceipt> requestFrame() {
    final NativeWindowCall<NativeWindowFrameReceipt> call =
        NativeWindowCall<NativeWindowFrameReceipt>._(_frames.length + 1);
    final NativeWindowStartupReceipt? original = _startup?.receipt;
    if (_held) {
      return _refused(call, 'native-owner-held');
    }
    if (_startup?.isSettled != true || original == null) {
      return _refused(call, 'native-startup-unproven');
    }
    if (_pendingFrame != null) {
      return _refused(call, 'native-frame-busy');
    }
    if (_frames.length >= maxFrameRequests) {
      return _refused(call, 'native-frame-limit');
    }
    _pendingFrame = call;
    _frames.add(call);
    call._start(
      invoke: () => _channel.invokeMethod<Object?>(
        'frame',
        <String, Object>{
          'protocol': 1,
          'owner': original.owner,
          'request': call.request,
        },
      ),
      accept: (Object? value) {
        final Map<Object?, Object?> receipt = _receiptMap(
          value,
          'frame',
          call.request,
        );
        if (receipt['owner'] != original.owner ||
            receipt['processInstance'] != original.processInstance ||
            receipt['callbackSerial'] != _lastCallbackSerial + 1) {
          throw const NativeWindowRefused('native-original-owner-unproven');
        }
        final int serial = receipt['callbackSerial']! as int;
        call._receipt = NativeWindowFrameReceipt._(
          startup: original,
          request: call.request,
          callbackSerial: serial,
        );
        if (_held || !identical(_pendingFrame, call) || !isCurrent(original)) {
          call._refuse(const NativeWindowRefused('native-owner-held'));
          revoke();
        } else {
          _lastCallbackSerial = serial;
          _pendingFrame = null;
        }
      },
      hold: revoke,
    );
    return call;
  }

  /// Retires admission while every original Future continues to its own result.
  /// No cancellation, native success or recovery is inferred from this call.
  void revoke() {
    _held = true;
  }

  NativeWindowCall<T> _refused<T>(NativeWindowCall<T> call, String code) {
    call._refuse(NativeWindowRefused(code));
    call._settled.complete();
    return call;
  }

  Map<Object?, Object?> _receiptMap(
    Object? value,
    String kind,
    int request,
  ) {
    if (value is! Map<Object?, Object?> ||
        value.length != 8 ||
        value['protocol'] is! int ||
        value['protocol'] != 1 ||
        value['kind'] != kind ||
        value['processId'] is! int ||
        value['processId'] != pid ||
        value['processInstance'] is! String ||
        !RegExp(r'^[0-9a-f]{16}$').hasMatch(
          value['processInstance']! as String,
        ) ||
        value['owner'] is! String ||
        !RegExp(r'^[0-9a-f]{32}$').hasMatch(value['owner']! as String) ||
        value['firstFrameCallback'] is! int ||
        value['firstFrameCallback'] != 1 ||
        value['callbackSerial'] is! int ||
        value['request'] is! int ||
        value['request'] != request) {
      throw const NativeWindowRefused('native-receipt-malformed');
    }
    return value;
  }
}
