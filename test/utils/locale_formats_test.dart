import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/l10n/app_localizations.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/cancel_plasma/view/cancel_countdown.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/stakes/view/stakes_card.dart';
import 'package:zenon_syrius_wallet_flutter/utils/constants.dart';
import 'package:zenon_syrius_wallet_flutter/utils/format_utils.dart';
import 'package:zenon_syrius_wallet_flutter/utils/notifiers/locale_notifier.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/reusable_widgets/accelerator_project_details.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/reusable_widgets/formatted_amount_with_tooltip.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

/// The rule of the wallet's formats: a date, a time ago and a length of time
/// follow the language, with Latin digits; an amount and a string a machine
/// reads are the same in every language.
///
/// The English is written out as the wallet showed it before dates followed
/// the language, so that a change of a single character fails.

const Locale _en = Locale('en');
const Locale _es = Locale('es');
const Locale _ar = Locale('ar');

/// The languages the interface has.
const List<String> _languages = <String>['en', 'zh', 'hi', 'es', 'ar'];

/// An afternoon in August, local time, as the wallet reads a timestamp:
/// August is `ago` in Spanish, which no English month is.
final DateTime _when = DateTime(2026, 8, 13, 14, 5, 9);
final int _at = _when.millisecondsSinceEpoch;

const String _spanishAugust = 'ago';
const String _arabicAugust = 'أغسطس';

/// Every date helper, by name, so that a failure says which one.
final Map<String, String Function(Locale)> _dated =
    <String, String Function(Locale)>{
      'formatDate': (Locale l) => FormatUtils.formatDate(_at, locale: l),
      'formatDateTime': (Locale l) =>
          FormatUtils.formatDateTime(_at, locale: l),
      'formatDateTimeSeconds': (Locale l) =>
          FormatUtils.formatDateTimeSeconds(_at, locale: l),
      'formatDayMonth': (Locale l) =>
          FormatUtils.formatDayMonth(_at, locale: l),
      'formatDayMonthTime': (Locale l) =>
          FormatUtils.formatDayMonthTime(_at, locale: l),
      'formatNotificationStamp': (Locale l) =>
          FormatUtils.formatNotificationStamp(_at, locale: l),
      'formatDeadline': (Locale l) =>
          FormatUtils.formatDeadline(_at, locale: l),
      'formatDateForTable, this year': (Locale l) =>
          FormatUtils.formatDateForTable(
            _at,
            locale: l,
            now: DateTime(2026, 12),
          ),
      'formatDateForTable, another year': (Locale l) =>
          FormatUtils.formatDateForTable(
            _at,
            locale: l,
            now: DateTime(2027, 3),
          ),
    };

final RegExp _anyDigit = RegExp(r'\p{Nd}', unicode: true);
final RegExp _latinDigit = RegExp('[0-9]');

/// Has digits, and none but 0 to 9.
void _expectLatinDigits(String text, {required String reason}) {
  expect(_latinDigit.hasMatch(text), isTrue, reason: '$reason: "$text"');
  expect(
    _anyDigit.hasMatch(text.replaceAll(_latinDigit, '')),
    isFalse,
    reason: '$reason: "$text"',
  );
}

