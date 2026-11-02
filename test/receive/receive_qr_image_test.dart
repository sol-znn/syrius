import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pretty_qr_code/pretty_qr_code.dart';
import 'package:zenon_syrius_wallet_flutter/utils/zts_utils.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/reusable_widgets/receive_qr_image.dart';

import 'receive_test_support.dart';

ReceiveQrImage _qr({
  String data = 'request-one',
  ReceiveQrEncoder? encode,
  bool Function()? isRequestCurrent,
  Future<void> Function(Uint8List)? share,
  Future<void> Function(Uint8List)? save,
}) => ReceiveQrImage(
  key: const Key('test_qr'),
  data: data,
  size: 150,
  tokenStandard: kZnnCoin.tokenStandard,
  encodeImage: encode ?? receiveTestEncode,
  isRequestCurrent: isRequestCurrent,
  onShareImage: share ?? (Uint8List _) async {},
  onSaveImage: save ?? (Uint8List _) async {},
);

void main() {
  testWidgets('Share and Save receive bytes at injected boundaries', (
    WidgetTester tester,
  ) async {
    final List<List<int>> shared = <List<int>>[];
    final List<List<int>> saved = <List<int>>[];
    final List<int> sizes = <int>[];
    await tester.pumpWidget(
      receiveTestHost(
        _qr(
          encode:
              (
                QrImage image,
                PrettyQrDecoration decoration,
                int size,
              ) async {
                sizes.add(size);
                return Uint8List.fromList(<int>[4, 5, 6]);
              },
          share: (Uint8List bytes) async => shared.add(bytes.toList()),
          save: (Uint8List bytes) async => saved.add(bytes.toList()),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('receive_share_image')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('receive_save_image')));
    await tester.pump();
    expect(sizes, <int>[150, 150]);
    expect(shared, <List<int>>[
      <int>[4, 5, 6],
    ]);
    expect(saved, <List<int>>[
      <int>[4, 5, 6],
    ]);
    expect(find.text('Copy image'), findsNothing);
    await receiveTestDispose(tester);
  });

  testWidgets('a pending encoder disables exports and refuses a replaced QR', (
    WidgetTester tester,
  ) async {
    final Completer<Uint8List?> encoding = Completer<Uint8List?>();
    final List<Uint8List> exports = <Uint8List>[];
    await tester.pumpWidget(
      receiveTestHost(
        _qr(
          encode:
              (
                QrImage image,
                PrettyQrDecoration decoration,
                int size,
              ) => encoding.future,
          share: (Uint8List bytes) async => exports.add(bytes),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('receive_share_image')));
    await tester.pump();
    expect(
      tester
          .widget<TextButton>(find.byKey(const Key('receive_share_image')))
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<TextButton>(find.byKey(const Key('receive_save_image')))
          .onPressed,
      isNull,
    );
    await tester.pumpWidget(receiveTestHost(_qr(data: 'request-two')));
    encoding.complete(Uint8List.fromList(<int>[1]));
    await tester.pump();
    expect(exports, isEmpty);
    expect(
      tester
          .widget<Tooltip>(find.byKey(const Key('receive_qr_payload')))
          .message,
      'request-two',
    );
    await receiveTestDispose(tester);
  });

  testWidgets('disposed request never exports a late encoded image', (
    WidgetTester tester,
  ) async {
    final Completer<Uint8List?> encoding = Completer<Uint8List?>();
    final List<Uint8List> exports = <Uint8List>[];
    await tester.pumpWidget(
      receiveTestHost(
        _qr(
          encode:
              (
                QrImage image,
                PrettyQrDecoration decoration,
                int size,
              ) => encoding.future,
          share: (Uint8List bytes) async => exports.add(bytes),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('receive_share_image')));
    await tester.pumpWidget(const SizedBox.shrink());
    encoding.complete(Uint8List.fromList(<int>[1]));
    await tester.pump();
    expect(exports, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('synchronous ownership guards admission and native dispatch', (
    WidgetTester tester,
  ) async {
    final Completer<Uint8List?> encoding = Completer<Uint8List?>();
    final List<Uint8List> exports = <Uint8List>[];
    bool current = false;
    int encodings = 0;
    await tester.pumpWidget(
      receiveTestHost(
        _qr(
          isRequestCurrent: () => current,
          encode:
              (
                QrImage image,
                PrettyQrDecoration decoration,
                int size,
              ) {
                encodings += 1;
                return encoding.future;
              },
          share: (Uint8List bytes) async => exports.add(bytes),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('receive_share_image')));
    await tester.pump();
    expect(encodings, 0);
    current = true;
    await tester.tap(find.byKey(const Key('receive_share_image')));
    await tester.pump();
    expect(encodings, 1);
    current = false;
    encoding.complete(Uint8List.fromList(<int>[1]));
    await tester.pump();
    expect(exports, isEmpty);
    await receiveTestDispose(tester);
  });

  testWidgets('missing encoded bytes fail visibly and can be retried', (
    WidgetTester tester,
  ) async {
    int encodings = 0;
    int exports = 0;
    await tester.pumpWidget(
      receiveTestHost(
        _qr(
          encode:
              (
                QrImage image,
                PrettyQrDecoration decoration,
                int size,
              ) async => ++encodings == 1 ? null : Uint8List.fromList(<int>[8]),
          save: (Uint8List bytes) async {
            exports += 1;
          },
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('receive_save_image')));
    await tester.pump();
    expect(exports, 0);
    expect(find.text('The QR image could not be exported'), findsOneWidget);
    await tester.tap(find.byKey(const Key('receive_save_image')));
    await tester.pump();
    expect(exports, 1);
    expect(find.text('The QR image could not be exported'), findsNothing);
    await receiveTestDispose(tester);
  });

  testWidgets('native export failures expose only the localized remedy', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      receiveTestHost(
        _qr(
          share: (Uint8List bytes) async {
            throw StateError('test export internals');
          },
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('receive_share_image')));
    await tester.pump();
    expect(find.text('The QR image could not be exported'), findsOneWidget);
    expect(find.textContaining('test export internals'), findsNothing);
    await receiveTestDispose(tester);
  });

  testWidgets('late native completion leaves disposed state alone', (
    WidgetTester tester,
  ) async {
    final Completer<void> exported = Completer<void>();
    await tester.pumpWidget(
      receiveTestHost(_qr(save: (Uint8List bytes) => exported.future)),
    );
    await tester.tap(find.byKey(const Key('receive_save_image')));
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    exported.completeError(StateError('test late export failure'));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
