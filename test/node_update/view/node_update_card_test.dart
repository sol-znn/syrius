// The Embedded node panel as the person meets it: what it shows on opening,
// the confirmation every install goes through, and the words for a failure.

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/embedded_node/node_archive.dart';
import 'package:zenon_syrius_wallet_flutter/embedded_node/node_library.dart';
import 'package:zenon_syrius_wallet_flutter/embedded_node/node_updater.dart';
import 'package:zenon_syrius_wallet_flutter/l10n/app_localizations.dart';
import 'package:zenon_syrius_wallet_flutter/l10n/l10n.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/node_update/node_update.dart';
import 'package:zenon_syrius_wallet_flutter/utils/app_theme.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/reusable_widgets/modals/modal_chrome.dart';

import '../support.dart';

const ValueKey<String> _check = ValueKey<String>('node_update_check');
const ValueKey<String> _download = ValueKey<String>('node_update_download');
const ValueKey<String> _fromFile = ValueKey<String>(
  'node_update_install_from_file',
);
const ValueKey<String> _useBundled = ValueKey<String>(
  'node_update_use_bundled',
);
const ValueKey<String> _usePrevious = ValueKey<String>(
  'node_update_use_previous',
);
const ValueKey<String> _repository = ValueKey<String>(
  'node_update_repository',
);
const ValueKey<String> _repositorySave = ValueKey<String>(
  'node_update_repository_save',
);
const ValueKey<String> _dialogCancel = ValueKey<String>(
  'node_update_dialog_cancel',
);
const ValueKey<String> _dialogInstall = ValueKey<String>(
  'node_update_dialog_install',
);
const ValueKey<String> _unverifiedCancel = ValueKey<String>(
  'node_update_unverified_cancel',
);
const ValueKey<String> _unverifiedDownload = ValueKey<String>(
  'node_update_unverified_download',
);
const ValueKey<String> _bundledCancel = ValueKey<String>(
  'node_update_bundled_cancel',
);
const ValueKey<String> _bundledConfirm = ValueKey<String>(
  'node_update_bundled_confirm',
);

const String _matchesChecksumFile = "Matches the release's checksum file";
const String _noChecksumFile = 'The release has no checksum file';
const String _noDigest = 'GitHub gives no digest for this release';
const String _fileUnchecked = 'Not checked: a file from this computer';
const String _replaces =
    'This replaces the node that runs inside the wallet. '
    'It takes effect at the next start.';

Finder _inDialog(Finder matching) =>
    find.descendant(of: find.byType(DialogCard), matching: matching);

/// Whether the keyboard focus is on the control with [key].
bool _focused(WidgetTester tester, Key key) {
  final BuildContext? focus = FocusManager.instance.primaryFocus?.context;
  if (focus == null) {
    return false;
  }
  final Element control = tester.element(find.byKey(key));
  bool inside = false;
  focus.visitAncestorElements((Element ancestor) {
    inside = ancestor == control;
    return !inside;
  });
  return inside;
}

bool _enabled(WidgetTester tester, Key key) =>
    tester.widget<ButtonStyleButton>(find.byKey(key)).onPressed != null;

double _buttonHeight(WidgetTester tester, Key key) => tester
    .getSize(
      find.descendant(
        of: find.byKey(key),
        matching: find.byType(Material),
      ),
    )
    .height;

Color? _inkOf(WidgetTester tester, String text) =>
    tester.widget<Text>(find.text(text)).style?.color;

