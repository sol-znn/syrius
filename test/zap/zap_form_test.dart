import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/l10n/app_localizations.dart';
import 'package:zenon_syrius_wallet_flutter/l10n/l10n.dart';
import 'package:zenon_syrius_wallet_flutter/main.dart' as app;
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/zap/zap.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/dollar_text.dart';
import 'package:zenon_syrius_wallet_flutter/seams/seam.dart';
import 'package:zenon_syrius_wallet_flutter/services/price_feed.dart';
import 'package:zenon_syrius_wallet_flutter/utils/app_theme.dart';
import 'package:zenon_syrius_wallet_flutter/utils/notifiers/balance_visibility.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/reusable_widgets/buttons/primary_pill.dart';

const String _prices = '{"zenon-2":{"usd":0.62},"quasar":{"usd":0.031}}';
const String _defaultMessage = 'You got zapped. Have a great day, alien.';

Finder _key(String value) => find.byKey(Key(value));

TextField _field(WidgetTester tester, String key) =>
    tester.widget<TextField>(_key(key));

class _InspectablePriceFeed extends PriceFeed {
  _InspectablePriceFeed({required super.request});

  bool get hasActiveListeners => hasListeners;
}

class _InspectableVisibility extends BalanceVisibility {
  bool get hasActiveListeners => hasListeners;
}

class _Fixture {
  _Fixture({ZapDraft initial = const ZapDraft()})
    : draft = ZapDraftCubit(initial: initial) {
    feed = _InspectablePriceFeed(request: _request);
  }

  final ZapDraftCubit draft;
  final _InspectableVisibility visibility = _InspectableVisibility();
  late final _InspectablePriceFeed feed;
  int requests = 0;
  String answer = _prices;
  Completer<String>? pending;
  bool _setView = false;

  Future<String> _request(Uri url) async {
    requests++;
    final Completer<String>? waiting = pending;
    if (waiting != null) {
      return waiting.future;
    }
    return answer;
  }

