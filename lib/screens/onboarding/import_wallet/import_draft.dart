import 'package:znn_sdk_dart/znn_sdk_dart.dart' show Mnemonic;

/// An immutable validation snapshot. A filename never authenticates a seed.
class ImportSeedDraft {
  /// Normalizes and validates one private 12- or 24-word input snapshot.
  ImportSeedDraft(
    String text, {
    required this.expectedWords,
    bool Function(String)? isValidWord,
    bool Function(List<String>)? validateMnemonic,
  }) : words = List<String>.unmodifiable(
         text.trim().isEmpty
             ? <String>[]
             : text.trim().toLowerCase().split(RegExp(r'\s+')),
       ) {
    final bool Function(String) member = isValidWord ?? Mnemonic.isValidWord;
    final bool Function(List<String>) checksum =
        validateMnemonic ?? Mnemonic.validateMnemonic;
    final bool allowedLength = expectedWords == 12 || expectedWords == 24;
    valid =
        allowedLength &&
        words.length == expectedWords &&
        words.every(member) &&
        checksum(words);
  }

  /// The word count selected by the import owner.
  final int expectedWords;

  /// The exact normalized private input, frozen before checksum validation.
  final List<String> words;

  /// Whether length, word membership and the mnemonic checksum all passed.
  late final bool valid;

  /// The exact normalized words validated in this snapshot.
  String get seed => words.join(' ');
}

/// The selected path is private input, never presentation or a log field.
class ImportFileSelection {
  /// Retains only the path admitted by the bounded content probe.
  ImportFileSelection(this.path);

  /// Private picker input used by the original decryptor, never a UI label.
  final String path;
}
