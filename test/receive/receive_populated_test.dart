import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' as foundation show TargetPlatform;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pretty_qr_code/pretty_qr_code.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/receive/receive_header_controller.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/receive/widgets/receive_populated.dart';
import 'package:zenon_syrius_wallet_flutter/utils/app_theme.dart';
import 'package:zenon_syrius_wallet_flutter/utils/zts_utils.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/reusable_widgets/receive_qr_image.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/shell/page_dismiss.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

import 'receive_test_support.dart';

String get _first => emptyAddress.toString();
String get _second => pillarAddress.toString();

ReceivePopulated _form({
  List<Token>? assets,
  Future<void> Function(String)? copy,
  Future<void> Function(Uint8List)? share,
  Future<void> Function(Uint8List)? save,
  ReceiveQrEncoder? encode,
  ReceiveHeaderController? header,
  bool Function()? isCurrent,
  List<String>? addresses,
}) => ReceivePopulated(
  key: const Key('receive_test_form'),
  assets: assets ?? <Token>[kZnnCoin, kQsrCoin],
  addresses: addresses ?? <String>[_first, _second],
  addressLabels: <String, String>{_first: 'Address 1', _second: 'Address 2'},
  initialAddress: _first,
  onCopyAddress: copy ?? (String _) async {},
  onShareImage: share ?? (Uint8List _) async {},
  onSaveImage: save ?? (Uint8List _) async {},
  encodeImage: encode ?? receiveTestEncode,
  headerController: header,
  isCurrent: isCurrent,
);

String _payload(WidgetTester tester) => tester
    .widget<Tooltip>(find.byKey(const Key('receive_qr_payload')))
    .message!;

Future<void> _showQr(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('receive_qr_toggle')));
  await receiveTestReveal(tester);
}

Future<void> _toggleRequest(WidgetTester tester) async {
  final Finder toggle = find.byKey(const Key('receive_request_toggle'));
  await tester.ensureVisible(toggle);
  await tester.tap(toggle);
  await receiveTestReveal(tester);
}

Widget _desktopForm(ReceivePopulated form, {required bool light}) => Theme(
  data: (light ? AppTheme.lightTheme : AppTheme.darkTheme).copyWith(
    platform: foundation.TargetPlatform.windows,
    visualDensity: VisualDensity.compact,
  ),
  child: form,
);

void _expectActionGeometry(WidgetTester tester, {required bool compact}) {
  for (final Key key in const <Key>[
    Key('receive_copy_address'),
    Key('receive_qr_toggle'),
  ]) {
    final Finder action = find.byKey(key);
    final Finder label = find.descendant(
      of: action,
      matching: find.byType(Text),
    );
    final Finder button = find.ancestor(
      of: label,
      matching: find.byType(OutlinedButton),
    );
    expect(label, findsOneWidget);
    expect(button, findsOneWidget);
    expect(
      Theme.of(tester.element(action)).visualDensity,
      VisualDensity.compact,
    );
    expect(tester.getSize(action).height, compact ? 30 : 38);
    expect(tester.getSize(button).height, compact ? 30 : 38);
    final TextStyle text = DefaultTextStyle.of(tester.element(label)).style;
    expect(text.fontSize, compact ? 13 : 14);
    expect(text.fontWeight, compact ? FontWeight.w500 : FontWeight.w600);
    final OutlinedButton control = tester.widget<OutlinedButton>(button);
    expect(
      control.style!.padding!
          .resolve(const <WidgetState>{})!
          .resolve(
            TextDirection.ltr,
          ),
      EdgeInsets.symmetric(horizontal: compact ? 12 : 16),
    );
  }
  for (final IconData icon in const <IconData>[
    Icons.copy_rounded,
    Icons.qr_code_rounded,
  ]) {
    expect(tester.getSize(find.byIcon(icon)), Size.square(compact ? 14 : 18));
  }
}

