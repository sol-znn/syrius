import 'dart:io';

import 'package:hive_ce/hive_ce.dart';
import 'package:path/path.dart' as p;

// The existing application pointer box and key, without importing UI code.
const String copiedWalletPointerBox = 'key_store_box';

enum CopiedPointerPhase { path, open, read, claim, write, flush, close }

class CopiedWalletPointerRefused implements Exception {
  const CopiedWalletPointerRefused(this.phase);

  final CopiedPointerPhase phase;

  @override
  String toString() => 'copied-wallet-pointer-${phase.name}-refused';
}

void _need(bool value, CopiedPointerPhase phase) {
  if (!value) throw CopiedWalletPointerRefused(phase);
}

/// Keeps the copied pointer inside a distinct named harness home.
String mapCopiedWalletPath({
  required String originalHome,
  required String restoredHome,
  required String savedPath,
  p.Context? context,
}) {
  final p.Context paths = context ?? p.context;
  for (final String value in <String>[
    originalHome, restoredHome, savedPath,
  ]) {
    _need(value.isNotEmpty && value.length <= 4096 &&
        !value.contains('\u0000') && paths.isAbsolute(value) &&
        !paths.split(value).contains('..'), CopiedPointerPhase.path);
  }
  final String original = paths.normalize(originalHome);
  final String restored = paths.normalize(restoredHome);
  final RegExp name = RegExp(r'^ci-wallet-[a-f0-9]{24}$');
  _need(name.hasMatch(paths.basename(original)) &&
      name.hasMatch(paths.basename(restored)) &&
      paths.basename(paths.dirname(original)) == '.harness' &&
      paths.equals(paths.dirname(original), paths.dirname(restored)) &&
      !paths.equals(original, restored) &&
      paths.isWithin(original, savedPath), CopiedPointerPhase.path);
  final String relative = paths.relative(savedPath, from: original);
  final String copied = paths.normalize(paths.join(restored, relative));
  _need(paths.isWithin(restored, copied), CopiedPointerPhase.path);
  return copied;
}

void _plainDirectory(String home, String directory) {
  _need(p.equals(home, directory) || p.isWithin(home, directory),
      CopiedPointerPhase.path);
  _need(FileSystemEntity.typeSync(home, followLinks: false) ==
      FileSystemEntityType.directory, CopiedPointerPhase.path);
  if (p.equals(home, directory)) return;
  final List<String> parts = p.split(p.relative(directory, from: home));
  _need(parts.length <= 32 && !parts.contains('..'), CopiedPointerPhase.path);
  String current = home;
  for (final String part in parts) {
    current = p.join(current, part);
    _need(FileSystemEntity.typeSync(current, followLinks: false) ==
        FileSystemEntityType.directory, CopiedPointerPhase.path);
  }
}

List<int> _cipherBytes(String home, String filename) {
  _plainDirectory(home, p.dirname(filename));
  _need(FileSystemEntity.typeSync(filename, followLinks: false) ==
      FileSystemEntityType.file, CopiedPointerPhase.path);
  final File file = File(filename);
  _need(file.lengthSync() > 0 && file.lengthSync() <= 64 * 1024,
      CopiedPointerPhase.path);
  final RandomAccessFile source = file.openSync();
  try {
    final List<int> bytes = source.readSync(64 * 1024 + 1);
    _need(bytes.isNotEmpty && bytes.length <= 64 * 1024 &&
        source.lengthSync() == bytes.length, CopiedPointerPhase.path);
    return bytes;
  } finally {
    source.closeSync();
  }
}

bool _sameBytes(List<int> left, List<int> right) {
  if (left.length != right.length) return false;
  for (int index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}

/// Binds key zero only after the caller retains its one-attempt write claim.
/// Hive ignores a new path when that box name is already open, so adoption
/// is refused before opening any copied backend.
Future<String> bindCopiedWalletPointer({
  required HiveInterface hive,
  required String originalHome,
  required String restoredHome,
  required String cacheRelative,
  required String originalWallet,
  required bool Function() closed,
  required Future<void> Function() claim,
}) async {
  CopiedPointerPhase phase = CopiedPointerPhase.path;
  Box<dynamic>? box;
  try {
    _need(closed() && !hive.isBoxOpen(copiedWalletPointerBox) &&
        cacheRelative.isNotEmpty && !p.isAbsolute(cacheRelative) &&
        p.rootPrefix(cacheRelative).isEmpty &&
        !cacheRelative.contains('\u0000') &&
        !p.split(cacheRelative).contains('..'), phase);
    final String expected = mapCopiedWalletPath(originalHome: originalHome,
      restoredHome: restoredHome, savedPath: originalWallet);
    final String home = p.normalize(restoredHome);
    final String cache = p.normalize(p.join(home, cacheRelative));
    _plainDirectory(home, cache);
    final String pointer = p.join(cache, '$copiedWalletPointerBox.hive');
    _need(FileSystemEntity.typeSync(pointer, followLinks: false) ==
        FileSystemEntityType.file && File(pointer).lengthSync() <= 1024 * 1024,
        phase);
    phase = CopiedPointerPhase.open;
    final Box<dynamic> original = await hive.openBox<dynamic>(
      copiedWalletPointerBox,
      path: cache, crashRecovery: false,
      compactionStrategy: (int entries, int deleted) => false);
    box = original;
    bool owned() => closed() && original.isOpen &&
        hive.isBoxOpen(copiedWalletPointerBox) &&
        identical(hive.box<dynamic>(copiedWalletPointerBox), original);
    phase = CopiedPointerPhase.read;
    _need(owned() && original.length == 1 && original.containsKey(0) &&
        original.keys.single is int && original.keys.single == 0 &&
        original.path != null && p.equals(original.path!, pointer), phase);
    final Object? saved = original.get(0);
    if (saved is! String) throw CopiedWalletPointerRefused(phase);
    _need(saved == originalWallet, phase);
    final String copied = mapCopiedWalletPath(originalHome: originalHome,
      restoredHome: home, savedPath: saved);
    _need(p.equals(copied, expected), phase);
    final List<int> encrypted = _cipherBytes(home, copied);
    phase = CopiedPointerPhase.claim;
    await claim();
    _need(owned() && original.length == 1 && original.get(0) == saved &&
        _sameBytes(encrypted, _cipherBytes(home, copied)), phase);
    phase = CopiedPointerPhase.write;
    await original.put(0, copied);
    phase = CopiedPointerPhase.flush;
    await original.flush();
    _need(owned() && original.length == 1 && original.get(0) == copied &&
        _sameBytes(encrypted, _cipherBytes(home, copied)), phase);
    return copied;
  } on CopiedWalletPointerRefused {
    rethrow;
  } on Object {
    throw CopiedWalletPointerRefused(phase);
  } finally {
    if (box != null && box.isOpen) {
      _need(hive.isBoxOpen(copiedWalletPointerBox) &&
          identical(hive.box<dynamic>(copiedWalletPointerBox), box),
          CopiedPointerPhase.close);
      try {
        await box.close();
      } on Object {
        throw const CopiedWalletPointerRefused(CopiedPointerPhase.close);
      }
    }
  }
}