void main() {
  late FakeNodeLibrary library;
  late FakeNodeUpdater updater;
  late List<String> asked;
  late List<String> saved;
  String? picked;

  Future<void> open(
    WidgetTester tester, {
    Size size = const Size(1200, 1000),
    Locale locale = const Locale('en'),
    ThemeData? theme,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: theme ?? AppTheme.darkTheme,
        locale: locale,
        localizationsDelegates: appLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SingleChildScrollView(
            child: NodeUpdateCard(
              library: library,
              repository: kRepo,
              updaterFor: (NodeUpdateSource source) {
                asked.add(source.repository);
                return updater;
              },
              saveRepository: (String repository) async =>
                  saved.add(repository),
              pickFile: () async => picked,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> press(WidgetTester tester, Key key) async {
    await tester.tap(find.byKey(key));
    await tester.pumpAndSettle();
  }

  setUp(() {
    library = FakeNodeLibrary();
    updater = FakeNodeUpdater(library)..latest = releaseOf();
    asked = <String>[];
    saved = <String>[];
    picked = null;
  });

  for (final bool light in <bool>[false, true]) {
    testWidgets(
      'update row and dialog pairs keep their roles, light $light',
      (WidgetTester tester) async {
        updater.downloads.add(downloadedOf());
        await open(
          tester,
          theme: (light ? AppTheme.lightTheme : AppTheme.darkTheme).copyWith(
            visualDensity: VisualDensity.compact,
            materialTapTargetSize: MaterialTapTargetSize.padded,
          ),
        );
        expect(_buttonHeight(tester, _fromFile), 30);
        expect(_buttonHeight(tester, _download), 30);
        await press(tester, _check);
        await press(tester, _download);
        expect(_buttonHeight(tester, _dialogCancel), 38);
        expect(_buttonHeight(tester, _dialogInstall), 38);
        expect(_focused(tester, _dialogCancel), isTrue);
        expect(updater.calls, isNot(contains('stage $kNewSha')));
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        expect(find.byType(DialogCard), findsNothing);
        expect(updater.calls, <String>[
          'latestRelease $kRepo',
          'download $kTag allowUnverified=false',
          'discard $kNewSha',
        ]);
      },
      timeout: const Timeout(Duration(seconds: 20)),
    );
  }

  group('on opening', () {
    testWidgets('shows what is loaded and asks the network nothing', (
      WidgetTester tester,
    ) async {
      await open(tester);

      expect(find.text('Embedded node'), findsOneWidget);
      expect(find.text('Loaded'), findsOneWidget);
      expect(find.text('Bundled'), findsOneWidget);
      // Cut in the middle on the row, whole in the tooltip.
      expect(find.text('1111111111…cccccc4444'), findsOneWidget);
      expect(find.byTooltip(kBundledSha), findsOneWidget);
      expect(find.byTooltip('Copy SHA-256'), findsOneWidget);
      expect(find.text('Not checked'), findsOneWidget);

      expect(asked, isEmpty, reason: 'no updater was made');
      expect(updater.calls, isEmpty);
      expect(_enabled(tester, _download), isFalse);
      // Nothing is installed, so there is nothing to roll back.
      expect(find.byKey(_useBundled), findsNothing);
      expect(find.byKey(_usePrevious), findsNothing);
      expect(find.byType(DialogCard), findsNothing);
    });

    testWidgets('names an override by its tag and repository', (
      WidgetTester tester,
    ) async {
      const String fork = 'someone/go-zenon';
      final NodeLibraryManifest running = manifestOf(
        source: fork,
        tag: 'v0.0.8',
        sha256: kOldSha,
      );
      library.current = statusOf(
        loadedOverride: running,
        installed: running,
        staged: manifestOf(),
      );
      await open(tester);

      expect(find.text('v0.0.8'), findsOneWidget);
      expect(find.text(fork), findsOneWidget);
      expect(find.byTooltip(kOldSha), findsOneWidget);
      // No way to restart from inside the wallet, so no button: a line.
      const String reopen = 'Close and reopen Syrius to use v0.0.9.';
      expect(find.text(reopen), findsOneWidget);
      expect(_inkOf(tester, reopen), AppTokens.dark.warn);
      expect(find.byKey(_useBundled), findsOneWidget);
    });

    testWidgets('says when the installed override failed to load', (
      WidgetTester tester,
    ) async {
      library.current = statusOf(
        installed: manifestOf(),
        bad: NodeLibraryBadMarker(
          sha256: kNewSha,
          reason: 'failed to load: Invalid argument(s)',
          at: DateTime.utc(2026, 10, 12),
        ),
      );
      await open(tester);

      const String failed =
          'The installed node failed to load. The bundled one is in use.';
      expect(find.text(failed), findsOneWidget);
      expect(_inkOf(tester, failed), AppTokens.dark.warn);
      expect(find.textContaining('Invalid argument'), findsNothing);
      expect(find.text('Bundled'), findsOneWidget);
    });

    // An overflow is an error in a test, so reaching the end is the check.
    testWidgets('fits a panel narrower than the window allows, every row in', (
      WidgetTester tester,
    ) async {
      library.current = statusOf(
        loadedOverride: manifestOf(),
        installed: manifestOf(),
        staged: manifestOf(tag: 'v0.1.0-rc.1', sha256: kOldSha),
        previous: manifestOf(tag: 'v0.0.8', sha256: kOldSha),
      );
      await open(tester, size: const Size(700, 1000));
      await press(tester, _check);

      expect(find.byKey(_usePrevious), findsOneWidget);
      expect(find.byKey(_useBundled), findsOneWidget);
      expect(find.text('Up to date'), findsOneWidget);
    });

    testWidgets('keeps hashes and names left to right in Arabic', (
      WidgetTester tester,
    ) async {
      updater.downloads.add(downloadedOf());
      await open(tester, locale: const Locale('ar'));
      expect(
        Directionality.of(tester.element(find.byKey(_check))),
        TextDirection.rtl,
      );
      expect(
        tester.widget<Text>(find.text('1111111111…cccccc4444')).textDirection,
        TextDirection.ltr,
      );
      expect(
        tester.widget<TextField>(find.byKey(_repository)).textDirection,
        TextDirection.ltr,
      );

      await press(tester, _check);
      await press(tester, _download);
      for (final String data in <String>[kRepo, kTag, kAsset, kNewSha]) {
        expect(
          tester.widget<Text>(_inDialog(find.text(data))).textDirection,
          TextDirection.ltr,
          reason: data,
        );
      }
    });
  });

  group('Check', () {
    testWidgets('shows the tag, its date and how it compares', (
      WidgetTester tester,
    ) async {
      await open(tester);
      await press(tester, _check);

      expect(updater.calls, <String>['latestRelease $kRepo']);
      expect(find.text(kTag), findsOneWidget);
      final String date = MaterialLocalizations.of(
        tester.element(find.byKey(_check)),
      ).formatShortDate(releaseOf().publishedAt!.toLocal());
      expect(date, contains('2026'));
      expect(find.text(date), findsOneWidget);
      expect(find.text('Not compared'), findsOneWidget);
      expect(_enabled(tester, _download), isTrue);
      // Found, not fetched.
      expect(find.byType(DialogCard), findsNothing);
    });

    testWidgets('a release with no library for this platform says so', (
      WidgetTester tester,
    ) async {
      updater.latest = releaseOf(withAsset: false);
      await open(tester);
      await press(tester, _check);

      expect(
        find.text('Release $kTag has no library for this platform.'),
        findsOneWidget,
      );
      expect(_enabled(tester, _download), isFalse);
    });
  });

  group('the confirmation', () {
    testWidgets(
      'shows the whole sha256 and both checks, and Cancel is the default',
      (WidgetTester tester) async {
        updater.downloads.add(downloadedOf());
        await open(tester);
        await press(tester, _check);
        await press(tester, _download);

        expect(find.byType(DialogCard), findsOneWidget);
        expect(_inDialog(find.text(kRepo)), findsOneWidget);
        expect(_inDialog(find.text(kTag)), findsOneWidget);
        expect(_inDialog(find.text(kAsset)), findsOneWidget);
        expect(_inDialog(find.text(kNewSha)), findsOneWidget);
        expect(_inDialog(find.text(_matchesChecksumFile)), findsOneWidget);
        expect(_inDialog(find.text(_noDigest)), findsOneWidget);
        expect(_inkOf(tester, _matchesChecksumFile), AppTokens.dark.znnInk);
        expect(_inkOf(tester, _noDigest), AppTokens.dark.warn);
        expect(_inDialog(find.text(_replaces)), findsOneWidget);
        // Every line can be selected and copied.
        expect(_inDialog(find.byType(SelectionArea)), findsOneWidget);

        expect(_focused(tester, _dialogCancel), isTrue);
        expect(_focused(tester, _dialogInstall), isFalse);
        expect(updater.calls, isNot(contains('stage $kNewSha')));

        // Enter goes to the focused button: it backs out.
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();

        expect(find.byType(DialogCard), findsNothing);
        expect(updater.calls.last, 'discard $kNewSha');
        expect(updater.calls, isNot(contains('stage $kNewSha')));
      },
    );

    testWidgets('Install stages it and says to reopen the wallet', (
      WidgetTester tester,
    ) async {
      updater.downloads.add(downloadedOf());
      await open(tester);
      await press(tester, _check);
      await press(tester, _download);
      await press(tester, _dialogInstall);

      expect(find.byType(DialogCard), findsNothing);
      expect(updater.calls, <String>[
        'latestRelease $kRepo',
        'download $kTag allowUnverified=false',
        'stage $kNewSha',
      ]);
      expect(
        find.text('Close and reopen Syrius to use $kTag.'),
        findsOneWidget,
      );
      expect(find.text('Staged for the next start'), findsOneWidget);
      expect(find.text('Restart'), findsNothing);
      // The running node is still the bundled one.
      expect(find.text('Bundled'), findsOneWidget);
    });

    testWidgets('closing it any other way deletes the download', (
      WidgetTester tester,
    ) async {
      updater.downloads.add(downloadedOf());
      await open(tester);
      await press(tester, _check);
      await press(tester, _download);

      await tester.tapAt(const Offset(4, 4));
      await tester.pumpAndSettle();

      expect(find.byType(DialogCard), findsNothing);
      expect(updater.calls.last, 'discard $kNewSha');
    });

    testWidgets('of a file reads both checks as not made', (
      WidgetTester tester,
    ) async {
      picked = 'C:/fixtures/libznn.dll';
      updater.picked = pickedOf();
      await open(tester);
      await press(tester, _fromFile);

      expect(updater.calls, <String>['fromFile libznn.dll']);
      expect(find.byType(DialogCard), findsOneWidget);
      expect(_inDialog(find.text(_fileUnchecked)), findsNWidgets(2));
      // No repository and no tag vouch for it.
      expect(_inDialog(find.text('None')), findsNWidgets(2));
      expect(_inDialog(find.text('libznn.dll')), findsOneWidget);
      expect(_inDialog(find.text(kNewSha)), findsOneWidget);
      expect(_inDialog(find.text(_replaces)), findsOneWidget);
      expect(_focused(tester, _dialogCancel), isTrue);

      await press(tester, _dialogCancel);
      expect(updater.calls.last, 'discard $kNewSha');
    });

    testWidgets('backing out of the file dialog asks for nothing', (
      WidgetTester tester,
    ) async {
      await open(tester);
      await press(tester, _fromFile);

      expect(asked, isEmpty);
      expect(find.byType(DialogCard), findsNothing);
    });
  });

  group('a release that publishes no hash', () {
    setUp(() {
      updater.downloads.addAll(<Object>[
        const NodeUpdateUnverified(
          checksumFile: NodeChecksumFileCheck.absentFromRelease,
        ),
        downloadedOf(checksumFile: NodeChecksumFileCheck.absentFromRelease),
      ]);
    });

    testWidgets('asks first, in the warning tone, with Cancel the default', (
      WidgetTester tester,
    ) async {
      await open(tester);
      await press(tester, _check);
      await press(tester, _download);

      const String nothing =
          'Nothing verifies this file. '
          'Release $kTag publishes no checksum for it.';
      expect(find.text('Download without verification?'), findsOneWidget);
      expect(_inDialog(find.text(nothing)), findsOneWidget);
      expect(_inkOf(tester, nothing), AppTokens.dark.warn);
      expect(_focused(tester, _unverifiedCancel), isTrue);
      expect(_buttonHeight(tester, _unverifiedCancel), 38);
      expect(_buttonHeight(tester, _unverifiedDownload), 38);
      final ButtonStyle warning = tester
          .widget<OutlinedButton>(find.byKey(_unverifiedDownload))
          .style!;
      expect(
        warning.side!.resolve(<WidgetState>{})!.color,
        AppTokens.dark.warn,
      );
      expect(find.byKey(_dialogInstall), findsNothing);

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(find.byType(DialogCard), findsNothing);
      expect(updater.calls, <String>[
        'latestRelease $kRepo',
        'download $kTag allowUnverified=false',
      ]);
    });

    testWidgets('is downloaded after a yes, then confirmed like any other', (
      WidgetTester tester,
    ) async {
      await open(tester);
      await press(tester, _check);
      await press(tester, _download);
      await press(tester, _unverifiedDownload);

      // The second question: the install itself.
      expect(find.byKey(_unverifiedDownload), findsNothing);
      expect(_inDialog(find.text(kNewSha)), findsOneWidget);
      expect(_inDialog(find.text(_noChecksumFile)), findsOneWidget);
      expect(_inDialog(find.text(_noDigest)), findsOneWidget);
      expect(_inkOf(tester, _noChecksumFile), AppTokens.dark.warn);
      expect(_focused(tester, _dialogCancel), isTrue);
      expect(updater.calls, <String>[
        'latestRelease $kRepo',
        'download $kTag allowUnverified=false',
        'download $kTag allowUnverified=true',
      ]);

      await press(tester, _dialogInstall);
      expect(updater.calls.last, 'stage $kNewSha');
    });
  });

  group('a failure reads as a sentence, never as the exception', () {
    final List<(NodeUpdateException, String)> onCheck =
        <(NodeUpdateException, String)>[
          (
            const NodeUpdateRateLimited(),
            'GitHub is limiting requests from this computer. Try again later.',
          ),
          (
            const NodeUpdateNetworkError('errno 11001'),
            'No connection to GitHub.',
          ),
          (
            const NodeUpdateHttpError(404),
            'GitHub has no such repository or file.',
          ),
          (
            const NodeUpdateHttpError(503),
            'GitHub answered with error 503.',
          ),
          (
            const NodeUpdateMalformedResponse('not JSON'),
            "GitHub's answer could not be read.",
          ),
        ];
    final List<(NodeUpdateException, String)> onDownload =
        <(NodeUpdateException, String)>[
          (
            const NodeUpdateNoAsset(kTag),
            'Release $kTag has no library for this platform.',
          ),
          (
            const NodeUpdateTooLarge(NodeUpdater.defaultMaxBytes),
            'The file is over 200 MB.',
          ),
          (
            NodeUpdateArchiveError(NodeArchiveProblem.corrupt, 'bad crc'),
            'This is not a libznn library.',
          ),
          (
            const NodeUpdateSizeMismatch(expected: 100, actual: 60),
            'The download was incomplete.',
          ),
          (
            const NodeUpdateFileError('errno 28'),
            'The file could not be read or written.',
          ),
        ];

    for (final (NodeUpdateException error, String sentence) in onCheck) {
      testWidgets('${error.runtimeType}: $sentence', (
        WidgetTester tester,
      ) async {
        updater.latest = error;
        await open(tester);
        await press(tester, _check);

        expect(find.text(sentence), findsOneWidget);
        expect(find.textContaining(error.detail), findsNothing);
        expect(find.textContaining('Exception'), findsNothing);
        expect(_enabled(tester, _check), isTrue);
      });
    }

    for (final (NodeUpdateException error, String sentence) in onDownload) {
      testWidgets('${error.runtimeType}: $sentence', (
        WidgetTester tester,
      ) async {
        updater.downloads.add(error);
        await open(tester);
        await press(tester, _check);
        await press(tester, _download);

        expect(find.text(sentence), findsOneWidget);
        expect(find.textContaining(error.detail), findsNothing);
        expect(find.textContaining('Exception'), findsNothing);
        expect(find.byType(DialogCard), findsNothing);
      });
    }

    testWidgets('a rate limit names the time it ends', (
      WidgetTester tester,
    ) async {
      updater.latest = NodeUpdateRateLimited(
        resetAt: DateTime.utc(2026, 10, 13, 12, 30),
      );
      await open(tester);
      await press(tester, _check);

      // The local time of day, as the locale writes it.
      final String time = DateFormat.jm(
        'en',
      ).format(DateTime.utc(2026, 10, 13, 12, 30).toLocal());
      expect(
        find.text(
          'GitHub is limiting requests from this computer. '
          'Try again after $time.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('a checksum mismatch shows both values', (
      WidgetTester tester,
    ) async {
      updater.downloads.add(
        const NodeUpdateDigestMismatch(
          check: NodeDigestSource.checksumFile,
          expected: kNewSha,
          actual: kOldSha,
        ),
      );
      await open(tester);
      await press(tester, _check);
      await press(tester, _download);

      expect(
        find.text(
          'The download does not match the published checksum and was '
          'deleted.',
        ),
        findsOneWidget,
      );
      expect(find.text('PUBLISHED'), findsOneWidget);
      expect(find.text(kNewSha), findsOneWidget);
      expect(find.text('DOWNLOADED'), findsOneWidget);
      expect(find.text(kOldSha), findsOneWidget);
      expect(find.byType(DialogCard), findsNothing);
      expect(updater.calls, isNot(contains('stage $kNewSha')));
    });
  });

  group('roll back', () {
    testWidgets('Use bundled node names what goes, then removes it', (
      WidgetTester tester,
    ) async {
      library
        ..current = statusOf(
          loadedOverride: manifestOf(),
          installed: manifestOf(),
        )
        ..afterRollback = statusOf(loadedOverride: manifestOf());
      await open(tester);
      expect(find.text('Applies at the next start'), findsOneWidget);
      await press(tester, _useBundled);

      expect(find.text('Use the bundled node?'), findsOneWidget);
      expect(_inDialog(find.text('$kTag  $kRepo')), findsOneWidget);
      expect(_focused(tester, _bundledCancel), isTrue);
      expect(library.calls, isEmpty);

      await press(tester, _bundledConfirm);

      expect(library.calls, <String>['rollback']);
      expect(
        find.text('Close and reopen Syrius to use the bundled node.'),
        findsOneWidget,
      );
      expect(find.byKey(_useBundled), findsNothing);
    });

    testWidgets('Cancel leaves the override where it is', (
      WidgetTester tester,
    ) async {
      library.current = statusOf(installed: manifestOf());
      await open(tester);
      await press(tester, _useBundled);
      await press(tester, _bundledCancel);

      expect(library.calls, isEmpty);
      expect(find.byKey(_useBundled), findsOneWidget);
    });

    testWidgets('Use previous is offered when there is one', (
      WidgetTester tester,
    ) async {
      library.current = statusOf(
        installed: manifestOf(),
        previous: manifestOf(tag: 'v0.0.8', sha256: kOldSha),
      );
      await open(tester);
      await press(tester, _usePrevious);

      expect(find.text('Use the previous node?'), findsOneWidget);
      expect(_inDialog(find.text('v0.0.8')), findsOneWidget);
      expect(_inDialog(find.text(kOldSha)), findsOneWidget);
      expect(
        _focused(
          tester,
          const ValueKey<String>('node_update_previous_cancel'),
        ),
        isTrue,
      );

      await press(
        tester,
        const ValueKey<String>('node_update_previous_confirm'),
      );
      expect(library.calls, <String>['restorePrevious']);
    });
  });

  group('the source repository', () {
    const String foreign =
        "Libraries from another repository are not the Zenon project's.";

    testWidgets('starts on the default, with no warning', (
      WidgetTester tester,
    ) async {
      await open(tester);

      expect(
        tester.widget<TextField>(find.byKey(_repository)).controller!.text,
        kRepo,
      );
      expect(find.text(foreign), findsNothing);
      expect(_enabled(tester, _repositorySave), isFalse);
    });

    testWidgets('warns about another one, saves it, and Check reads it', (
      WidgetTester tester,
    ) async {
      await open(tester);
      await tester.enterText(find.byKey(_repository), 'someone/go-zenon');
      await tester.pumpAndSettle();

      expect(find.text(foreign), findsOneWidget);
      expect(_inkOf(tester, foreign), AppTokens.dark.warn);
      expect(saved, isEmpty);

      await press(tester, _repositorySave);
      expect(saved, <String>['someone/go-zenon']);
      expect(_enabled(tester, _repositorySave), isFalse);

      await press(tester, _check);
      expect(asked, <String>['someone/go-zenon']);
    });

    testWidgets('refuses what is not owner/name', (WidgetTester tester) async {
      await open(tester);
      await tester.enterText(
        find.byKey(_repository),
        'https://github.com/someone/go-zenon',
      );
      await tester.pumpAndSettle();

      expect(find.text('Enter a repository as owner/name.'), findsOneWidget);
      expect(_enabled(tester, _repositorySave), isFalse);
      expect(saved, isEmpty);
    });
  });
}