  Future<void> show(
    WidgetTester tester, {
    bool active = true,
    bool busy = false,
    bool light = false,
    ThemeData? theme,
    double scale = 1,
    Size size = const Size(1280, 780),
    TextDirection direction = TextDirection.ltr,
    ZapRecipientStatus recipientStatus = ZapRecipientStatus.unavailable,
    ZapDraftCubit? owner,
    PriceFeed? priceFeed,
    BalanceVisibility? balanceVisibility,
  }) async {
    if (!_setView) {
      _setView = true;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
    }
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    await tester.pumpWidget(
      MaterialApp(
        theme: theme ?? (light ? AppTheme.lightTheme : AppTheme.darkTheme),
        locale: const Locale('en'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: appLocalizationsDelegates,
        home: MediaQuery(
          data: MediaQueryData(
            size: size,
            textScaler: TextScaler.linear(scale),
          ),
          child: Directionality(
            textDirection: direction,
            child: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 640,
                  child: SingleChildScrollView(
                    child: ZapForm(
                      draft: owner ?? draft,
                      active: active,
                      busy: busy,
                      priceFeed: priceFeed ?? feed,
                      visibility: balanceVisibility ?? visibility,
                      recipientStatus: recipientStatus,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    await draft.close();
    feed.dispose();
    visibility.dispose();
  }
}

void main() {
  setUp(() => app.sharedPrefsService = null);
  tearDown(() => app.sharedPrefsService = null);

  for (final bool light in <bool>[false, true]) {
    testWidgets('full form has honest unavailable recipients, light $light', (
      WidgetTester tester,
    ) async {
      final _Fixture fixture = _Fixture();
      try {
        await fixture.show(tester, light: light);
        expect(_key('zap_form_ready'), findsOneWidget);
        expect(_key('zap_candidates_unavailable'), findsOneWidget);
        expect(_key('zap_recipient_unavailable'), findsOneWidget);
        expect(_key('zap_candidates_empty'), findsNothing);
        expect(find.textContaining('212'), findsNothing);
        expect(find.textContaining('z1q'), findsNothing);
        expect(_field(tester, 'zap_znn_amount').controller!.text, '1');
        expect(_field(tester, 'zap_qsr_amount').controller!.text, '10');
        expect(_field(tester, 'zap_message').controller!.text, _defaultMessage);
        expect(find.text('40/140'), findsOneWidget);
        expect(find.text('Two blocks, one per coin'), findsOneWidget);
        expect(
          find.text('Zap 1 ZNN + 10 QSR', findRichText: true),
          findsOneWidget,
        );
        expect(find.text(r'≈ $0.9300'), findsOneWidget);
        expect(fixture.requests, 1);
        final Rect znn = tester.getRect(_key('zap_znn_control'));
        final Rect qsr = tester.getRect(_key('zap_qsr_control'));
        expect(znn.top, qsr.top);
        expect(znn.width, qsr.width);
        expect(qsr.left - znn.right, 10);
        expect(
          tester.getSize(_key('zap_message_area')).height,
          greaterThanOrEqualTo(72),
        );
        expect(tester.getSize(_key('zap_submit_button')).height, 46);
        expect(find.byType(SeamGate), findsNWidgets(3));
        expect(find.byType(AlertDialog), findsNothing);
        expect(tester.takeException(), isNull);
      } finally {
        await fixture.close(tester);
      }
    });
  }

  for (final bool light in <bool>[false, true]) {
    testWidgets(
      'Pick another keeps 42 px and its seam in compact density, $light',
      (WidgetTester tester) async {
        final _Fixture fixture = _Fixture();
        final ThemeData theme =
            (light ? AppTheme.lightTheme : AppTheme.darkTheme).copyWith(
              visualDensity: VisualDensity.compact,
            );
        final SemanticsHandle semantics = tester.ensureSemantics();
        try {
          await fixture.show(tester, theme: theme);
          final Finder pick = _key('zap_pick_another');
          final Finder gate = find
              .ancestor(of: pick, matching: find.byType(SeamGate))
              .first;
          final ZapDraft original = fixture.draft.state;
          final VoidCallback refused = tester
              .widget<OutlinedButton>(pick)
              .onPressed!;
          expect(
            Theme.of(tester.element(pick)).visualDensity,
            VisualDensity.compact,
          );
          expect(tester.getSize(pick).height, 42);
          expect(
            tester.getSemantics(gate),
            isSemantics(
              label: 'Not yet',
              hasEnabledState: true,
              isEnabled: false,
            ),
          );
          await tester.ensureVisible(pick);
          await tester.tap(pick, warnIfMissed: false);
          refused();
          await tester.pump();
          expect(fixture.draft.state, original);
          expect(find.byType(AlertDialog), findsNothing);

          await fixture.show(tester, theme: theme, busy: true);
          expect(tester.getSize(pick).height, 42);
          expect(_field(tester, 'zap_znn_amount').readOnly, isTrue);
          refused();
          expect(fixture.draft.state, original);

          await fixture.show(tester, theme: theme, scale: 2.5);
          final Rect bounds = tester.getRect(pick);
          final Rect label = tester.getRect(
            find.descendant(of: pick, matching: find.text('Pick another')),
          );
          expect(bounds.height, greaterThan(42));
          expect(label.top, greaterThanOrEqualTo(bounds.top));
          expect(label.bottom, lessThanOrEqualTo(bounds.bottom));
          await fixture.show(
            tester,
            theme: theme,
            scale: 2.5,
            busy: true,
          );
          expect(tester.getSize(pick).height, greaterThan(42));
          expect(_field(tester, 'zap_znn_amount').readOnly, isTrue);
          expect(fixture.draft.state, original);
          expect(fixture.requests, 1);
          expect(tester.takeException(), isNull);
        } finally {
          await fixture.close(tester);
          semantics.dispose();
        }
      },
    );
  }

  testWidgets('known-empty discovery is separate from unavailable discovery', (
    WidgetTester tester,
  ) async {
    final _Fixture fixture = _Fixture();
    try {
      await fixture.show(tester, recipientStatus: ZapRecipientStatus.empty);
      expect(_key('zap_candidates_empty'), findsOneWidget);
      expect(_key('zap_recipient_empty'), findsOneWidget);
      expect(_key('zap_candidates_unavailable'), findsNothing);
      expect(find.textContaining('found'), findsNothing);
      expect(find.textContaining('z1q'), findsNothing);
      expect(find.byType(SeamGate), findsNWidgets(3));
      await fixture.show(tester);
      expect(_key('zap_candidates_unavailable'), findsOneWidget);
      expect(_key('zap_recipient_empty'), findsNothing);
      expect(fixture.draft.state, const ZapDraft());
    } finally {
      await fixture.close(tester);
    }
  });

  testWidgets(
    'mode, busy and theme changes retain exact editable draft fields',
    (
      WidgetTester tester,
    ) async {
      final _Fixture fixture = _Fixture();
      try {
        await fixture.show(tester);
        final TextEditingController znn = _field(
          tester,
          'zap_znn_amount',
        ).controller!;
        final TextEditingController qsr = _field(
          tester,
          'zap_qsr_amount',
        ).controller!;
        final TextEditingController message = _field(
          tester,
          'zap_message',
        ).controller!;
        await tester.enterText(_key('zap_znn_amount'), '0001.23000000');
        await tester.enterText(_key('zap_qsr_amount'), '0.00000001');
        await tester.enterText(_key('zap_message'), 'A retained € message');
        final ZapDraft retained = fixture.draft.state;
        await fixture.show(tester, busy: true);
        expect(_field(tester, 'zap_znn_amount').readOnly, isTrue);
        expect(_field(tester, 'zap_message').focusNode!.hasFocus, isFalse);
        expect(fixture.draft.state, retained);
        await fixture.show(tester, active: false, light: true);
        expect(find.byType(DollarText), findsNothing);
        expect(_field(tester, 'zap_znn_amount').controller, same(znn));
        expect(_field(tester, 'zap_qsr_amount').controller, same(qsr));
        expect(_field(tester, 'zap_message').controller, same(message));
        await fixture.show(tester, light: true);
        expect(_field(tester, 'zap_znn_amount').readOnly, isFalse);
        expect(znn.text, retained.znn);
        expect(qsr.text, retained.qsr);
        expect(message.text, retained.message);
        await tester.enterText(_key('zap_message'), 'Still editable');
        expect(fixture.draft.state.message, 'Still editable');
        fixture.draft.clear();
        await tester.pump();
        expect(znn.text, '1');
        expect(qsr.text, '10');
        expect(message.text, _defaultMessage);
        expect(find.text('40/140'), findsOneWidget);
      } finally {
        await fixture.close(tester);
      }
    },
  );

  testWidgets(
    'invalid amounts stay visible and never produce a partial total',
    (
      WidgetTester tester,
    ) async {
      final _Fixture fixture = _Fixture();
      try {
        await fixture.show(tester);
        for (final String invalid in <String>[
          '1.000000001',
          '-1',
          '1,5',
          '1e2',
          List<String>.filled(100, '9').join(),
        ]) {
          await tester.enterText(_key('zap_znn_amount'), invalid);
          await tester.pump();
          expect(_field(tester, 'zap_znn_amount').controller!.text, invalid);
          expect(fixture.draft.state.znn, invalid);
          expect(_key('zap_amount_error'), findsOneWidget);
          expect(find.byType(DollarText), findsNothing);
          expect(find.text('Zap', findRichText: true), findsOneWidget);
        }
        await tester.enterText(_key('zap_znn_amount'), '0');
        await tester.enterText(_key('zap_qsr_amount'), '0');
        await tester.pump();
        expect(_key('zap_amount_error'), findsOneWidget);
        expect(find.byType(DollarText), findsNothing);
        await tester.enterText(_key('zap_qsr_amount'), '1.23000000');
        await tester.pump();
        expect(_key('zap_amount_error'), findsNothing);
        expect(find.text('One block'), findsOneWidget);
        expect(find.text('Zap 1.23 QSR', findRichText: true), findsOneWidget);
        expect(find.text(r'≈ $0.0381'), findsOneWidget);
      } finally {
        await fixture.close(tester);
      }
    },
  );

  testWidgets('message counter uses bytes and keeps over-limit edits intact', (
    WidgetTester tester,
  ) async {
    final _Fixture fixture = _Fixture();
    final String euro46 = List<String>.filled(46, '€').join();
    final String euro47 = List<String>.filled(47, '€').join();
    try {
      await fixture.show(tester);
      await tester.enterText(_key('zap_message'), '${euro46}ab');
      await tester.pump();
      expect(find.text('140/140'), findsOneWidget);
      expect(_key('zap_message_error'), findsNothing);
      await tester.enterText(_key('zap_message'), euro47);
      await tester.pump();
      expect(find.text('141/140'), findsOneWidget);
      expect(_key('zap_message_error'), findsOneWidget);
      expect(_field(tester, 'zap_message').controller!.text, euro47);
      expect(fixture.draft.state.message, euro47);
      await tester.enterText(_key('zap_message'), '');
      await tester.pump();
      expect(find.text('0/140'), findsOneWidget);
      expect(_key('zap_message_error'), findsNothing);
      await fixture.show(tester, light: true);
      expect(_field(tester, 'zap_message').controller!.text, isEmpty);
    } finally {
      await fixture.close(tester);
    }
  });

  testWidgets(
    'missing controls refuse pointer, focus, semantics and callbacks',
    (
      WidgetTester tester,
    ) async {
      final _Fixture fixture = _Fixture();
      final SemanticsHandle semantics = tester.ensureSemantics();
      const int mouseDevice = 47;
      bool mouseAdded = false;
      int clipboardWrites = 0;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (MethodCall call) async {
          if (call.method == 'Clipboard.setData') {
            clipboardWrites++;
          }
          return null;
        },
      );
      try {
        await fixture.show(tester);
        final ZapDraft original = fixture.draft.state;
        // MouseTracker is keyed by the event device, not a gesture pointer.
        await tester.sendEventToBinding(
          PointerAddedEvent(
            device: mouseDevice,
            kind: PointerDeviceKind.mouse,
            viewId: tester.view.viewId,
          ),
        );
        mouseAdded = true;
        for (final String key in <String>[
          'zap_copy_recipient',
          'zap_pick_another',
          'zap_submit_button',
        ]) {
          final Finder control = _key(key);
          await tester.ensureVisible(control);
          await tester.pump();
          final Offset position = tester.getCenter(control);
          final Finder gate = find
              .ancestor(
                of: control,
                matching: find.byType(SeamGate),
              )
              .first;
          final Finder region = find
              .descendant(
                of: gate,
                matching: find.byWidgetPredicate(
                  (Widget widget) =>
                      widget is MouseRegion &&
                      widget.cursor == SystemMouseCursors.basic,
                ),
              )
              .first;
          final RenderMouseRegion gateRegion = tester
              .renderObject<RenderMouseRegion>(region);
          final HitTestResult hit = tester.hitTestOnBinding(position);
          expect(
            hit.path.any(
              (HitTestEntry<HitTestTarget> entry) =>
                  identical(entry.target, gateRegion),
            ),
            isTrue,
            reason: '$key must be reached through its rendered seam gate',
          );
          await tester.sendEventToBinding(
            PointerHoverEvent(
              device: mouseDevice,
              kind: PointerDeviceKind.mouse,
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
          await tester.tap(control, warnIfMissed: false);
          final FocusNode focus = Focus.of(tester.element(control))
            ..requestFocus();
          await tester.pump();
          expect(focus.hasFocus, isFalse);
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          await tester.sendKeyEvent(LogicalKeyboardKey.space);
        }
        for (int index = 0; index < 3; index++) {
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
        expect(find.semantics.byLabel('Pick another'), findsNothing);
        tester.widget<IconButton>(_key('zap_copy_recipient')).onPressed!();
        tester.widget<OutlinedButton>(_key('zap_pick_another')).onPressed!();
        tester.widget<PrimaryPill>(_key('zap_submit_button')).onPressed!();
        _field(tester, 'zap_znn_amount').onSubmitted!('999');
        _field(tester, 'zap_message').onSubmitted!('999');
        await tester.pump();
        expect(clipboardWrites, 0);
        expect(fixture.draft.state, original);
        expect(find.byType(AlertDialog), findsNothing);
        expect(tester.takeException(), isNull);
      } finally {
        if (mouseAdded) {
          await tester.sendEventToBinding(
            PointerRemovedEvent(
              device: mouseDevice,
              kind: PointerDeviceKind.mouse,
              viewId: tester.view.viewId,
            ),
          );
        }
        semantics.dispose();
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        );
        await fixture.close(tester);
      }
    },
  );

  testWidgets(
    'keyboard traversal returns after inactive and busy holds',
    (
      WidgetTester tester,
    ) async {
      final _Fixture fixture = _Fixture();
      try {
        await fixture.show(tester, active: false);
        final FocusNode znn = _field(tester, 'zap_znn_amount').focusNode!;
        final FocusNode qsr = _field(tester, 'zap_qsr_amount').focusNode!;
        final FocusNode message = _field(tester, 'zap_message').focusNode!;
        for (final FocusNode field in <FocusNode>[znn, qsr, message]) {
          expect(field.canRequestFocus, isFalse);
          expect(field.skipTraversal, isFalse);
        }
        await fixture.show(tester);
        for (final bool busy in <bool>[true, false]) {
          for (final FocusNode field in <FocusNode>[znn, qsr, message]) {
            expect(field.canRequestFocus, isTrue);
            expect(field.skipTraversal, isFalse);
          }
          znn.requestFocus();
          await tester.pump();
          await tester.sendKeyEvent(LogicalKeyboardKey.tab);
          await tester.pump();
          expect(qsr.hasFocus, isTrue);
          await tester.sendKeyEvent(LogicalKeyboardKey.tab);
          await tester.pump();
          expect(message.hasFocus, isTrue);
          await fixture.show(tester, active: busy, busy: busy);
          expect(message.hasFocus, isFalse);
          message.requestFocus();
          await tester.pump();
          expect(message.hasFocus, isFalse);
          await fixture.show(tester);
        }
        for (final FocusNode field in <FocusNode>[znn, qsr, message]) {
          expect(field.canRequestFocus, isTrue);
          expect(field.skipTraversal, isFalse);
        }
        znn.requestFocus();
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        expect(qsr.hasFocus, isTrue);
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        expect(message.hasFocus, isTrue);
        expect(tester.takeException(), isNull);
      } finally {
        await fixture.close(tester);
      }
    },
  );

  for (final bool light in <bool>[false, true]) {
    testWidgets('RTL and scaled narrow layout keeps money LTR, light $light', (
      WidgetTester tester,
    ) async {
      final _Fixture fixture = _Fixture();
      try {
        await fixture.show(
          tester,
          light: light,
          scale: 2,
          size: const Size(520, 780),
          direction: TextDirection.rtl,
        );
        final TextField znn = _field(tester, 'zap_znn_amount');
        final TextField qsr = _field(tester, 'zap_qsr_amount');
        expect(znn.textDirection, TextDirection.ltr);
        expect(qsr.textDirection, TextDirection.ltr);
        expect(znn.textAlign, TextAlign.right);
        expect(qsr.textAlign, TextAlign.right);
        final Rect znnRect = tester.getRect(_key('zap_znn_control'));
        final Rect qsrRect = tester.getRect(_key('zap_qsr_control'));
        expect(qsrRect.top, greaterThan(znnRect.bottom));
        final Finder counter = _key('zap_message_bytes');
        expect(Directionality.of(tester.element(counter)), TextDirection.ltr);
        expect(tester.takeException(), isNull);
      } finally {
        await fixture.close(tester);
      }
    });
  }

  testWidgets('privacy and the existing dollar setting update the shared sum', (
    WidgetTester tester,
  ) async {
    final _Fixture fixture = _Fixture();
    try {
      await fixture.show(tester);
      fixture.visibility.set(true);
      await tester.pump();
      expect(find.text('≈ ••••'), findsOneWidget);
      expect(find.textContaining(r'$'), findsNothing);
      fixture.feed.enabled = false;
      await tester.pump();
      expect(find.text('≈ ••••'), findsNothing);
      final int requests = fixture.requests;
      await tester.pump(const Duration(minutes: 3));
      expect(fixture.requests, requests);
      fixture.visibility.set(false);
      fixture.feed.enabled = true;
      await tester.pump();
      await tester.pump();
      expect(find.text(r'≈ $0.9300'), findsOneWidget);
    } finally {
      await fixture.close(tester);
    }
  });

  testWidgets(
    'missing prices suppress the whole estimate rather than one coin',
    (
      WidgetTester tester,
    ) async {
      final _Fixture fixture = _Fixture()..answer = '{"zenon-2":{"usd":0.62}}';
      try {
        await fixture.show(tester);
        expect(find.textContaining(r'$'), findsNothing);
        await tester.enterText(_key('zap_qsr_amount'), '0');
        await tester.pump();
        expect(find.text(r'≈ $0.6200'), findsOneWidget);
        expect(find.text('One block'), findsOneWidget);
      } finally {
        await fixture.close(tester);
      }
    },
  );

  testWidgets(
    'inactive retained forms own no price listener or polling timer',
    (
      WidgetTester tester,
    ) async {
      final _Fixture fixture = _Fixture();
      try {
        await fixture.show(tester, active: false);
        expect(fixture.requests, 0);
        expect(fixture.feed.hasActiveListeners, isFalse);
        expect(fixture.visibility.hasActiveListeners, isFalse);
        await fixture.show(tester);
        expect(fixture.requests, 1);
        expect(fixture.feed.hasActiveListeners, isTrue);
        expect(fixture.visibility.hasActiveListeners, isTrue);
        await fixture.show(tester, active: false);
        expect(find.byType(DollarText), findsNothing);
        expect(fixture.feed.hasActiveListeners, isFalse);
        expect(fixture.visibility.hasActiveListeners, isFalse);
        await tester.pump(const Duration(minutes: 3));
        expect(fixture.requests, 1);
      } finally {
        await fixture.close(tester);
      }
    },
  );

  testWidgets('late prices after teardown have no disposed widget listener', (
    WidgetTester tester,
  ) async {
    final _Fixture fixture = _Fixture()..pending = Completer<String>();
    try {
      await fixture.show(tester);
      expect(find.textContaining(r'$'), findsNothing);
      expect(fixture.requests, 1);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      expect(fixture.feed.hasActiveListeners, isFalse);
      expect(fixture.visibility.hasActiveListeners, isFalse);
      fixture.pending!.complete(_prices);
      await tester.pump();
      await tester.pump(const Duration(minutes: 3));
      expect(fixture.requests, 1);
      expect(tester.takeException(), isNull);
    } finally {
      await fixture.close(tester);
    }
  });

  testWidgets(
    'replacing injected owners releases old drafts and feed listeners',
    (WidgetTester tester) async {
      final _Fixture fixture = _Fixture();
      final _Fixture replacement = _Fixture(
        initial: const ZapDraft(znn: '2', qsr: '0', message: 'Replacement'),
      );
      try {
        await fixture.show(tester);
        await fixture.show(
          tester,
          owner: replacement.draft,
          priceFeed: replacement.feed,
          balanceVisibility: replacement.visibility,
        );
        expect(fixture.feed.hasActiveListeners, isFalse);
        expect(replacement.feed.hasActiveListeners, isTrue);
        expect(fixture.visibility.hasActiveListeners, isFalse);
        expect(replacement.visibility.hasActiveListeners, isTrue);
        expect(_field(tester, 'zap_znn_amount').controller!.text, '2');
        fixture.draft.save(znn: '7', qsr: '8', message: 'Old owner');
        await tester.pump();
        expect(_field(tester, 'zap_znn_amount').controller!.text, '2');
        expect(_field(tester, 'zap_message').controller!.text, 'Replacement');
        await tester.enterText(_key('zap_qsr_amount'), '3');
        await tester.pump();
        expect(replacement.draft.state.qsr, '3');
        expect(fixture.draft.state.qsr, '8');
        expect(tester.takeException(), isNull);
      } finally {
        await fixture.close(tester);
        await replacement.draft.close();
        replacement.feed.dispose();
        replacement.visibility.dispose();
      }
    },
  );
}
