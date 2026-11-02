/// Private observations of the original membership and committed selection.
/// This value grants no wallet, storage, signing or callback authority.
final class WalletAddressContext {
  WalletAddressContext._(
    this.members, this.selected, this.saved, this.revision, this.owner,
  );

  /// Parses only bounded facts; the agent must match them to its live owner.
  factory WalletAddressContext.parse(Object? value) {
    if (value is! Map<String, dynamic> ||
        value.length != 5 ||
        value['members'] is! List ||
        value['selected'] is! String ||
        value['saved'] is! String ||
        value['revision'] is! int ||
        (value['revision'] as int) < 0 ||
        value['owner'] is! int || (value['owner'] as int) <= 0) {
      throw const FormatException('Address context unavailable');
    }
    final List<dynamic> raw = value['members'] as List<dynamic>;
    if (raw.isEmpty || raw.length > 128 ||
        raw.any((dynamic member) => member is! String ||
            member.isEmpty || member.length > 128)) {
      throw const FormatException('Address membership unavailable');
    }
    final List<String> members = List<String>.unmodifiable(raw.cast<String>());
    if (members.toSet().length != members.length ||
        !members.contains(value['selected']) ||
        !members.contains(value['saved'])) {
      throw const FormatException('Address membership ambiguous');
    }
    return WalletAddressContext._(members, value['selected'] as String,
        value['saved'] as String, value['revision'] as int,
        value['owner'] as int);
  }

  /// Ordered members captured from the original wallet and address Box.
  final List<String> members;
  /// The original notifier's current selection.
  final String selected;
  /// The exact committed preference, independently read from its open Box.
  final String saved;
  /// The wallet context generation at this observation.
  final int revision;
  /// Agent-local generation of the exact original Boxes and transports.
  final int owner;

  /// A pending preference write cannot count as a completed selection.
  bool get consistent => selected == saved;

  /// Private protocol facts; callers publish only finite result flags.
  Map<String, Object> toJson() => <String, Object>{
    'members': members, 'selected': selected, 'saved': saved,
    'revision': revision, 'owner': owner,
  };

  bool _sameMembers(WalletAddressContext other) =>
      members.length == other.members.length &&
      Iterable<int>.generate(members.length).every(
        (int index) => members[index] == other.members[index],
      );

  /// Equality includes the original order and generation, not just an index.
  bool same(WalletAddressContext other) => owner == other.owner &&
      _sameMembers(other) &&
      selected == other.selected && saved == other.saved &&
      revision == other.revision;

  /// Exactly one normal Settings derivation extends the original prefix.
  bool derivedFrom(WalletAddressContext original) =>
      owner == original.owner && consistent && original.consistent &&
      members.length == original.members.length + 1 &&
      Iterable<int>.generate(original.members.length).every(
        (int index) => members[index] == original.members[index],
      ) && selected == original.selected && revision == original.revision + 1;

  /// A preference write can precede the original notifier's one revision.
  /// Neither that intermediate state nor a timeout authorizes another tap.
  bool selectionPending(WalletAddressContext original, int index) =>
      owner == original.owner && index >= 0 &&
      index < original.members.length &&
      _sameMembers(original) &&
      ((selected == original.selected && revision == original.revision &&
          (saved == original.saved || saved == original.members[index])) ||
       (selected == original.members[index] && saved == selected &&
          revision == original.revision + 1));

  /// Exactly one notifier transition and the matching persisted selection.
  bool selectedFrom(WalletAddressContext original, int index) =>
      selectionPending(original, index) && consistent &&
      selected == original.members[index] && revision == original.revision + 1;
}
