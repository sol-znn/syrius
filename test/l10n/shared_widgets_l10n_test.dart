import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/l10n/app_localizations.dart';
import 'package:zenon_syrius_wallet_flutter/l10n/l10n.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/card_parts/card_parts.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/exceptions/exceptions.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/extensions/buildcontext_extension.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/go_to_palette.dart';
import 'package:zenon_syrius_wallet_flutter/utils/app_theme.dart';
import 'package:zenon_syrius_wallet_flutter/utils/constants.dart';
import 'package:zenon_syrius_wallet_flutter/utils/notifiers/locale_notifier.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/reusable_widgets/buttons/copy_to_clipboard_button.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/reusable_widgets/dialogs.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/reusable_widgets/error_widget.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/reusable_widgets/modals/base_modal.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/reusable_widgets/seed/seed_choice.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/reusable_widgets/select_file_widget.dart';

/// The texts the shared widgets showed before they were moved into
/// `app_en.arb`, written out here so that a change of a single character
/// fails.

/// [child] under the app's localisations, in English.
Widget _app(Widget child) => MaterialApp(
  theme: AppTheme.darkTheme,
  locale: const Locale('en'),
  localizationsDelegates: appLocalizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: Center(child: child)),
);

/// A button that runs [open] with a context under the app.
Widget _opener(Future<void> Function(BuildContext context) open) => Builder(
  builder: (BuildContext context) =>
      TextButton(onPressed: () => open(context), child: const Text('open')),
);

