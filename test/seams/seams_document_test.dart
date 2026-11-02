import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zenon_syrius_wallet_flutter/seams/seam.dart';

void main() {
  test('each seam has one row with real screens and source references', () {
    final String document = File('lib/seams/SEAMS.md').readAsStringSync();
    final List<String> rows = document
        .split('\n')
        .where((String line) => RegExp(r'^\| `\w+` \|').hasMatch(line))
        .toList();
    final List<String> names = <String>[];
    final Set<String> screens = <String>{};
    for (final File file in Directory(
      'mockups/redesign/src',
    ).listSync().whereType<File>()) {
      if (file.path.endsWith('.html')) {
        screens.addAll(
          RegExp(r'<section\b[^>]*\bid="([^"]+)"')
              .allMatches(file.readAsStringSync())
              .map((RegExpMatch match) => match.group(1)!),
        );
      }
    }

    final RegExp code = RegExp('`([^`]+)`');
    for (final String row in rows) {
      final List<String> columns = row.split('|');
      names.add(code.firstMatch(columns[1])!.group(1)!);
      final List<String> ids = code
          .allMatches(columns[2])
          .map((RegExpMatch match) => match.group(1)!)
          .toList();
      expect(ids, isNotEmpty, reason: row);
      for (final String id in ids) {
        expect(screens, contains(id), reason: row);
      }
      final String implementation = code.firstMatch(columns[3])!.group(1)!;
      final String brief = code.firstMatch(columns[4])!.group(1)!;
      expect(File(implementation).existsSync(), isTrue, reason: row);
      expect(brief, startsWith('docs/research/'), reason: row);
      expect(File(brief).existsSync(), isTrue, reason: row);
    }
    expect(names, unorderedEquals(Seam.values.map((Seam seam) => seam.name)));
  });
}
