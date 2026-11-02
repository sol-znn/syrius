import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../harness/app/native_window_owner.dart';

const String _owner = '11111111111111111111111111111111';
const String _process = '0123456789abcdef';

Map<String, Object> _reply({
  String kind = 'startup',
  int request = 0,
  int serial = 1,
  String owner = _owner,
  String process = _process,
  int? processId,
}) => <String, Object>{
  'protocol': 1,
  'kind': kind,
  'processId': processId ?? pid,
  'processInstance': process,
  'owner': owner,
  'firstFrameCallback': 1,
  'callbackSerial': serial,
  'request': request,
};

Matcher _refused(String code) => isA<NativeWindowRefused>().having(
  (NativeWindowRefused error) => error.code,
  'refusal',
  code,
);

void main() {
  final TestWidgetsFlutterBinding binding =
      TestWidgetsFlutterBinding.ensureInitialized();
  int scope = 0;
  late MethodChannel channel;

  setUp(() {
    channel = MethodChannel('native-window-owner-test-${scope++}');
  });

  tearDown(() {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
  });

  test(
    'startup reserves the original call before synchronous reentry',
    () async {
      final NativeWindowOwner owner = NativeWindowOwner(channel: channel);
      final Completer<Object?> native = Completer<Object?>();
      NativeWindowCall<NativeWindowStartupReceipt>? reentered;
      int calls = 0;
      binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        MethodCall method,
      ) {
        calls++;
        expect(method.method, 'startup');
        expect(method.arguments, <String, Object>{'protocol': 1});
        reentered = owner.startup();
        return native.future;
      });

      final NativeWindowCall<NativeWindowStartupReceipt> call = owner.startup();
      expect(reentered, same(call));
      expect(owner.startup(), same(call));
      expect(call.original, isNotNull);
      expect(call.isSettled, isFalse);
      expect(calls, 1);
      expect(
        NativeWindowOwner(channel: MethodChannel(channel.name)),
        same(owner),
      );
      final Future<Object?> original = call.original!;
      native.complete(_reply());
      final Object? originalValue = await original;
      final NativeWindowStartupReceipt receipt = await call.completion;
      expect(call.original, same(original));
      expect(call.value, same(originalValue));
      expect(call.receipt, same(receipt));
      expect(owner.startup().receipt, same(receipt));
      expect(receipt.processId, pid);
      expect(receipt.owner, _owner);
      expect(receipt.processInstance, _process);
      expect(receipt.firstFrameCallback, 1);
      expect(owner.isCurrent(receipt), isTrue);
      expect(owner.heldUnknown, isFalse);
    },
  );

  test(
    'pending startup has no synthetic first frame or frame dispatch',
    () async {
      final NativeWindowOwner owner = NativeWindowOwner(channel: channel);
      final Completer<Object?> native = Completer<Object?>();
      int calls = 0;
      binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (_) {
        calls++;
        return native.future;
      });
      final NativeWindowCall<NativeWindowStartupReceipt> startup = owner
          .startup();
      final NativeWindowCall<NativeWindowFrameReceipt> refused = owner
          .requestFrame();
      expect(refused.original, isNull);
      await expectLater(
        refused.completion,
        throwsA(_refused('native-startup-unproven')),
      );
      expect(calls, 1);
      expect(startup.isSettled, isFalse);
      expect(startup.receipt, isNull);
      expect(owner.heldUnknown, isFalse);
      native.complete(_reply());
      await startup.completion;
    },
  );

  test('a frame reserves one exact pending Future before reentry', () async {
    final NativeWindowOwner owner = NativeWindowOwner(channel: channel);
    final Completer<Object?> nativeFrame = Completer<Object?>();
    NativeWindowCall<NativeWindowFrameReceipt>? reentered;
    int calls = 0;
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      MethodCall method,
    ) {
      calls++;
      if (method.method == 'startup') {
        return Future<Object?>.value(_reply());
      }
      expect(method.method, 'frame');
      expect(method.arguments, <String, Object>{
        'protocol': 1,
        'owner': _owner,
        'request': 1,
      });
      reentered = owner.requestFrame();
      return nativeFrame.future;
    });
    final NativeWindowStartupReceipt startup = await owner.startup().completion;
    final NativeWindowCall<NativeWindowFrameReceipt> frame = owner
        .requestFrame();
    expect(frame.original, isNotNull);
    expect(frame.isSettled, isFalse);
    expect(reentered!.original, isNull);
    await expectLater(
      reentered!.completion,
      throwsA(_refused('native-frame-busy')),
    );
    expect(calls, 2);
    expect(owner.frames, <NativeWindowCall<NativeWindowFrameReceipt>>[frame]);
    final Future<Object?> original = frame.original!;
    nativeFrame.complete(_reply(kind: 'frame', request: 1, serial: 2));
    final Object? originalValue = await original;
    final NativeWindowFrameReceipt receipt = await frame.completion;
    expect(frame.original, same(original));
    expect(frame.value, same(originalValue));
    expect(receipt.startup, same(startup));
    expect(receipt.callbackSerial, 2);
    expect(receipt.request, 1);
    expect(owner.heldUnknown, isFalse);
  });

  test(
    'each later callback stays with its original request and startup',
    () async {
      final NativeWindowOwner owner = NativeWindowOwner(channel: channel);
      binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        MethodCall method,
      ) async {
        if (method.method == 'startup') return _reply();
        final Map<Object?, Object?> arguments =
            method.arguments as Map<Object?, Object?>;
        final int request = arguments['request']! as int;
        return _reply(kind: 'frame', request: request, serial: request + 1);
      });
      final NativeWindowStartupReceipt startup = await owner
          .startup()
          .completion;
      final NativeWindowCall<NativeWindowFrameReceipt> first = owner
          .requestFrame();
      final NativeWindowFrameReceipt firstReceipt = await first.completion;
      final NativeWindowCall<NativeWindowFrameReceipt> second = owner
          .requestFrame();
      final NativeWindowFrameReceipt secondReceipt = await second.completion;
      expect(firstReceipt.request, 1);
      expect(firstReceipt.callbackSerial, 2);
      expect(secondReceipt.request, 2);
      expect(secondReceipt.callbackSerial, 3);
      expect(secondReceipt.startup, same(startup));
      expect(first.receipt, same(firstReceipt));
      expect(first.original, isNot(same(second.original)));
      expect(owner.frames, <NativeWindowCall<NativeWindowFrameReceipt>>[
        first,
        second,
      ]);
    },
  );

  test(
    'revocation retains a pending original and its late successful reply',
    () async {
      final NativeWindowOwner owner = NativeWindowOwner(channel: channel);
      final Completer<Object?> nativeFrame = Completer<Object?>();
      int frames = 0;
      binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        MethodCall method,
      ) {
        if (method.method == 'startup') {
          return Future<Object?>.value(_reply());
        }
        frames++;
        return nativeFrame.future;
      });
      final NativeWindowStartupReceipt startup = await owner
          .startup()
          .completion;
      final NativeWindowCall<NativeWindowFrameReceipt> frame = owner
          .requestFrame();
      final Future<Object?> original = frame.original!;
      owner.revoke();
      expect(frame.isSettled, isFalse);
      expect(owner.isCurrent(startup), isFalse);
      final NativeWindowOwner reopened = NativeWindowOwner(
        channel: MethodChannel(channel.name),
      );
      expect(reopened, same(owner));
      expect(reopened.heldUnknown, isTrue);
      nativeFrame.complete(_reply(kind: 'frame', request: 1, serial: 2));
      final Object? originalValue = await original;
      await frame.settled;
      expect(frame.original, same(original));
      expect(frame.value, same(originalValue));
      expect(frame.receipt!.startup, same(startup));
      expect(frame.error, isNull);
      await expectLater(
        frame.completion,
        throwsA(_refused('native-owner-held')),
      );
      final NativeWindowCall<NativeWindowFrameReceipt> refused = reopened
          .requestFrame();
      expect(refused.original, isNull);
      await expectLater(
        refused.completion,
        throwsA(_refused('native-owner-held')),
      );
      expect(frames, 1);
    },
  );

  test(
    'late startup success remains held after its scope was retired',
    () async {
      final NativeWindowOwner owner = NativeWindowOwner(channel: channel);
      final Completer<Object?> native = Completer<Object?>();
      binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        (_) => native.future,
      );
      final NativeWindowCall<NativeWindowStartupReceipt> startup = owner
          .startup();
      owner.revoke();
      expect(startup.isSettled, isFalse);
      native.complete(_reply());
      await startup.settled;
      expect(startup.receipt, isNotNull);
      expect(owner.isCurrent(startup.receipt!), isFalse);
      await expectLater(
        startup.completion,
        throwsA(_refused('native-owner-held')),
      );
      expect(owner.startup(), same(startup));
    },
  );

  for (final String changed in <String>[
    'owner',
    'processInstance',
    'request',
    'callbackSerial',
  ]) {
    test('foreign $changed cannot replace the original frame owner', () async {
      final NativeWindowOwner owner = NativeWindowOwner(channel: channel);
      int frames = 0;
      binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        MethodCall method,
      ) async {
        if (method.method == 'startup') return _reply();
        frames++;
        final Map<String, Object> reply = _reply(
          kind: 'frame',
          request: 1,
          serial: 2,
        );
        reply[changed] = switch (changed) {
          'owner' => '22222222222222222222222222222222',
          'processInstance' => 'fedcba9876543210',
          'request' => 2,
          _ => 1,
        };
        return reply;
      });
      final NativeWindowStartupReceipt startup = await owner
          .startup()
          .completion;
      final NativeWindowCall<NativeWindowFrameReceipt> frame = owner
          .requestFrame();
      await frame.settled;
      expect(frame.value, isA<Map<Object?, Object?>>());
      expect(frame.receipt, isNull);
      expect(frame.failure, isA<NativeWindowRefused>());
      expect(owner.heldUnknown, isTrue);
      expect(owner.isCurrent(startup), isFalse);
      expect(NativeWindowOwner(channel: channel), same(owner));
      expect(owner.requestFrame().original, isNull);
      expect(frames, 1);
    });
  }

  final Map<String, Object?> malformed = <String, Object?>{
    'null': null,
    'missing first frame': <String, Object>{..._reply()}
      ..remove('firstFrameCallback'),
    'false first frame': <String, Object>{
      ..._reply(),
      'firstFrameCallback': false,
    },
    'wrong process': _reply(processId: pid + 1),
    'handle instead of generation': <String, Object>{..._reply(), 'owner': 12},
    'unexpected field': <String, Object>{..._reply(), 'handle': 12},
    'first callback absent': _reply(serial: 0),
    'floating protocol': <String, Object>{..._reply(), 'protocol': 1.0},
  };
  for (final MapEntry<String, Object?> entry in malformed.entries) {
    test(
      'malformed startup ${entry.key} holds every later construction',
      () async {
        final NativeWindowOwner owner = NativeWindowOwner(channel: channel);
        int calls = 0;
        binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
          _,
        ) async {
          calls++;
          return entry.value;
        });
        final NativeWindowCall<NativeWindowStartupReceipt> startup = owner
            .startup();
        await startup.settled;
        expect(startup.failure, isA<NativeWindowRefused>());
        expect(startup.receipt, isNull);
        expect(owner.heldUnknown, isTrue);
        expect(
          NativeWindowOwner(channel: MethodChannel(channel.name)).startup(),
          same(startup),
        );
        expect(owner.requestFrame().original, isNull);
        expect(calls, 1);
      },
    );
  }

  for (final bool failStartup in <bool>[true, false]) {
    test(
      'retains the exact failed ${failStartup ? 'startup' : 'frame'} Future',
      () async {
        final NativeWindowOwner owner = NativeWindowOwner(channel: channel);
        binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
          MethodCall method,
        ) async {
          if (!failStartup && method.method == 'startup') return _reply();
          throw PlatformException(
            code: 'native-owner-destroyed',
            message: 'Private platform detail',
            details: <String, Object>{'private': 'Retained only in the call'},
          );
        });
        final NativeWindowCall<NativeWindowStartupReceipt> startup = owner
            .startup();
        late NativeWindowCall<Object> call;
        if (failStartup) {
          call = startup;
        } else {
          await startup.completion;
          call = owner.requestFrame();
        }
        final Future<Object?> original = call.original!;
        Object? originalError;
        StackTrace? originalTrace;
        await original.then<void>(
          (_) => fail('failed method returned success'),
          onError: (Object error, StackTrace trace) {
            originalError = error;
            originalTrace = trace;
          },
        );
        await call.settled;
        expect(call.original, same(original));
        expect(call.error, same(originalError));
        expect(call.stackTrace, same(originalTrace));
        expect(call.failure, same(originalError));
        expect(call.receipt, isNull);
        expect(owner.heldUnknown, isTrue);
        expect(NativeWindowOwner(channel: channel), same(owner));
        expect(owner.requestFrame().original, isNull);
        await expectLater(call.completion, throwsA(same(originalError)));
      },
    );
  }

  test('retained native evidence has a finite frame request limit', () async {
    final NativeWindowOwner owner = NativeWindowOwner(channel: channel);
    int frames = 0;
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      MethodCall method,
    ) async {
      if (method.method == 'startup') return _reply();
      frames++;
      return _reply(kind: 'frame', request: frames, serial: frames + 1);
    });
    await owner.startup().completion;
    for (int index = 0; index < NativeWindowOwner.maxFrameRequests; index++) {
      await owner.requestFrame().completion;
    }
    final NativeWindowCall<NativeWindowFrameReceipt> refused = owner
        .requestFrame();
    expect(refused.original, isNull);
    await expectLater(
      refused.completion,
      throwsA(_refused('native-frame-limit')),
    );
    expect(frames, NativeWindowOwner.maxFrameRequests);
    expect(owner.frames.length, NativeWindowOwner.maxFrameRequests);
    expect(owner.heldUnknown, isFalse);
  });
}