void main() {
  setUp(() {
    // The language of `currentL10n` is the one of the notifier made last.
    LocaleNotifier(AppLanguage.english);
  });

  group('shared widgets, in English', () {
    testWidgets('the copy button says Copy unless it is told otherwise', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(_app(const CopyToClipboardButton('z1qq')));
      expect(find.byTooltip('Copy'), findsOneWidget);

      await tester.pumpWidget(
        _app(const CopyToClipboardButton('z1qq', tooltip: 'Copy SHA-256')),
      );
      expect(find.byTooltip('Copy SHA-256'), findsOneWidget);
      expect(find.byTooltip('Copy'), findsNothing);
    });

    testWidgets('the seed choice names both lengths', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        _app(
          SeedChoice(
            onSeed24Selected: () {},
            onSeed12Selected: () {},
            isSeed12Selected: false,
          ),
        ),
      );
      expect(find.text('24 words'), findsOneWidget);
      expect(find.text('12 words'), findsOneWidget);
    });

    testWidgets('the error line maps a closed client and offers a retry', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        _app(
          SyriusErrorWidget('Bad state: The client is closed', onRetry: () {}),
        ),
      );
      expect(find.text('Not connected to the network'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    });

    testWidgets('a card names what can be spent and a closed client', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        _app(
          Column(
            children: <Widget>[
              CardAvailable(
                amount: BigInt.from(150000000),
                decimals: 8,
                symbol: 'ZNN',
              ),
              CardNote.error(StateError('The client is closed')),
            ],
          ),
        ),
      );
      expect(find.text('AVAILABLE'), findsOneWidget);
      expect(find.text('Not connected to the network'), findsOneWidget);
    });

    testWidgets('the dialogs answer No and Yes, Cancel and OK', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        _app(
          _opener(
            (BuildContext context) => showDialogWithNoAndYesOptions(
              context: context,
              title: 'Send',
              description: 'Send 1 ZNN?',
              isBarrierDismissible: true,
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('No'), findsOneWidget);
      expect(find.text('Yes'), findsOneWidget);
      await tester.tap(find.text('No'));
      await tester.pumpAndSettle();

      await tester.pumpWidget(
        _app(
          _opener(
            (BuildContext context) => showWarningDialog(
              context: context,
              title: 'Careful',
              description: 'This is a warning',
              buttonText: '',
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('OK'), findsOneWidget);
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
    });

    testWidgets('the palette hints Go to unless it is told otherwise', (
      WidgetTester tester,
    ) async {
      const List<GoToEntry<int>> entries = <GoToEntry<int>>[
        GoToEntry<int>(value: 1, label: 'Home'),
      ];
      await tester.pumpWidget(_app(const GoToPalette<int>(entries: entries)));
      expect(find.text('Go to'), findsOneWidget);

      await tester.enterText(find.byKey(const Key('go_to_field')), 'zzz');
      await tester.pump();
      expect(find.text('None yet'), findsOneWidget);

      await tester.pumpWidget(
        _app(const GoToPalette<int>(entries: entries, hintText: 'Jump')),
      );
      await tester.enterText(find.byKey(const Key('go_to_field')), '');
      await tester.pump();
      expect(find.text('Jump'), findsOneWidget);
      expect(find.text('Go to'), findsNothing);
    });

    testWidgets('the file zone and the modal frame', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        _app(SelectFileWidget(onPathFoundCallback: (_) {})),
      );
      expect(find.text('Drop a file here, or click to browse'), findsOneWidget);

      await tester.pumpWidget(
        _app(const BaseModal(title: 'Title', child: SizedBox())),
      );
      expect(find.byTooltip('Close'), findsOneWidget);
    });

    testWidgets('a widget with no delegate above it still has its text', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: const Scaffold(body: CopyToClipboardButton('z1qq')),
        ),
      );
      expect(find.byTooltip('Copy'), findsOneWidget);
    });
  });

  group('shared messages, in English', () {
    late AppLocalizations l10n;

    setUp(() {
      l10n = lookupAppLocalizations(const Locale('en'));
    });

    test('an exception made with no message', () {
      expect(FailureException().message, 'Something went wrong');
      expect(NodeNotSyncedException().message, 'Node is not synced');
      expect(
        NoRewardsLastWeekException().message,
        'No rewards in the last week',
      );
      expect(FailureException(message: 'boom').message, 'boom');
      expect(
        FailureException.fromJson(const <String, dynamic>{}).message,
        'Something went wrong',
      );
      expect(
        FailureException.fromJson(FailureException().toJson()),
        FailureException(),
      );
    });

    test('the closed client outside a widget', () {
      expect(
        cardErrorText(StateError('The client is closed')),
        'Not connected to the network',
      );
      expect(cardErrorText('boom'), 'boom');
    });

    test('an available balance', () {
      expect(l10n.availableBalanceLabel('12.5', 'ZNN'), '12.5 ZNN available');
    });

    test('an address label', () {
      const String label = 'Savings';
      expect(l10n.addressDefaultLabel(1), 'Address 1');
      expect(l10n.settingsAddressLabelEmptyError, "Label can't be empty");
      expect(
        l10n.settingsAddressLabelTooLongNotificationTitle(
          kAddressLabelMaxLength,
        ),
        'The label has more than $kAddressLabelMaxLength characters',
      );
      expect(
        l10n.settingsAddressLabelTooLongNotificationDetails(
          label,
          92,
          kAddressLabelMaxLength,
        ),
        'The label $label is 92 '
        'characters long, which is more than the $kAddressLabelMaxLength '
        'limit.',
      );
      expect(
        l10n.settingsAddressLabelExistsNotificationDetails(label),
        'Label $label already exists in the database',
      );
      expect(
        l10n.settingsAddressLabelExistsNotificationTitle,
        'Label already exists',
      );
      expect(
        l10n.settingsAddressRenameFailedNotificationTitle,
        'Something went wrong while changing the address label',
      );
    });

    test('a node in Settings', () {
      const String node = 'wss://my.znn.node:35998';
      expect(
        l10n.settingsNodeChainIdTooltip(1, 1),
        'Client chain identifier: 1\n'
        'Node chain identifier: 1',
      );
      expect(
        l10n.settingsNodeChainIdMismatchTooltip(1, 3),
        'Chain identifier mismatch\n'
        'Client chain identifier: 1\n'
        'Node chain identifier: 3',
      );
      expect(
        l10n.settingsNodeEmbeddedSyncTooltip,
        'The Embedded Node validates all network transactions\n'
        'It may take several hours to fully sync with the network',
      );
      expect(
        l10n.settingsNodeDeleteConfirm(node),
        'Delete $node from the list of nodes? '
        "This can't be undone.",
      );
      expect(
        l10n.settingsNodeTooLongError(kAddressLabelMaxLength),
        'The node has more than $kAddressLabelMaxLength characters',
      );
      expect(
        l10n.settingsNodeDeleteFailedNotificationTitle(node),
        'Error during deleting node $node from the database',
      );
    });

    testWidgets('context.l10n is the one the delegate gave', (
      WidgetTester tester,
    ) async {
      late AppLocalizations seen;
      late AppLocalizations? given;
      await tester.pumpWidget(
        _app(
          Builder(
            builder: (BuildContext context) {
              seen = context.l10n;
              given = AppLocalizations.of(context);
              return const SizedBox();
            },
          ),
        ),
      );
      expect(given, isNotNull);
      expect(seen, same(given));
    });
  });
}
