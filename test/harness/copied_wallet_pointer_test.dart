import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:path/path.dart' as p;

import '../../harness/bin/copied_wallet_pointer.dart';

String _name(String digit) =>
    'ci-wallet-${List<String>.filled(24, digit).join()}';

class _Copy {
  _Copy(this.root, this.original, this.restored, this.cacheRelative,
      this.originalWallet, this.copiedWallet, this.originalPointer,
      this.copiedPointer, this.other);

  final Directory root;
  final String original;
  final String restored;
  final String cacheRelative;
  final File originalWallet;
  final File copiedWallet;
  final File originalPointer;
  final File copiedPointer;
  final File other;

  String get cache => p.join(restored, cacheRelative);

  Future<void> dispose() async {
    for (final String name in <String>[
      copiedWalletPointerBox, 'pointer_fixture_other',
    ]) {
      if (Hive.isBoxOpen(name)) {
        final Box<dynamic> box = Hive.box<dynamic>(name);
        if (box.path != null && p.isWithin(root.path, box.path!)) {
          await box.close();
        }
      }
    }
    await root.delete(recursive: true);
  }
}

Future<_Copy> _copy({bool extra = false}) async {
  if (Hive.isBoxOpen(copiedWalletPointerBox) ||
      Hive.isBoxOpen('pointer_fixture_other')) {
    throw StateError('fixture backend already owned');
  }
  final Directory root = await Directory.systemTemp
      .createTemp('syrius-pointer-binding-regression-');
  final String parent = p.join(root.path, '.harness');
  final String original = p.join(parent, _name('1'));
  final String restored = p.join(parent, _name('2'));
  final String relative = p.join('AppData', 'Roaming', 'fixture', 'cache');
  final String originalCache = p.join(original, relative);
  final String copiedCache = p.join(restored, relative);
  await Directory(originalCache).create(recursive: true);
  await Directory(copiedCache).create(recursive: true);
  final File oldWallet = File(p.join(original, 'wallet', 'fixture.json'));
  final File newWallet = File(p.join(restored, 'wallet', 'fixture.json'));
  await oldWallet.parent.create(recursive: true);
  await newWallet.parent.create(recursive: true);
  await oldWallet.writeAsString('synthetic cipher bytes');
  await oldWallet.copy(newWallet.path);
  final Box<dynamic> pointer = await Hive.openBox<dynamic>(
    copiedWalletPointerBox, path: originalCache, crashRecovery: false,
  );
  await pointer.put(0, oldWallet.path);
  if (extra) await pointer.put(1, 'held fixture');
  await pointer.close();
  final File originalPointer = File(p.join(
    originalCache, '$copiedWalletPointerBox.hive',
  ));
  final File copiedPointer = await originalPointer.copy(p.join(
    copiedCache, '$copiedWalletPointerBox.hive',
  ));
  final Box<dynamic> other = await Hive.openBox<dynamic>(
    'pointer_fixture_other', path: copiedCache,
  );
  await other.put(0, 'untouched fixture');
  final File otherFile = File(other.path!);
  await other.close();
  return _Copy(root, original, restored, relative, oldWallet, newWallet,
    originalPointer, copiedPointer, otherFile);
}

