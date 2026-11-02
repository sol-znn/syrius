import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/l10n/app_localizations.dart';
import 'package:zenon_syrius_wallet_flutter/l10n/l10n.dart';
import 'package:zenon_syrius_wallet_flutter/seams/missing_services.dart';
import 'package:zenon_syrius_wallet_flutter/seams/seam.dart';
import 'package:zenon_syrius_wallet_flutter/utils/app_theme.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/reusable_widgets/modals/frosted_route.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/tab_children_widgets/lock_card.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/tab_children_widgets/lock_wallet_picker.dart';

const Key _field = ValueKey<String>('lock_wallet_display');
const Key _arrow = ValueKey<String>('lock_wallet_picker_arrow');
const Key _menu = ValueKey<String>('lock_wallet_picker_menu');
const Key _add = ValueKey<String>('lock_wallet_picker_add');
const Key _before = ValueKey<String>('before_picker_field');
const Key _after = ValueKey<String>('after_picker_field');
const MethodChannel _window = MethodChannel('window_manager');

// These identifiers are deliberately not wallet addresses or catalog records.
const LockWalletDisplayEntry _current = LockWalletDisplayEntry(
  name: 'Synthetic current',
  address: 'synthetic-current-address-0001',
);
const LockWalletDisplayEntry _hardware = LockWalletDisplayEntry(
  name: 'Synthetic hardware',
  address: 'synthetic-hardware-address-0002',
  isLedger: true,
);
const LockWalletDisplayEntry _secondary = LockWalletDisplayEntry(
  name: 'Synthetic secondary',
  address: 'synthetic-secondary-address-0003',
);
const List<LockWalletDisplayEntry> _entries = <LockWalletDisplayEntry>[
  _current,
  _hardware,
  _secondary,
];

/// The actual card can lay out without decoding art or constructing auth.
class _PendingArtBundle extends CachingAssetBundle {
  final Completer<ByteData> _bytes = Completer<ByteData>();

  @override
  Future<ByteData> load(String key) => _bytes.future;
}

Key _entryKey(int index) => ValueKey<String>('lock_wallet_picker_entry_$index');

Matcher get _pickerError => isA<SeamNotBuilt>().having(
  (SeamNotBuilt error) => error.seam,
  'seam',
  Seam.walletPicker,
);

Widget _host({
  required Widget child,
  bool light = false,
  TextDirection direction = TextDirection.ltr,
  double scale = 1,
}) => MaterialApp(
  locale: const Locale('en'),
  theme: light ? AppTheme.lightTheme : AppTheme.darkTheme,
  supportedLocales: AppLocalizations.supportedLocales,
  localizationsDelegates: appLocalizationsDelegates,
  builder: (BuildContext context, Widget? child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
    child: child!,
  ),
  home: Directionality(
    textDirection: direction,
    child: Scaffold(body: child),
  ),
);

Widget _frame(Widget child) => Builder(
  builder: (BuildContext context) {
    final AppTokens tokens = AppTokens.of(context);
    return SingleChildScrollView(
      child: Center(
        child: Padding(
          padding: tokens.lockPagePadding,
          child: Container(
            width: tokens.lockCardWidth,
            decoration: BoxDecoration(
              border: Border.all(color: tokens.line),
            ),
            padding: tokens.lockContentPadding,
            child: child,
          ),
        ),
      ),
    );
  },
);

Future<void> _show(
  WidgetTester tester,
  Widget host, {
  Size size = const Size(1280, 780),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));
  await tester.pumpWidget(host);
  await tester.pump();
}

LockWalletPicker _preview() =>
    LockWalletPicker(current: _current, entries: _entries, expanded: true);

