import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:zenon_syrius_wallet_flutter/screens/onboarding/import_wallet/import_draft.dart';
import 'package:zenon_syrius_wallet_flutter/screens/onboarding/import_wallet/import_file_offer.dart';

void main() {
  test('content admission has no filename or extension requirement', () {
    final List<String> probed = <String>[];
    final List<ImportFileSelection?> selected = <ImportFileSelection?>[];
    final ImportFileOfferSession session = ImportFileOfferSession(
      pick: () async => null,
      probe: (String path) {
        probed.add(path);
        return true;
      },
      isCurrent: () => true,
      onSelected: selected.add,
      onPickerFailed: () {},
    );
    <String>[
      'fixture.backup',
      'fixture-no-extension',
      'fixture.unrelated',
    ].forEach(session.offer);
    expect(selected.map((ImportFileSelection? value) => value!.path), probed);
    expect(selected, hasLength(3));
    session.refuse();
    expect(selected.last, isNull);
  });

  test(
    'a refusal clears the prior selection and a throwing probe is refused',
    () {
      final List<ImportFileSelection?> selected = <ImportFileSelection?>[];
      ImportFileOfferSession(
          pick: () async => null,
          probe: (String path) {
            if (path == 'fixture-error') {
              throw const FormatException('Synthetic invalid envelope');
            }
            return path == 'fixture-valid';
          },
          isCurrent: () => true,
          onSelected: selected.add,
          onPickerFailed: () {},
        )
        ..offer('fixture-valid')
        ..offer('fixture-invalid')
        ..offer('fixture-error');
      expect(selected.first!.path, 'fixture-valid');
      expect(selected.skip(1), <ImportFileSelection?>[null, null]);
    },
  );

  test(
    'the original picker future is retained and duplicate browse is bounded',
    () async {
      final Completer<String?> picker = Completer<String?>();
      final List<ImportFileSelection?> selected = <ImportFileSelection?>[];
      int picks = 0;
      final ImportFileOfferSession session = ImportFileOfferSession(
        pick: () {
          picks++;
          return picker.future;
        },
        probe: (_) => true,
        isCurrent: () => true,
        onSelected: selected.add,
        onPickerFailed: () {},
      );
      final Future<void> original = session.browse();
      expect(identical(session.browse(), original), isTrue);
      expect(identical(session.originalPicker, picker.future), isTrue);
      picker.complete('fixture.any-name');
      await original;
      expect(picks, 1);
      expect(selected.single!.path, 'fixture.any-name');
    },
  );

  test(
    'a picker result after coverage or replacement never probes or selects',
    () async {
      bool current = true;
      int probes = 0;
      int failures = 0;
      final Completer<String?> picker = Completer<String?>();
      final List<ImportFileSelection?> selected = <ImportFileSelection?>[];
      final ImportFileOfferSession session = ImportFileOfferSession(
        pick: () => picker.future,
        probe: (_) {
          probes++;
          return true;
        },
        isCurrent: () => current,
        onSelected: selected.add,
        onPickerFailed: () => failures++,
      );
      final Future<void> original = session.browse();
      current = false;
      picker.complete('fixture.original');
      await original;
      session.offer('fixture.replacement');
      expect(probes, 0);
      expect(failures, 0);
      expect(selected, isEmpty);
    },
  );

  test(
    'picker cancellation preserves the source and failure is mapped once',
    () async {
      final List<ImportFileSelection?> selected = <ImportFileSelection?>[];
      int failures = 0;
      final ImportFileOfferSession cancelled = ImportFileOfferSession(
        pick: () async => null,
        probe: (_) => true,
        isCurrent: () => true,
        onSelected: selected.add,
        onPickerFailed: () => failures++,
      );
      await cancelled.browse();
      expect(selected, isEmpty);
      expect(failures, 0);
      final ImportFileOfferSession failed = ImportFileOfferSession(
        pick: () async => throw StateError('Synthetic picker failure'),
        probe: (_) => true,
        isCurrent: () => true,
        onSelected: selected.add,
        onPickerFailed: () => failures++,
      );
      await failed.browse();
      expect(selected, isEmpty);
      expect(failures, 1);
    },
  );

  test('ownership lost during probing cannot install the returned path', () {
    bool current = true;
    final List<ImportFileSelection?> selected = <ImportFileSelection?>[];
    ImportFileOfferSession(
      pick: () async => null,
      probe: (_) {
        current = false;
        return true;
      },
      isCurrent: () => current,
      onSelected: selected.add,
      onPickerFailed: () {},
    ).offer('fixture.original');
    expect(selected, isEmpty);
  });
}
