import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:rxdart/rxdart.dart';
import 'package:zenon_syrius_wallet_flutter/blocs/pow_generating_status_bloc.dart';
import 'package:zenon_syrius_wallet_flutter/l10n/app_localizations.dart';
import 'package:zenon_syrius_wallet_flutter/l10n/l10n.dart';
import 'package:zenon_syrius_wallet_flutter/utils/app_theme.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/reusable_widgets/app_lottie.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/shell/strip/plasma_status.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

Widget _app(Widget child) => MaterialApp(
  theme: AppTheme.darkTheme,
  localizationsDelegates: appLocalizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(
    body: Center(child: SizedBox(width: 700, child: child)),
  ),
);

void main() {
  testWidgets('idle is empty and original 18px bolt repeats only for work', (
    WidgetTester tester,
  ) async {
    final PowGeneratingStatusBloc owner = PowGeneratingStatusBloc();
    final PowWorkToken work = owner.claimWork();
    final StreamController<PowGenerationState> status =
        StreamController<PowGenerationState>.broadcast(sync: true);
    final PlasmaTimes times = PlasmaTimes();
    final DateTime start = tester.binding.clock.now();
    Duration now() => tester.binding.clock.now().difference(start);
    try {
      await tester.pumpWidget(
        _app(
          GenerationStatus(status: status.stream, uptime: now, times: times),
        ),
      );
      expect(find.byKey(const Key('strip_plasma')), findsNothing);
      status.add(PowGenerationState.generating(work));
      await tester.pump();
      final AppLottie bolt = tester.widget<AppLottie>(
        find.byKey(const Key('strip_plasma')),
      );
      expect(bolt.asset, AppLottieAsset.plasmaGeneration);
      expect(bolt.size, 18);
      expect(bolt.repeat, isTrue);
      await tester.pump(const Duration(seconds: 3));
      status.add(PowGenerationState.completed(work));
      await tester.pump();
      expect(find.byKey(const Key('strip_plasma')), findsNothing);
      expect(times.typical, const Duration(seconds: 3));
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await status.close();
      owner.dispose();
    }
  });

  testWidgets(
    'joining running work shows a lower bound without a shortened sample',
    (WidgetTester tester) async {
      final PowGeneratingStatusBloc owner = PowGeneratingStatusBloc();
      final PowWorkToken first = owner.claimWork();
      final BehaviorSubject<PowGenerationState> status =
          BehaviorSubject<PowGenerationState>.seeded(
            PowGenerationState.generating(first),
            sync: true,
          );
      final PlasmaTimes times = PlasmaTimes();
      final DateTime start = tester.binding.clock.now();
      Duration now() => tester.binding.clock.now().difference(start);
      try {
        await tester.pumpWidget(
          _app(
            GenerationStatus(status: status.stream, uptime: now, times: times),
          ),
        );
        await tester.pump();
        expect(
          tester
              .widget<Text>(find.byKey(const Key('strip_plasma_elapsed')))
              .data,
          '≥0 s',
        );
        await tester.pump(const Duration(seconds: 5));
        expect(
          tester
              .widget<Text>(find.byKey(const Key('strip_plasma_elapsed')))
              .data,
          '≥5 s',
        );
        status.add(PowGenerationState.completed(first));
        await tester.pump();
        expect(times.typical, isNull);
        final PowWorkToken second = owner.claimWork();
        status.add(PowGenerationState.generating(second));
        await tester.pump();
        expect(
          tester
              .widget<Text>(find.byKey(const Key('strip_plasma_elapsed')))
              .data,
          '0 s',
        );
        await tester.pump(const Duration(seconds: 2));
        status.add(PowGenerationState.completed(second));
        await tester.pump();
        expect(times.typical, const Duration(seconds: 2));
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await status.close();
        owner.dispose();
      }
    },
  );

  testWidgets(
    'duplicate generating events keep the start and one completed sample',
    (WidgetTester tester) async {
      final PowGeneratingStatusBloc owner = PowGeneratingStatusBloc();
      final PowWorkToken work = owner.claimWork();
      final StreamController<PowGenerationState> status =
          StreamController<PowGenerationState>.broadcast(sync: true);
      final PlasmaTimes times = PlasmaTimes();
      final DateTime start = tester.binding.clock.now();
      Duration now() => tester.binding.clock.now().difference(start);
      try {
        await tester.pumpWidget(
          _app(
            GenerationStatus(status: status.stream, uptime: now, times: times),
          ),
        );
        status.add(PowGenerationState.generating(work));
        await tester.pump(const Duration(seconds: 3));
        status.add(PowGenerationState.generating(work));
        await tester.pump(const Duration(seconds: 2));
        expect(
          tester
              .widget<Text>(find.byKey(const Key('strip_plasma_elapsed')))
              .data,
          '5 s',
        );
        status
          ..add(PowGenerationState.completed(work))
          ..add(PowGenerationState.completed(work));
        await tester.pump();
        expect(times.typical, const Duration(seconds: 5));
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await status.close();
        owner.dispose();
      }
    },
  );

  testWidgets(
    'replacing a stream cancels its timer and ignores its later events',
    (WidgetTester tester) async {
      final PowGeneratingStatusBloc owner = PowGeneratingStatusBloc();
      final PowWorkToken oldWork = owner.claimWork();
      final PowWorkToken currentWork = owner.claimWork();
      final StreamController<PowGenerationState> old =
          StreamController<PowGenerationState>.broadcast(sync: true);
      final StreamController<PowGenerationState> current =
          StreamController<PowGenerationState>.broadcast(sync: true);
      final PlasmaTimes times = PlasmaTimes();
      final DateTime start = tester.binding.clock.now();
      Duration now() => tester.binding.clock.now().difference(start);
      try {
        await tester.pumpWidget(
          _app(GenerationStatus(status: old.stream, uptime: now, times: times)),
        );
        old.add(PowGenerationState.generating(oldWork));
        await tester.pump(const Duration(seconds: 7));
        await tester.pumpWidget(
          _app(
            GenerationStatus(status: current.stream, uptime: now, times: times),
          ),
        );
        expect(find.byKey(const Key('strip_plasma_elapsed')), findsNothing);
        old.add(PowGenerationState.completed(oldWork));
        await tester.pump(const Duration(seconds: 1));
        expect(times.typical, isNull);
        current.add(PowGenerationState.generating(currentWork));
        await tester.pump();
        expect(
          tester
              .widget<Text>(find.byKey(const Key('strip_plasma_elapsed')))
              .data,
          '0 s',
        );
        await tester.pump(const Duration(seconds: 2));
        current.add(PowGenerationState.completed(currentWork));
        await tester.pump();
        expect(times.typical, const Duration(seconds: 2));
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await old.close();
        await current.close();
        owner.dispose();
      }
    },
  );

  testWidgets(
    'errors do not count as completion and a closed source owns no timer',
    (WidgetTester tester) async {
      final PowGeneratingStatusBloc owner = PowGeneratingStatusBloc();
      final PowWorkToken work = owner.claimWork();
      final StreamController<PowGenerationState> status =
          StreamController<PowGenerationState>.broadcast(sync: true);
      final PlasmaTimes times = PlasmaTimes();
      final DateTime start = tester.binding.clock.now();
      Duration now() => tester.binding.clock.now().difference(start);
      try {
        await tester.pumpWidget(
          _app(
            GenerationStatus(status: status.stream, uptime: now, times: times),
          ),
        );
        status.add(PowGenerationState.generating(work));
        await tester.pump(const Duration(seconds: 2));
        status.addError(StateError('status source unavailable'));
        await tester.pump();
        expect(times.typical, isNull);
        expect(find.byKey(const Key('strip_plasma')), findsNothing);
        status.add(PowGenerationState.completed(work));
        await tester.pump();
        expect(times.typical, isNull);
        await status.close();
        await tester.pump();
        expect(find.byKey(const Key('strip_plasma')), findsNothing);
        expect(times.typical, isNull);
        await tester.pump(const Duration(seconds: 10));
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        if (!status.isClosed) await status.close();
        owner.dispose();
      }
    },
  );

  testWidgets('invalidation stops the timer and replays idle after remount', (
    WidgetTester tester,
  ) async {
    final PowGeneratingStatusBloc status = PowGeneratingStatusBloc();
    final PlasmaTimes times = PlasmaTimes();
    final DateTime start = tester.binding.clock.now();
    Duration now() => tester.binding.clock.now().difference(start);
    Widget strip() => _app(
      GenerationStatus(status: status.stream, uptime: now, times: times),
    );
    try {
      await tester.pumpWidget(strip());
      await tester.pump();
      final PowWorkToken old = status.claimWork();
      status.update(old, PowStatus.generating);
      await tester.pump();
      await tester.pump(const Duration(seconds: 7));
      status.invalidate();
      await tester.pump();
      // Async source delivery schedules the removal on the following frame.
      await tester.pump();
      expect(find.byKey(const Key('strip_plasma')), findsNothing);
      expect(times.typical, isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(status.update(old, PowStatus.generating), isFalse);
      await tester.pumpWidget(strip());
      await tester.pump();
      expect(find.byKey(const Key('strip_plasma')), findsNothing);
      final PowWorkToken current = status.claimWork();
      status.update(current, PowStatus.generating);
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
      expect(status.update(old, PowStatus.done), isFalse);
      status.release(old);
      await tester.pump();
      expect(find.byKey(const Key('strip_plasma')), findsOneWidget);
      expect(times.typical, isNull);
      status.update(current, PowStatus.done);
      await tester.pump();
      expect(times.typical, const Duration(seconds: 2));
      await tester.pump();
      expect(find.byKey(const Key('strip_plasma')), findsNothing);
      await tester.pump(const Duration(seconds: 10));
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      status.dispose();
    }
  });

  testWidgets('a stale done cannot finish or time a replacement generation', (
    WidgetTester tester,
  ) async {
    final PowGeneratingStatusBloc owner = PowGeneratingStatusBloc();
    final PowWorkToken old = owner.claimWork();
    final PowWorkToken current = owner.claimWork();
    final StreamController<PowGenerationState> status =
        StreamController<PowGenerationState>.broadcast(sync: true);
    final PlasmaTimes times = PlasmaTimes();
    final DateTime start = tester.binding.clock.now();
    Duration now() => tester.binding.clock.now().difference(start);
    try {
      await tester.pumpWidget(
        _app(
          GenerationStatus(status: status.stream, uptime: now, times: times),
        ),
      );
      status.add(PowGenerationState.generating(old));
      await tester.pump(const Duration(seconds: 7));
      status.add(PowGenerationState.generating(current));
      await tester.pump(const Duration(seconds: 2));
      status.add(PowGenerationState.completed(old));
      await tester.pump();
      expect(find.byKey(const Key('strip_plasma')), findsOneWidget);
      expect(
        tester.widget<Text>(find.byKey(const Key('strip_plasma_elapsed'))).data,
        '2 s',
      );
      expect(times.typical, isNull);
      status.add(PowGenerationState.completed(current));
      await tester.pump();
      expect(times.typical, const Duration(seconds: 2));
      expect(find.byKey(const Key('strip_plasma')), findsNothing);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await status.close();
      owner.dispose();
    }
  });

  test('only positive completed times enter the bounded median', () {
    final PlasmaTimes times = PlasmaTimes()
      ..add(Duration.zero)
      ..add(const Duration(seconds: -1));
    expect(times.typical, isNull);
    times.add(const Duration(milliseconds: 100));
    expect(times.typical, const Duration(milliseconds: 100));
    for (int i = 0; i < PlasmaTimes.kept; i++) {
      times.add(const Duration(seconds: 8));
    }
    expect(times.typical, const Duration(seconds: 8));
  });
}