void main() {
  // Each test chooses its language; the next starts from the default.
  tearDown(LocaleNotifier.new);

  group('dates in English read as they did', () {
    test('each helper, to the character', () {
      expect(FormatUtils.formatDate(_at, locale: _en), 'Aug 13, 2026');
      // intl puts a narrow no-break space before AM and PM.
      expect(
        FormatUtils.formatDateTime(_at, locale: _en),
        'Aug 13, 2026 2:05 PM',
      );
      expect(
        FormatUtils.formatDateTimeSeconds(_at, locale: _en),
        'Aug 13, 2026 14:05:09',
      );
      expect(FormatUtils.formatTimeSeconds(_at, locale: _en), '14:05:09');
      expect(FormatUtils.formatDayMonth(_at, locale: _en), '13 Aug');
      expect(
        FormatUtils.formatDayMonthTime(_at, locale: _en),
        '13 Aug 14:05',
      );
      expect(
        FormatUtils.formatNotificationStamp(_at, locale: _en),
        '13 Aug 2026  02:05 PM',
      );
      expect(
        FormatUtils.formatDeadline(_at, locale: _en),
        '2026-08-13 02:05 PM',
      );
    });

    test('each helper gives what its old pattern gave', () {
      // The patterns as they stood at the call sites, with no locale, which
      // is how they were formatted.
      String old(String pattern) => DateFormat(pattern).format(_when);
      expect(
        FormatUtils.formatNotificationStamp(_at, locale: _en),
        '${old('d MMM yyyy')}  ${old('hh:mm aaa')}',
      );
      expect(
        FormatUtils.formatDayMonthTime(_at, locale: _en),
        old('d MMM HH:mm'),
      );
      expect(FormatUtils.formatDayMonth(_at, locale: _en), old('d MMM'));
      expect(FormatUtils.formatTimeSeconds(_at, locale: _en), old('HH:mm:ss'));
      expect(
        FormatUtils.formatDateTimeSeconds(_at, locale: _en),
        old('MMM d, y HH:mm:ss'),
      );
      expect(
        FormatUtils.formatDeadline(_at, locale: _en),
        old('yyyy-MM-dd hh:mm a'),
      );
      expect(
        FormatUtils.formatDateForTable(
          _at,
          locale: _en,
          now: DateTime(2026, 12),
        ),
        old('MMM d'),
      );
      expect(
        FormatUtils.formatDateForTable(
          _at,
          locale: _en,
          now: DateTime(2027, 3),
        ),
        old('MMM d, y'),
      );
    });

    test('the Activity date: ago within a day, the day, then the year', () {
      final DateTime now = DateTime(2026, 8, 13, 19, 5, 9);
      String table(DateTime then) => FormatUtils.formatDateForTable(
        then.millisecondsSinceEpoch,
        locale: _en,
        now: now,
      );
      expect(table(_when), '5 h ago');
      expect(table(DateTime(2026, 8, 13, 18, 53, 9)), '12 min ago');
      expect(table(DateTime(2026, 8, 13, 19, 4, 39)), '30 s ago');
      expect(table(DateTime(2026, 8, 12, 19, 5, 9)), '24 h ago');
      expect(table(DateTime(2026, 8, 12, 19, 5, 8)), 'Aug 12');
      expect(table(DateTime(2025, 3, 4, 9, 7, 3)), 'Mar 4, 2025');
    });

    test('with no locale given, the app language is English', () {
      LocaleNotifier(AppLanguage.english);
      expect(FormatUtils.formatDate(_at), 'Aug 13, 2026');
      expect(
        FormatUtils.formatNotificationStamp(_at),
        '13 Aug 2026  02:05 PM',
      );
    });
  });

  group('dates in Spanish', () {
    for (final MapEntry<String, String Function(Locale)> helper
        in _dated.entries) {
      test('${helper.key} names the month in Spanish, in Latin digits', () {
        final String text = helper.value(_es);
        expect(text, contains(_spanishAugust));
        expect(text, isNot(contains('Aug')));
        _expectLatinDigits(text, reason: helper.key);
      });
    }

    test('the order is that of the language', () {
      expect(FormatUtils.formatDate(_at, locale: _es), '13 ago 2026');
      expect(
        FormatUtils.formatTimeSeconds(_at, locale: _es),
        '14:05:09',
      );
    });
  });

  group('dates in Arabic', () {
    for (final MapEntry<String, String Function(Locale)> helper
        in _dated.entries) {
      test('${helper.key} names the month in Arabic, in Latin digits', () {
        final String text = helper.value(_ar);
        expect(text, contains(_arabicAugust));
        _expectLatinDigits(text, reason: helper.key);
      });
    }

    test('the time is in Latin digits', () {
      final String time = FormatUtils.formatTimeSeconds(_at, locale: _ar);
      expect(time, '14:05:09');
    });

    test('a region does not bring its digits', () {
      // intl's and Flutter's symbols for ar_EG, and Flutter's for ar itself,
      // count in Arabic-Indic digits.
      for (final Locale locale in const <Locale>[
        Locale('ar', 'EG'),
        Locale('ar', 'SA'),
      ]) {
        final String text = FormatUtils.formatDateTime(_at, locale: locale);
        expect(text, contains(_arabicAugust));
        _expectLatinDigits(text, reason: '$locale');
      }
    });

    test('the app language is followed when no locale is given', () {
      LocaleNotifier(AppLanguage.arabic);
      for (final String text in <String>[
        FormatUtils.formatDate(_at),
        FormatUtils.formatDateTime(_at),
        FormatUtils.formatNotificationStamp(_at),
        FormatUtils.formatDayMonthTime(_at),
      ]) {
        expect(text, contains(_arabicAugust));
        _expectLatinDigits(text, reason: 'app language ar');
      }
    });
  });

  test('every language has its dates, in Latin digits', () {
    for (final String code in _languages) {
      for (final MapEntry<String, String Function(Locale)> helper
          in _dated.entries) {
        _expectLatinDigits(
          helper.value(Locale(code)),
          reason: '$code ${helper.key}',
        );
      }
    }
  });

  group('strings a machine reads', () {
    test('are the same under Arabic', () {
      LocaleNotifier(AppLanguage.arabic);
      expect(FormatUtils.fileStamp(_when), '2026-08-13-1405');
      expect(FormatUtils.dayKey(_when), '13 Aug, 2026');
      // And under an Arabic default locale of intl's, which the app never
      // sets.
      Intl.withLocale('ar', () {
        expect(FormatUtils.fileStamp(_when), '2026-08-13-1405');
        expect(FormatUtils.dayKey(_when), '13 Aug, 2026');
      });
    });

    test('are what the old patterns gave', () {
      expect(
        FormatUtils.fileStamp(_when),
        DateFormat('yyyy-MM-dd-HHmm').format(_when),
      );
      expect(
        FormatUtils.dayKey(_when),
        DateFormat('d MMM, yyyy').format(_when),
      );
    });

    test('the day key tells days apart, and nothing finer', () {
      expect(
        FormatUtils.dayKey(DateTime(2026, 8, 13, 0, 0, 1)),
        FormatUtils.dayKey(DateTime(2026, 8, 13, 23, 59, 59)),
      );
      expect(
        FormatUtils.dayKey(DateTime(2026, 8, 13)),
        isNot(FormatUtils.dayKey(DateTime(2026, 8, 14))),
      );
      expect(
        FormatUtils.dayKey(DateTime(2026, 8, 13)),
        isNot(FormatUtils.dayKey(DateTime(2025, 8, 13))),
      );
    });

    test('a fixed pattern given to formatDate stays English', () {
      LocaleNotifier(AppLanguage.arabic);
      expect(
        FormatUtils.formatDate(_at, dateFormat: kDefaultDateTimeFormat),
        '2026-08-13 02:05 PM',
      );
    });
  });

  group('the compact amount', () {
    test('is the English one under every language', () {
      for (final String code in _languages) {
        LocaleNotifier(
          AppLanguage.values.firstWhere(
            (AppLanguage l) => l.locale?.languageCode == code,
          ),
        );
        // A default locale of intl's is what would change an unpinned
        // format. The app sets none; this is the case it is pinned against.
        Intl.withLocale(code, () {
          expect(compactAmount('1234567.89'), '1.23M', reason: code);
          expect(compactAmount('1204.5'), '1.2K', reason: code);
          expect(compactAmount('0.5'), '0.5', reason: code);
          expect(compactAmount('0'), '0', reason: code);
        });
      }
    });

    test('would not be, left to the default locale', () {
      expect(
        Intl.withLocale(
          'es',
          () => NumberFormat.compact().format(1234567.89),
        ),
        isNot('1.23M'),
      );
    });
  });

  group('lengths of time in English', () {
    final AppLocalizations l10n = lookupAppLocalizations(_en);

    test('the largest unit alone', () {
      String coarse(Duration d) => FormatUtils.formatDurationCoarse(l10n, d);
      expect(coarse(const Duration(days: 12, hours: 23)), '12 d');
      expect(coarse(const Duration(hours: 5, minutes: 59)), '5 h');
      expect(coarse(const Duration(minutes: 40, seconds: 59)), '40 min');
      expect(coarse(const Duration(seconds: 30)), '30 s');
      expect(coarse(Duration.zero), '0 s');
      expect(coarse(const Duration(seconds: -5)), '0 s');
    });

    test('the countdown clock', () {
      String clock(Duration d) => FormatUtils.formatCountdownClock(l10n, d);
      expect(
        clock(const Duration(days: 2, hours: 3, minutes: 4, seconds: 5)),
        '2 d 03:04:05',
      );
      expect(
        clock(const Duration(hours: 23, minutes: 59, seconds: 59)),
        '23:59:59',
      );
      expect(clock(const Duration(seconds: 7)), '00:00:07');
      expect(clock(Duration.zero), '00:00:00');
      expect(clock(const Duration(seconds: -5)), '00:00:00');
    });

    test('the sentences a length of time stands in', () {
      expect(l10n.acceleratorClosesIn('12 d'), 'Closes in 12 d');
      expect(l10n.cancelUnlocksIn('9 h 52 m'), 'Unlocks in 9 h 52 m');
      expect(
        l10n.p2pSwapExpiresIn(
          FormatUtils.formatDuration(
            l10n,
            const Duration(minutes: 9, seconds: 58, milliseconds: 400),
          ),
        ),
        'The swap expires in 9 m 58 s',
      );
    });

    test('a stake of one month and of twelve', () {
      expect(stakeDurationText(stakeTimeUnitSec, l10n), '1 month');
      expect(stakeDurationText(12 * stakeTimeUnitSec, l10n), '12 months');
      expect(stakeDurationText(0, l10n), '0 months');
      // With no messages given, the app's.
      LocaleNotifier(AppLanguage.english);
      expect(stakeDurationText(stakeTimeMaxSec), '12 months');
    });
  });

  group('the widgets that word a length of time', () {
    testWidgets('CancelCountdown draws the time left and hands it on', (
      WidgetTester tester,
    ) async {
      const Duration left = Duration(hours: 9, minutes: 52, seconds: 30);
      String? handed;
      await tester.pumpWidget(
        MaterialApp(
          home: Column(
            children: <Widget>[
              CancelCountdown(duration: left, onFinished: () {}),
              CancelCountdown(
                duration: left,
                onFinished: () {},
                builder: (_, String text) {
                  handed = text;
                  return const SizedBox.shrink();
                },
              ),
            ],
          ),
        ),
      );
      expect(find.text('9 h 52 m'), findsOneWidget);
      expect(handed, '9 h 52 m');
      // Unmounted, so that its timer is cancelled.
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('a project shows its creation date and when voting closes', (
      WidgetTester tester,
    ) async {
      LocaleNotifier(AppLanguage.english);
      final int created =
          DateTime.now().millisecondsSinceEpoch ~/ 1000 - 2 * 60 * 60;
      final String createdDate = DateFormat.yMMMd('en').format(
        DateTime.fromMillisecondsSinceEpoch(created * 1000),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: AcceleratorProjectDetails(
            creationTimestamp: created,
            acceleratorProjectStatus: AcceleratorProjectStatus.voting,
          ),
        ),
      );
      final RichText line = tester.widget<RichText>(find.byType(RichText));
      expect(
        line.text.toPlainText(),
        'Created $createdDate · Closes in 13 d',
      );
      expect(
        find.text('Created $createdDate · Closes in 13 d'),
        findsOneWidget,
      );
    });
  });
}