EditableText _editable(WidgetTester tester, Key key) =>
    tester.widget<EditableText>(
      find.descendant(of: find.byKey(key), matching: find.byType(EditableText)),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_window, (MethodCall call) async => true);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_window, null);
  });

  for (final bool light in <bool>[false, true]) {
    for (final TextDirection direction in TextDirection.values) {
      final String variant = '${light ? 'light' : 'dark'} ${direction.name}';

      testWidgets('$variant production retains only its actual current field', (
        WidgetTester tester,
      ) async {
        final TextEditingController password = TextEditingController();
        addTearDown(password.dispose);
        final SemanticsHandle semantics = tester.ensureSemantics();
        try {
          await _show(
            tester,
            _host(
              light: light,
              direction: direction,
              child: DefaultAssetBundle(
                bundle: _PendingArtBundle(),
                child: LockCard(
                  walletName: _current.name,
                  address: _current.address,
                  passwordController: password,
                  onUnlock: () {},
                ),
              ),
            ),
          );
          final AppTokens tokens = light ? AppTokens.light : AppTokens.dark;
          final LockWalletPicker picker = tester.widget<LockWalletPicker>(
            find.byType(LockWalletPicker),
          );
          expect(picker.current.name, _current.name);
          expect(picker.current.address, _current.address);
          expect(picker.entries, isEmpty);
          expect(picker.expanded, isFalse);
          expect(find.byKey(_menu), findsNothing);
          expect(find.byKey(_add), findsNothing);
          expect(find.text(_hardware.name), findsNothing);
          expect(find.text(_secondary.name), findsNothing);
          expect(find.text('Main'), findsNothing);
          expect(find.text('Lab devnet'), findsNothing);
          final Rect field = tester.getRect(find.byKey(_field));
          expect(field.size, Size(362, tokens.fieldHeight));
          expect(
            tester
                .getSize(
                  find.byKey(const ValueKey<String>('lock_card_surface')),
                )
                .width,
            tokens.lockCardWidth,
          );
          final Rect passwordBounds = tester.getRect(
            find.byKey(const ValueKey<String>('wallet_password_field')),
          );
          expect(passwordBounds.width, field.width);
          expect(passwordBounds.height, tokens.fieldHeight);
          expect(find.semantics.byLabel(_current.name), findsWidgets);
          expect(find.semantics.byLabel(_current.address!), findsWidgets);
          expect(find.byTooltip(_current.name), findsOneWidget);
          expect(find.byTooltip(_current.address!), findsOneWidget);
          expect(
            Directionality.of(tester.element(find.text('synthe…0001'))),
            TextDirection.ltr,
          );
          final Text address = tester.widget<Text>(find.text('synthe…0001'));
          expect(address.style, tokens.lockAddressText);
          await tester.tapAt(tester.getCenter(find.byKey(_arrow)));
          await tester.pump();
          expect(find.byKey(_menu), findsNothing);
          expect(tester.takeException(), isNull);
        } finally {
          semantics.dispose();
        }
      });

      testWidgets('$variant external menu matches the measured field', (
        WidgetTester tester,
      ) async {
        await _show(
          tester,
          _host(
            light: light,
            direction: direction,
            child: _frame(_preview()),
          ),
        );
        final AppTokens tokens = light ? AppTokens.light : AppTokens.dark;
        final Rect field = tester.getRect(find.byKey(_field));
        final Rect menu = tester.getRect(find.byKey(_menu));
        expect(field.size, Size(362, tokens.fieldHeight));
        expect(menu.left, field.left);
        expect(menu.right, field.right);
        expect(menu.top - field.bottom, tokens.walletPickerMenuGap);
        expect(find.byIcon(Icons.expand_less), findsOneWidget);
        expect(find.byIcon(Icons.usb_outlined), findsOneWidget);
        expect(find.byIcon(Icons.key_outlined), findsNWidgets(3));
        expect(find.byIcon(Icons.add), findsOneWidget);
        final FrostedSurface frost = tester.widget<FrostedSurface>(
          find.byType(FrostedSurface),
        );
        expect(frost.sigma, tokens.menuBlur);
        expect(frost.borderRadius, BorderRadius.circular(tokens.cardRadius));
        final Container surface = tester.widget<Container>(find.byKey(_menu));
        expect(
          (surface.decoration! as BoxDecoration).boxShadow,
          <BoxShadow>[tokens.menuShadow],
        );
        for (int index = 0; index < _entries.length; index++) {
          final Finder row = find.byKey(_entryKey(index));
          final Rect rowBounds = tester.getRect(row);
          expect(rowBounds.height, tokens.walletPickerRowHeight);
          expect(rowBounds.left, menu.left);
          expect(rowBounds.right, menu.right);
          final TextButton button = tester.widget<TextButton>(row);
          final ButtonStyle style = button.style!;
          expect(
            style.padding!.resolve(<WidgetState>{}),
            tokens.walletPickerRowPadding,
          );
          expect(
            style.backgroundColor!.resolve(<WidgetState>{}),
            index == 0 ? tokens.card3 : tokens.card3.withValues(alpha: 0),
          );
          final TextStyle nameStyle = style.textStyle!.resolve(
            <WidgetState>{},
          )!;
          expect(nameStyle.fontFamily, tokens.sansFontFamily);
          expect(nameStyle.fontSize, 13);
          final Finder address = find.descendant(
            of: row,
            matching: find.text('synthe…000${index + 1}'),
          );
          expect(
            tester.widget<Text>(address).style,
            tokens.walletPickerAddressText,
          );
          expect(
            Directionality.of(tester.element(address)),
            TextDirection.ltr,
          );
          final Rect addressBounds = tester.getRect(address);
          final EdgeInsets rowPadding = tokens.walletPickerRowPadding.resolve(
            direction,
          );
          expect(
            direction == TextDirection.ltr
                ? addressBounds.right
                : addressBounds.left,
            direction == TextDirection.ltr
                ? rowBounds.right - rowPadding.right
                : rowBounds.left + rowPadding.left,
          );
          expect(
            find.descendant(
              of: row,
              matching: find.byTooltip(_entries[index].address!),
            ),
            findsOneWidget,
          );
        }
        expect(
          tester.getSize(find.byKey(_add)).height,
          tokens.walletPickerRowHeight,
        );
        final Divider divider = tester.widget<Divider>(
          find.byKey(const ValueKey<String>('lock_wallet_picker_separator')),
        );
        expect(divider.color, tokens.line);
        expect(divider.thickness, tokens.glassTopEdge.width);
        expect(tester.takeException(), isNull);
      });

      testWidgets('$variant gates pointer, key, semantics and callbacks', (
        WidgetTester tester,
      ) async {
        final SemanticsHandle semantics = tester.ensureSemantics();
        const int mouseDevice = 41;
        bool mouseAdded = false;
        try {
          await _show(
            tester,
            _host(
              light: light,
              direction: direction,
              child: _frame(_preview()),
            ),
          );
          expect(find.byType(SeamGate), findsNWidgets(5));
          expect(find.semantics.byLabel(_current.name), findsWidgets);
          expect(find.semantics.byLabel(_hardware.name), findsNothing);
          for (int index = 0; index < 5; index++) {
            final Finder gate = find.byType(SeamGate).at(index);
            final SemanticsNode node = tester.getSemantics(gate);
            expect(
              node,
              isSemantics(
                label: 'Not yet',
                hasEnabledState: true,
                isEnabled: false,
              ),
            );
            for (final ui.SemanticsAction action in <ui.SemanticsAction>[
              ui.SemanticsAction.tap,
              ui.SemanticsAction.longPress,
              ui.SemanticsAction.focus,
              ui.SemanticsAction.setText,
            ]) {
              expect(node.getSemanticsData().hasAction(action), isFalse);
              node.owner!.performAction(node.id, action, 'injected');
            }
          }
          await tester.sendEventToBinding(
            PointerAddedEvent(
              device: mouseDevice,
              kind: ui.PointerDeviceKind.mouse,
              viewId: tester.view.viewId,
            ),
          );
          mouseAdded = true;
          for (final Key key in <Key>[
            _arrow,
            for (int index = 0; index < _entries.length; index++)
              _entryKey(index),
            _add,
          ]) {
            final Finder control = find.byKey(key);
            final Offset position = tester.getCenter(control);
            await tester.sendEventToBinding(
              PointerHoverEvent(
                device: mouseDevice,
                kind: ui.PointerDeviceKind.mouse,
                position: position,
                viewId: tester.view.viewId,
              ),
            );
            await tester.pump();
            expect(
              RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(
                mouseDevice,
              ),
              SystemMouseCursors.basic,
            );
            await tester.tapAt(position);
            await tester.pump(const Duration(milliseconds: 50));
            await tester.tapAt(position);
            await tester.longPressAt(position);
            final FocusNode focus = Focus.of(tester.element(control))
              ..requestFocus();
            await tester.pump();
            expect(focus.hasFocus, isFalse);
            await tester.sendKeyEvent(LogicalKeyboardKey.enter);
            await tester.sendKeyEvent(LogicalKeyboardKey.space);
            await tester.pump(const Duration(seconds: 2));
          }
          expect(
            tester.widget<IconButton>(find.byKey(_arrow)).onPressed,
            throwsA(_pickerError),
          );
          for (final Key key in <Key>[
            for (int index = 0; index < _entries.length; index++)
              _entryKey(index),
            _add,
          ]) {
            expect(
              tester.widget<TextButton>(find.byKey(key)).onPressed,
              throwsA(_pickerError),
            );
          }
          expect(find.byKey(_menu), findsOneWidget);
          expect(find.byType(AlertDialog), findsNothing);
          expect(tester.takeException(), isNull);
        } finally {
          if (mouseAdded) {
            await tester.sendEventToBinding(
              PointerRemovedEvent(
                device: mouseDevice,
                kind: ui.PointerDeviceKind.mouse,
                viewId: tester.view.viewId,
              ),
            );
          }
          semantics.dispose();
        }
      });

      testWidgets('$variant scaled menu stays inside a short view', (
        WidgetTester tester,
      ) async {
        await _show(
          tester,
          _host(
            light: light,
            direction: direction,
            scale: 2,
            child: _frame(_preview()),
          ),
          size: const Size(480, 260),
        );
        final Rect field = tester.getRect(find.byKey(_field));
        final Rect menu = tester.getRect(find.byKey(_menu));
        expect(menu.left, field.left);
        expect(menu.right, field.right);
        expect(menu.width, 362);
        for (int index = 0; index < _entries.length; index++) {
          final Rect row = tester.getRect(find.byKey(_entryKey(index)));
          expect(row.height, greaterThanOrEqualTo(34));
          expect(row.left, greaterThanOrEqualTo(menu.left));
          expect(row.right, lessThanOrEqualTo(menu.right));
        }
        await tester.ensureVisible(find.byKey(_add));
        await tester.pump();
        final Rect add = tester.getRect(find.byKey(_add));
        expect(add.top, greaterThanOrEqualTo(0));
        expect(add.bottom, lessThanOrEqualTo(260));
        expect(tester.takeException(), isNull);
      });
    }
  }

  for (final TextDirection direction in TextDirection.values) {
    testWidgets('${direction.name} TextFields traverse past every gate', (
      WidgetTester tester,
    ) async {
      final TextEditingController before = TextEditingController();
      final TextEditingController after = TextEditingController();
      addTearDown(before.dispose);
      addTearDown(after.dispose);
      await _show(
        tester,
        _host(
          direction: direction,
          child: _frame(
            Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                TextField(key: _before, controller: before),
                _preview(),
                TextField(key: _after, controller: after),
              ],
            ),
          ),
        ),
      );
      final FocusNode beforeFocus = _editable(tester, _before).focusNode;
      final FocusNode afterFocus = _editable(tester, _after).focusNode;
      await tester.tap(find.byKey(_before));
      await tester.pump();
      expect(beforeFocus.hasFocus, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(afterFocus.hasFocus, isTrue);
      expect(beforeFocus.hasFocus, isFalse);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pump();
      expect(beforeFocus.hasFocus, isTrue);
      expect(afterFocus.hasFocus, isFalse);
      await tester.enterText(find.byKey(_before), 'before');
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.enterText(find.byKey(_after), 'after');
      expect(before.text, 'before');
      expect(after.text, 'after');
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('empty display facts invent neither a catalog nor an address', (
    WidgetTester tester,
  ) async {
    await _show(
      tester,
      _host(
        child: _frame(
          LockWalletPicker(current: const LockWalletDisplayEntry(name: '')),
        ),
      ),
    );
    expect(find.byKey(_menu), findsNothing);
    expect(find.byIcon(Icons.usb_outlined), findsNothing);
    expect(find.byTooltip(_current.address!), findsNothing);
    expect(find.text('Main'), findsNothing);
    expect(find.text('Ledger'), findsNothing);
    expect(find.text('Lab devnet'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('entries are frozen and replacement retains no old menu state', (
    WidgetTester tester,
  ) async {
    final List<LockWalletDisplayEntry> source = <LockWalletDisplayEntry>[
      ..._entries,
    ];
    final LockWalletPicker picker = LockWalletPicker(
      current: _current,
      entries: source,
      expanded: true,
    );
    source.clear();
    expect(picker.entries, _entries);
    expect(picker.entries.clear, throwsUnsupportedError);
    await _show(tester, _host(child: _frame(picker)));
    expect(find.byKey(_entryKey(2)), findsOneWidget);
    final VoidCallback refused = tester
        .widget<TextButton>(
          find.byKey(_add),
        )
        .onPressed!;
    await tester.pumpWidget(
      _host(
        child: _frame(LockWalletPicker(current: _hardware)),
      ),
    );
    await tester.pump();
    expect(find.byKey(_menu), findsNothing);
    expect(find.text(_current.name), findsNothing);
    expect(find.text(_hardware.name), findsOneWidget);
    expect(find.byTooltip(_current.address!), findsNothing);
    expect(find.byIcon(Icons.usb_outlined), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(refused, throwsA(_pickerError));
    await tester.pump(const Duration(seconds: 2));
    expect(tester.takeException(), isNull);
  });

  test('indirect entry and the catalog service refuse', () async {
    bool called = false;
    expect(
      runUnlessSeamed(
        seam: Seam.walletPicker,
        action: () => called = true,
      ),
      isFalse,
    );
    expect(called, isFalse);
    await expectLater(
      const UnbuiltWalletPickerService().open(),
      throwsA(_pickerError),
    );
  });
}