void main() {
  test('mapping retains the exact relative wallet in both path styles', () {
    for (final p.Style style in <p.Style>[p.Style.posix, p.Style.windows]) {
      final p.Context paths = p.Context(style: style);
      final String base = paths.join(
        style == p.Style.windows ? 'C:/' : '/', 'fixture', '.harness',
      );
      final String original = paths.join(base, _name('1'));
      final String restored = paths.join(base, _name('2'));
      expect(mapCopiedWalletPath(originalHome: original,
        restoredHome: restored, savedPath: paths.join(original, 'wallet', 'a'),
        context: paths),
        paths.normalize(paths.join(restored, 'wallet', 'a')));
    }
  });

  test('mapping refuses the original, default and foreign restore homes', () {
    final String base = p.join(Directory.systemTemp.path, '.harness');
    final String original = p.join(base, _name('1'));
    for (final String restored in <String>[
      original, p.join(base, 'default'),
      p.join(base, 'nested', _name('2')),
    ]) {
      expect(() => mapCopiedWalletPath(originalHome: original,
        restoredHome: restored, savedPath: p.join(original, 'wallet', 'a')),
        throwsA(isA<CopiedWalletPointerRefused>()));
    }
  });

  test('mapping refuses relative, escaped, foreign and malformed pointers', () {
    final String base = p.join(Directory.systemTemp.path, '.harness');
    final String original = p.join(base, _name('1'));
    final String restored = p.join(base, _name('2'));
    for (final String saved in <String>[
      'relative', p.join(base, 'foreign'), p.join(restored, 'wallet', 'a'),
      '$original${p.separator}wallet${p.separator}..${p.separator}a',
      '$original\u0000',
    ]) {
      expect(() => mapCopiedWalletPath(originalHome: original,
        restoredHome: restored, savedPath: saved),
        throwsA(isA<CopiedWalletPointerRefused>()));
    }
  });

  test('actual Hive binding changes only its copied pointer and keeps bytes',
      () async {
    final _Copy fixture = await _copy();
    try {
      final List<int> source = await fixture.originalPointer.readAsBytes();
      final List<int> encrypted = await fixture.copiedWallet.readAsBytes();
      final List<int> other = await fixture.other.readAsBytes();
      int claims = 0;
      final String rebound = await bindCopiedWalletPointer(hive: Hive,
        originalHome: fixture.original, restoredHome: fixture.restored,
        originalWallet: fixture.originalWallet.path,
        cacheRelative: fixture.cacheRelative, closed: () => true,
        claim: () async { claims++; });
      expect(rebound, fixture.copiedWallet.path);
      expect(claims, 1);
      expect(Hive.isBoxOpen(copiedWalletPointerBox), isFalse);
      expect(await fixture.originalPointer.readAsBytes(), source);
      expect(await fixture.copiedWallet.readAsBytes(), encrypted);
      expect(await fixture.originalWallet.readAsBytes(), encrypted);
      expect(await fixture.other.readAsBytes(), other);
      final Box<dynamic> box = await Hive.openBox<dynamic>(
        copiedWalletPointerBox, path: fixture.cache, crashRecovery: false,
      );
      expect(box.toMap(), <int, String>{0: fixture.copiedWallet.path});
      await box.close();
    } finally {
      await fixture.dispose();
    }
  });

  test('an already open backend cannot be adopted with another cache path',
      () async {
    final _Copy fixture = await _copy();
    try {
      final Box<dynamic> original = await Hive.openBox<dynamic>(
        copiedWalletPointerBox, path: fixture.originalPointer.parent.path,
      );
      final List<int> before = await fixture.copiedPointer.readAsBytes();
      int claims = 0;
      await expectLater(bindCopiedWalletPointer(hive: Hive,
        originalHome: fixture.original, restoredHome: fixture.restored,
        originalWallet: fixture.originalWallet.path,
        cacheRelative: fixture.cacheRelative, closed: () => true,
        claim: () async { claims++; }),
        throwsA(isA<CopiedWalletPointerRefused>()));
      expect(original.get(0), fixture.originalWallet.path);
      expect(original.isOpen, isTrue);
      expect(claims, 0);
      expect(await fixture.copiedPointer.readAsBytes(), before);
      await original.close();
    } finally {
      await fixture.dispose();
    }
  });

  test('extra copied pointer entries refuse before a write claim', () async {
    final _Copy fixture = await _copy(extra: true);
    try {
      int claims = 0;
      await expectLater(bindCopiedWalletPointer(hive: Hive,
        originalHome: fixture.original, restoredHome: fixture.restored,
        originalWallet: fixture.originalWallet.path,
        cacheRelative: fixture.cacheRelative, closed: () => true,
        claim: () async { claims++; }),
        throwsA(isA<CopiedWalletPointerRefused>()));
      expect(claims, 0);
      final Box<dynamic> box = await Hive.openBox<dynamic>(
        copiedWalletPointerBox, path: fixture.cache, crashRecovery: false,
      );
      expect(box.toMap(), <int, String>{
        0: fixture.originalWallet.path, 1: 'held fixture',
      });
      await box.close();
    } finally {
      await fixture.dispose();
    }
  });

  test('lost closure during the write claim holds the original copied value',
      () async {
    final _Copy fixture = await _copy();
    try {
      bool closed = true;
      await expectLater(bindCopiedWalletPointer(hive: Hive,
        originalHome: fixture.original, restoredHome: fixture.restored,
        originalWallet: fixture.originalWallet.path,
        cacheRelative: fixture.cacheRelative, closed: () => closed,
        claim: () async { closed = false; }),
        throwsA(isA<CopiedWalletPointerRefused>()));
      final Box<dynamic> box = await Hive.openBox<dynamic>(
        copiedWalletPointerBox, path: fixture.cache, crashRecovery: false,
      );
      expect(box.toMap(), <int, String>{0: fixture.originalWallet.path});
      await box.close();
    } finally {
      await fixture.dispose();
    }
  });

  test('a different valid original wallet refuses before a write claim',
      () async {
    final _Copy fixture = await _copy();
    try {
      final List<int> source = await fixture.originalPointer.readAsBytes();
      final List<int> encrypted = await fixture.copiedWallet.readAsBytes();
      int claims = 0;
      await expectLater(bindCopiedWalletPointer(hive: Hive,
        originalHome: fixture.original, restoredHome: fixture.restored,
        originalWallet: p.join(fixture.original, 'wallet', 'different.json'),
        cacheRelative: fixture.cacheRelative, closed: () => true,
        claim: () async { claims++; }),
        throwsA(isA<CopiedWalletPointerRefused>()));
      expect(claims, 0);
      expect(await fixture.originalPointer.readAsBytes(), source);
      expect(await fixture.copiedWallet.readAsBytes(), encrypted);
      final Box<dynamic> box = await Hive.openBox<dynamic>(
        copiedWalletPointerBox, path: fixture.cache, crashRecovery: false,
      );
      expect(box.toMap(), <int, String>{0: fixture.originalWallet.path});
      await box.close();
    } finally {
      await fixture.dispose();
    }
  });
}