void main() {
  testWidgets('Receive header snapshots revoke old choices synchronously', (
    WidgetTester tester,
  ) async {
    final ReceiveHeaderController header = ReceiveHeaderController();
    final Object owner = Object();
    final Object replacement = Object();
    final Map<String, String> labels = <String, String>{_first: 'Address 1'};
    final List<String> selections = <String>[];
    bool current = true;
    bool isCurrent() => current;
    bool select(String address) {
      selections.add(address);
      return true;
    }
    void publish(Object source, int revision) => header.publish(
      owner: source,
      expectedRevision: revision,
      labels: labels,
      selected: _first,
      isCurrent: isCurrent,
      onSelected: select,
    );
    publish(owner, header.revision);
    final ReceiveHeaderSnapshot original = header.snapshot!;
    labels[_second] = 'Address 2';
    expect(original.labels, <String, String>{_first: 'Address 1'});
    expect(() => original.labels[_second] = 'Changed', throwsUnsupportedError);
    expect(header.select(original, _second), isFalse);
    expect(header.select(original, _first), isTrue);
    expect(header.select(original, _first), isFalse);
    final int revoked = header.revision;
    publish(owner, revoked - 1);
    expect(header.snapshot, isNull);
    publish(replacement, revoked);
    final ReceiveHeaderSnapshot latest = header.snapshot!;
    header.detach(owner);
    expect(header.snapshot, same(latest));
    expect(header.select(original, _first), isFalse);
    current = false;
    expect(header.select(latest, _first), isFalse);
    header.invalidate();
    current = true;
    expect(header.select(latest, _first), isFalse);
    expect(selections, <String>[_first]);
    header.dispose();
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('Receive header coalesces notifications and refuses disposal', (
    WidgetTester tester,
  ) async {
    final ReceiveHeaderController header = ReceiveHeaderController();
    int notifications = 0;
    header.addListener(() => notifications += 1);
    header
      ..invalidate()
      ..invalidate();
    expect(notifications, 0);
    await tester.pump();
    expect(notifications, 1);
    header
      ..invalidate()
      ..dispose();
    header.publish(
      owner: Object(),
      expectedRevision: header.revision,
      labels: <String, String>{_first: 'Address 1'},
      selected: _first,
      isCurrent: () => true,
      onSelected: (_) => true,
    );
    await tester.pump();
    expect(header.snapshot, isNull);
    expect(notifications, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Receive header checks latest membership before selection', (
    WidgetTester tester,
  ) async {
    final ReceiveHeaderController header = ReceiveHeaderController();
    final List<String> addresses = <String>[_first, _second];
    await tester.pumpWidget(
      receiveTestHost(_form(header: header, addresses: addresses)),
    );
    await tester.pump();
    final ReceiveHeaderSnapshot choices = header.snapshot!;
    expect(find.byKey(const Key('receive_address_picker')), findsNothing);
    addresses.remove(_second);
    expect(header.select(choices, _second), isFalse);
    expect(
      tester.widget<SelectableText>(find.byKey(const Key('receive_address')))
          .data,
      _first,
    );
    await receiveTestDispose(tester);
    expect(header.select(choices, _first), isFalse);
    header.dispose();
  });

  for (final String change in <String>[
    'address', 'mode cycle', 'controller', 'route cycle',
  ]) {
    testWidgets('Receive header $change revokes pending QR export', (
      WidgetTester tester,
    ) async {
      final ReceiveHeaderController original = ReceiveHeaderController();
      final ReceiveHeaderController replacement = ReceiveHeaderController();
      ReceiveHeaderController header = original;
      final Completer<Uint8List?> encoding = Completer<Uint8List?>();
      final List<Uint8List> exports = <Uint8List>[];
      bool current = true;
      Widget form() => receiveTestHost(_form(
        header: header,
        isCurrent: () => current,
        encode: (QrImage image, PrettyQrDecoration decoration, int size) =>
            encoding.future,
        share: (Uint8List bytes) async => exports.add(bytes),
      ));
      await tester.pumpWidget(form());
      await tester.pump();
      await _showQr(tester);
      final ReceiveHeaderSnapshot choices = original.snapshot!;
      await tester.tap(find.byKey(const Key('receive_share_image')));
      await tester.pump();
      switch (change) {
        case 'address':
          expect(original.select(choices, _second), isTrue);
        case 'mode cycle':
          current = false;
          original.invalidate();
          current = true;
        case 'controller':
          header = replacement;
          await tester.pumpWidget(form());
        case 'route cycle':
          final NavigatorState navigator = Navigator.of(
            tester.element(find.byType(ReceivePopulated)),
          );
          unawaited(navigator.push<void>(MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('Covered')),
          )));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));
          expect(original.select(choices, _second), isFalse);
          navigator.pop();
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));
      }
      encoding.complete(Uint8List.fromList(<int>[1]));
      await tester.pump();
      await tester.pump();
      expect(exports, isEmpty);
      expect(original.select(choices, _second), isFalse);
      expect(
        _payload(tester),
        'znn:${change == 'address' ? _second : _first}'
        '?zts=${kZnnCoin.tokenStandard}&amount=0',
      );
      await receiveTestDispose(tester);
      original.dispose();
      replacement.dispose();
    });
  }

  for (final bool light in <bool>[false, true]) {
    testWidgets('full address at rest with optional controls closed, $light', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(receiveTestHost(_form(), light: light));
      final SelectableText address = tester.widget<SelectableText>(
        find.byKey(const Key('receive_address')),
      );
      expect(address.data, _first);
      expect(address.textDirection, TextDirection.ltr);
      expect(find.text('Copy address'), findsOneWidget);
      expect(find.text('Show QR'), findsOneWidget);
      expect(
        IconTheme.of(tester.element(find.byIcon(Icons.qr_code_rounded))).color,
        AppTokens.of(tester.element(find.byIcon(Icons.qr_code_rounded)))
            .foreground,
      );
      expect(find.byType(ReceiveQrImage), findsNothing);
      expect(find.byKey(const Key('receive_amount_field')), findsNothing);
      expect(find.byKey(const Key('receive_share_image')), findsNothing);
      await _showQr(tester);
      expect(find.text('Hide QR'), findsOneWidget);
      expect(
        IconTheme.of(tester.element(find.byIcon(Icons.qr_code_rounded))).color,
        AppTokens.of(tester.element(find.byIcon(Icons.qr_code_rounded)))
            .foreground,
      );
      expect(
        _payload(tester),
        'znn:$_first?zts=${kZnnCoin.tokenStandard}&amount=0',
      );
      expect(find.text('Share image'), findsOneWidget);
      expect(find.text('Save QR'), findsOneWidget);
      expect(find.text('Copy image'), findsNothing);
      await receiveTestDispose(tester);
    });

    testWidgets(
      'desktop actions follow ordinary and compact QR states, $light',
      (WidgetTester tester) async {
        await tester.pumpWidget(
          receiveTestHost(
            _desktopForm(_form(), light: light),
            light: light,
          ),
        );
        _expectActionGeometry(tester, compact: false);
        await tester.tap(find.byKey(const Key('receive_qr_toggle')));
        await tester.pump();
        _expectActionGeometry(tester, compact: true);
        await tester.pump(const Duration(milliseconds: 120));
        _expectActionGeometry(tester, compact: true);
        await receiveTestReveal(tester);
        expect(find.text('Hide QR'), findsOneWidget);
        _expectActionGeometry(tester, compact: true);
        await tester.tap(find.byKey(const Key('receive_qr_toggle')));
        await tester.pump();
        expect(find.text('Show QR'), findsOneWidget);
        _expectActionGeometry(tester, compact: true);
        await receiveTestReveal(tester);
        expect(find.byType(ReceiveQrImage), findsNothing);
        _expectActionGeometry(tester, compact: false);
        await receiveTestDispose(tester);
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );

    testWidgets(
      'desktop action resizing retains pending copy and request ownership, '
      '$light',
      (WidgetTester tester) async {
        final Completer<void> pending = Completer<void>();
        final List<String> copies = <String>[];
        await tester.pumpWidget(
          receiveTestHost(
            _desktopForm(
              _form(
                copy: (String address) {
                  copies.add(address);
                  return copies.length == 1
                      ? pending.future
                      : Future<void>.value();
                },
              ),
              light: light,
            ),
            light: light,
          ),
        );
        await tester.tap(find.byKey(const Key('receive_copy_address')));
        await tester.pump();
        expect(copies, <String>[_first]);
        _expectActionGeometry(tester, compact: false);
        await _showQr(tester);
        _expectActionGeometry(tester, compact: true);
        await tester.tap(find.byKey(const Key('receive_copy_address')));
        await tester.pump();
        expect(copies, <String>[_first]);
        await _toggleRequest(tester);
        final Finder amount = find.byKey(const Key('receive_amount_field'));
        await tester.enterText(amount, '12.5');
        tester
            .widget<DropdownMenu<String>>(
              find.byKey(const Key('receive_address_picker')),
            )
            .onSelected!(_second);
        await tester.pump();
        expect(
          _payload(tester),
          'znn:$_second?zts=${kZnnCoin.tokenStandard}&amount=1250000000',
        );
        await tester.ensureVisible(find.byKey(const Key('receive_qr_toggle')));
        await _showQr(tester);
        _expectActionGeometry(tester, compact: false);
        pending.complete();
        await tester.pump();
        expect(copies, <String>[_first]);
        expect(tester.widget<TextField>(amount).controller!.text, '12.5');
        await tester.tap(find.byKey(const Key('receive_copy_address')));
        await tester.pump();
        expect(copies, <String>[_first, _second]);
        await _showQr(tester);
        _expectActionGeometry(tester, compact: true);
        expect(
          _payload(tester),
          'znn:$_second?zts=${kZnnCoin.tokenStandard}&amount=1250000000',
        );
        await receiveTestDispose(tester);
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );
  }

  testWidgets('copies the complete selected address without direction marks', (
    WidgetTester tester,
  ) async {
    final List<String> copies = <String>[];
    await tester.pumpWidget(
      receiveTestHost(
        _form(copy: (String value) async => copies.add(value)),
        direction: TextDirection.rtl,
      ),
    );
    await tester.tap(find.byKey(const Key('receive_copy_address')));
    await tester.pump();
    expect(copies, <String>[_first]);
    final DropdownMenu<String> picker = tester.widget<DropdownMenu<String>>(
      find.byKey(const Key('receive_address_picker')),
    );
    picker.onSelected!(_second);
    await tester.pump();
    await tester.tap(find.byKey(const Key('receive_copy_address')));
    await tester.pump();
    expect(copies, <String>[_first, _second]);
    await _showQr(tester);
    expect(
      _payload(tester),
      'znn:$_second?zts=${kZnnCoin.tokenStandard}&amount=0',
    );
    await receiveTestDispose(tester);
  });

  testWidgets('request keeps all base units beyond double precision', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(receiveTestHost(_form()));
    await _toggleRequest(tester);
    await tester.enterText(
      find.byKey(const Key('receive_amount_field')),
      '9007199254740993.00000001',
    );
    await _showQr(tester);
    expect(_payload(tester), endsWith('&amount=900719925474099300000001'));
    await receiveTestDispose(tester);
  });

  testWidgets('QR keeps the full reveal clock and denies closing exports', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(receiveTestHost(_form(), reduced: true));
    await tester.tap(find.byKey(const Key('receive_qr_toggle')));
    await tester.pump();
    final AnimationController motion =
        tester
                .widget<AnimatedBuilder>(
                  find.byKey(const Key('receive_qr_reveal')),
                )
                .animation
            as AnimationController;
    expect(motion.duration, ReceivePopulated.qrRevealDuration);
    expect(motion.animationBehavior, AnimationBehavior.preserve);
    expect(
      tester
          .widget<Transform>(find.byKey(const Key('receive_qr_slide')))
          .transform
          .storage[13],
      -8,
    );
    await tester.pump(const Duration(milliseconds: 239));
    expect(motion.isCompleted, isFalse);
    await tester.pump(const Duration(milliseconds: 1));
    if (!motion.isCompleted) {
      expect(motion.lastElapsedDuration, ReceivePopulated.qrRevealDuration);
    }
    expect(motion.value, closeTo(1, 1e-12));
    // The exact endpoint can round just below one in the ticker's double
    // clock. Settle status at the next quantum without changing its duration.
    await tester.pump(const Duration(microseconds: 1));
    expect(motion.isCompleted, isTrue);
    await tester.tap(find.byKey(const Key('receive_qr_toggle')));
    await tester.pump();
    expect(
      tester
          .widget<TextButton>(find.byKey(const Key('receive_share_image')))
          .onPressed,
      isNull,
    );
    await receiveTestReveal(tester);
    expect(find.byType(ReceiveQrImage), findsNothing);
    await receiveTestDispose(tester);
  });

  testWidgets('token changes revalidate without truncating the typed amount', (
    WidgetTester tester,
  ) async {
    final Token whole = Token.fromJson(<String, dynamic>{
      ...kQsrCoin.toJson(),
      'symbol': 'WHOLE',
      'decimals': 0,
    });
    await tester.pumpWidget(
      receiveTestHost(_form(assets: <Token>[kZnnCoin, whole])),
    );
    await _toggleRequest(tester);
    final Finder field = find.byKey(const Key('receive_amount_field'));
    await tester.enterText(field, '1.5');
    await _showQr(tester);
    expect(_payload(tester), endsWith('&amount=150000000'));
    tester
        .widget<DropdownMenu<Token>>(
          find.byKey(const Key('receive_token_picker')),
        )
        .onSelected!(whole);
    await tester.pump();
    expect(tester.widget<TextField>(field).controller!.text, '1.5');
    expect(find.byType(ReceiveQrImage), findsNothing);
    expect(find.byKey(const Key('receive_share_image')), findsNothing);
    tester
        .widget<DropdownMenu<Token>>(
          find.byKey(const Key('receive_token_picker')),
        )
        .onSelected!(kZnnCoin);
    await tester.pump();
    expect(_payload(tester), endsWith('&amount=150000000'));
    await receiveTestDispose(tester);
  });

  testWidgets('invalid amounts expose no image export or zero substitution', (
    WidgetTester tester,
  ) async {
    final List<Uint8List> exports = <Uint8List>[];
    await tester.pumpWidget(
      receiveTestHost(
        _form(
          share: (Uint8List bytes) async => exports.add(bytes),
          save: (Uint8List bytes) async => exports.add(bytes),
        ),
      ),
    );
    await _toggleRequest(tester);
    await _showQr(tester);
    for (final String amount in <String>[
      '0',
      '1.000000001',
      (kBigP255m1 + BigInt.one).toString(),
    ]) {
      await tester.enterText(
        find.byKey(const Key('receive_amount_field')),
        amount,
      );
      await tester.pump();
      expect(find.byType(ReceiveQrImage), findsNothing, reason: amount);
      expect(find.byKey(const Key('receive_share_image')), findsNothing);
      expect(find.byKey(const Key('receive_save_image')), findsNothing);
    }
    expect(exports, isEmpty);
    await receiveTestDispose(tester);
  });

  testWidgets('invalidating a request refuses bytes from its pending encoder', (
    WidgetTester tester,
  ) async {
    final Completer<Uint8List?> encoding = Completer<Uint8List?>();
    final List<Uint8List> exports = <Uint8List>[];
    await tester.pumpWidget(
      receiveTestHost(
        _form(
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
    await _toggleRequest(tester);
    final Finder amount = find.byKey(const Key('receive_amount_field'));
    await tester.enterText(amount, '1');
    await _showQr(tester);
    await tester.tap(find.byKey(const Key('receive_share_image')));
    await tester.pump();
    await tester.enterText(amount, '1.000000001');
    encoding.complete(Uint8List.fromList(<int>[1]));
    await tester.pump();
    expect(find.byType(ReceiveQrImage), findsNothing);
    expect(exports, isEmpty);
    await receiveTestDispose(tester);
  });

  testWidgets('restoring the same amount does not revive an old export', (
    WidgetTester tester,
  ) async {
    final Completer<Uint8List?> encoding = Completer<Uint8List?>();
    final List<Uint8List> exports = <Uint8List>[];
    await tester.pumpWidget(
      receiveTestHost(
        _form(
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
    await _toggleRequest(tester);
    final Finder amount = find.byKey(const Key('receive_amount_field'));
    await tester.enterText(amount, '1');
    await _showQr(tester);
    final String originalPayload = _payload(tester);
    final TextEditingController controller = tester
        .widget<TextField>(amount)
        .controller!;
    await tester.tap(find.byKey(const Key('receive_share_image')));
    await tester.pump();
    // Both edits precede the next frame and return to the same wire value.
    controller
      ..text = '1.000000001'
      ..text = '1';
    encoding.complete(Uint8List.fromList(<int>[1]));
    await tester.pump();
    expect(_payload(tester), originalPayload);
    expect(exports, isEmpty);
    await tester.tap(find.byKey(const Key('receive_share_image')));
    await tester.pump();
    expect(exports, <List<int>>[
      <int>[1],
    ]);
    await receiveTestDispose(tester);
  });

  testWidgets('Escape closes request then QR while retaining the draft', (
    WidgetTester tester,
  ) async {
    final PageDismissController dismiss = PageDismissController();
    try {
      await tester.pumpWidget(
        receiveTestHost(
          PageDismissScope(controller: dismiss, child: _form()),
        ),
      );
      await _showQr(tester);
      await _toggleRequest(tester);
      await tester.enterText(
        find.byKey(const Key('receive_amount_field')),
        '12.5',
      );
      expect(dismiss.dismissLatest(), isTrue);
      await receiveTestReveal(tester);
      expect(find.byKey(const Key('receive_amount_field')), findsNothing);
      expect(find.byType(ReceiveQrImage), findsOneWidget);
      expect(dismiss.dismissLatest(), isTrue);
      await receiveTestReveal(tester);
      expect(find.byType(ReceiveQrImage), findsNothing);
      await _toggleRequest(tester);
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('receive_amount_field')))
            .controller!
            .text,
        '12.5',
      );
      await receiveTestDispose(tester);
    } finally {
      dismiss.dispose();
    }
  });

  testWidgets('disclosure and QR toggles retain address, token and amount', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(receiveTestHost(_form()));
    await _toggleRequest(tester);
    final Finder field = find.byKey(const Key('receive_amount_field'));
    await tester.enterText(field, '100.5');
    tester
        .widget<DropdownMenu<Token>>(
          find.byKey(const Key('receive_token_picker')),
        )
        .onSelected!(kQsrCoin);
    tester
        .widget<DropdownMenu<String>>(
          find.byKey(const Key('receive_address_picker')),
        )
        .onSelected!(_second);
    await tester.pump();
    await _showQr(tester);
    final String request = _payload(tester);
    expect(
      request,
      'qsr:$_second?zts=${kQsrCoin.tokenStandard}&amount=10050000000',
    );
    await _toggleRequest(tester);
    expect(find.byKey(const Key('receive_amount_field')), findsNothing);
    expect(_payload(tester), request);
    await _showQr(tester);
    await _showQr(tester);
    await _toggleRequest(tester);
    expect(tester.widget<TextField>(field).controller!.text, '100.5');
    expect(_payload(tester), request);
    await receiveTestDispose(tester);
  });

  testWidgets('refreshed precision invalidates a retained request', (
    WidgetTester tester,
  ) async {
    final List<Token> original = <Token>[kQsrCoin, kZnnCoin];
    await tester.pumpWidget(receiveTestHost(_form(assets: original)));
    expect(original, <Token>[kQsrCoin, kZnnCoin]);
    await _toggleRequest(tester);
    await tester.enterText(
      find.byKey(const Key('receive_amount_field')),
      '1.5',
    );
    await _showQr(tester);
    final Token wholeZnn = Token.fromJson(<String, dynamic>{
      ...kZnnCoin.toJson(),
      'decimals': 0,
    });
    await tester.pumpWidget(
      receiveTestHost(_form(assets: <Token>[wholeZnn, kQsrCoin])),
    );
    expect(find.byType(ReceiveQrImage), findsNothing);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('receive_amount_field')))
          .controller!
          .text,
      '1.5',
    );
    await receiveTestDispose(tester);
  });

  testWidgets('narrow RTL and scaled text keep the full address below QR', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      receiveTestHost(
        _form(),
        width: 320,
        scale: 1.5,
        direction: TextDirection.rtl,
      ),
    );
    await _showQr(tester);
    expect(
      tester.getTopLeft(find.byKey(const Key('receive_address'))).dy,
      greaterThan(
        tester.getBottomLeft(find.byKey(const Key('receive_qr_image'))).dy,
      ),
    );
    await _toggleRequest(tester);
    await tester.ensureVisible(find.byKey(const Key('receive_amount_field')));
    await tester.enterText(find.byKey(const Key('receive_amount_field')), '.5');
    await tester.pump();
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('receive_amount_field')))
          .textDirection,
      TextDirection.ltr,
    );
    expect(_payload(tester), endsWith('&amount=50000000'));
    await receiveTestDispose(tester);
  });

  testWidgets('late clipboard completion after disposal stays local', (
    WidgetTester tester,
  ) async {
    final Completer<void> copy = Completer<void>();
    await tester.pumpWidget(
      receiveTestHost(_form(copy: (String _) => copy.future)),
    );
    await tester.tap(find.byKey(const Key('receive_copy_address')));
    await tester.pumpWidget(const SizedBox.shrink());
    copy.completeError(StateError('test clipboard failure'));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
