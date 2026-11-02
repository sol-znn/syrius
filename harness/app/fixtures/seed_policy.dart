import 'dart:async';

/// Harness-only policy. This file has no wallet, signer, filesystem or client.
const String seedWsOrigin = 'ws://127.0.0.1:45998';
const String seedHttpOrigin = 'http://127.0.0.1:45997';
/// The single P09 send is separate from the six checkpointed F06 recipes.
const String labSendRecipeId = 'lab-send';
const Set<String> seedRecipeIds = <String>{
  'stake',
  'fuse',
  'token',
  'deposit',
  'project',
  'fund-address',
};

final class SeedRefused implements Exception {
  const SeedRefused(this.code, {this.frontier, this.confirmation});
  final String code;
  final SeedAdvanceObservation? frontier;
  final SeedConfirmationObservation? confirmation;
  @override
  String toString() => 'Seed refused: $code';
}

/// Completed nonpositive rounds from the original eighteen seed reads only.
/// These counts contain no receipt, wallet identity or operation authority.
final class SeedConfirmationObservation {
  const SeedConfirmationObservation._({
    required this.absent,
    required this.unconfirmed,
    required this.effectPending,
    required this.last,
  });

  final int absent;
  final int unconfirmed;
  final int effectPending;
  final SeedPendingResult last;

  Map<String, Object> get public =>
      Map<String, Object>.unmodifiable(<String, Object>{
        'polls': absent + unconfirmed + effectPending,
        'absent': absent, 'unconfirmed': unconfirmed,
        'effect_pending': effectPending,
        'last': switch (last) {
          SeedPendingResult.absent => 'absent',
          SeedPendingResult.unconfirmed => 'unconfirmed',
          SeedPendingResult.effectPending => 'effect_pending',
        },
      });
}

enum SeedPendingResult { absent, unconfirmed, effectPending }

/// A bounded copy of completed original negative reads, without authority.
Map<String, Object>? seedConfirmationProjection(Object? value) {
  const Set<String> fields = <String>{
    'polls', 'absent', 'unconfirmed', 'effect_pending', 'last',
  };
  if (value is! Map<String, Object?> || value.length != fields.length ||
      !value.keys.toSet().containsAll(fields)) {
    return null;
  }
  final Object? polls = value['polls'];
  final Object? absent = value['absent'];
  final Object? unconfirmed = value['unconfirmed'];
  final Object? pending = value['effect_pending'];
  final Object? last = value['last'];
  if (polls is! int || polls != 18 || absent is! int ||
      unconfirmed is! int || pending is! int || last is! String ||
      absent < 0 || absent > 18 || unconfirmed < 0 || unconfirmed > 18 ||
      pending < 0 || pending > 18 || absent + unconfirmed + pending != 18 ||
      !<String>{'absent', 'unconfirmed', 'effect_pending'}.contains(last)) {
    return null;
  }
  if (last == 'absent' && absent == 0 ||
      last == 'unconfirmed' && unconfirmed == 0 ||
      last == 'effect_pending' && pending == 0) {
    return null;
  }
  return Map<String, Object>.unmodifiable(<String, Object>{
    'polls': 18, 'absent': absent, 'unconfirmed': unconfirmed,
    'effect_pending': pending, 'last': last,
  });
}

final class SeedEnvironment {
  SeedEnvironment({
    required this.profile,
    required this.isolated,
    required this.unlocked,
    required this.initialized,
    required this.booted,
    required this.ws,
    required this.http,
    required this.nodeChain,
    required this.signingChain,
    required this.selectedIndex,
    required this.owner,
    required Iterable<String> members,
  }) : members = List<String>.unmodifiable(members);
  final String profile;
  final bool isolated;
  final bool unlocked;
  final bool initialized;
  final bool booted;
  final String ws;
  final String http;
  final int? nodeChain;
  final int signingChain;
  final int selectedIndex;
  final String owner;
  final List<String> members;

  void requireLab() {
    if (profile == 'default' ||
        !RegExp(r'^[A-Za-z0-9][A-Za-z0-9_-]{0,63}$').hasMatch(profile) ||
        !isolated ||
        !booted ||
        !unlocked ||
        !initialized) {
      throw const SeedRefused('isolated-unlocked-profile-required');
    }
    // Exact strings deliberately refuse DNS aliases, credentials, paths,
    // alternate ports, query strings and public endpoints.
    if (ws != seedWsOrigin ||
        http != seedHttpOrigin ||
        nodeChain != 321 ||
        signingChain != 321) {
      throw const SeedRefused('exact-chain-321-lab-required');
    }
    if (selectedIndex != 1 ||
        members.length < 2 ||
        members.toSet().length != members.length ||
        owner.isEmpty ||
        members[1] != owner) {
      throw const SeedRefused('funded-index-one-required');
    }
  }
}

final class SeedFrontier {
  const SeedFrontier({
    required this.chain,
    required this.height,
    required this.timestamp,
    required this.hash,
  });
  final int chain;
  final int height;
  final int timestamp;
  final String hash;
  bool get valid =>
      chain == 321 && height > 0 && timestamp > 0 && seedHash(hash);
  bool advances(SeedFrontier original) =>
      valid &&
      original.valid &&
      height > original.height &&
      timestamp > original.timestamp &&
      hash != original.hash;
}

/// Facts from the same completed admission reads; this starts no extra read.
final class SeedAdvanceObservation {
  const SeedAdvanceObservation({
    required this.firstWs,
    required this.firstHttp,
    required this.lastWs,
    required this.lastHttp,
  });

  final SeedFrontier firstWs;
  final SeedFrontier firstHttp;
  final SeedFrontier lastWs;
  final SeedFrontier lastHttp;

  /// Only isolated lab heights, timestamps and hash comparisons are public.
  /// Hash bytes, transport replies and wallet identities never leave here.
  Map<String, Object> get public => Map<String, Object>.unmodifiable(
    <String, Object>{
      'polls': 6,
      'ws_first_height': firstWs.height,
      'ws_last_height': lastWs.height,
      'ws_first_timestamp': firstWs.timestamp,
      'ws_last_timestamp': lastWs.timestamp,
      'ws_hash_changed': firstWs.hash != lastWs.hash,
      'http_first_height': firstHttp.height,
      'http_last_height': lastHttp.height,
      'http_first_timestamp': firstHttp.timestamp,
      'http_last_timestamp': lastHttp.timestamp,
      'http_hash_changed': firstHttp.hash != lastHttp.hash,
    },
  );
}

bool seedHash(String value) =>
    RegExp(r'^[0-9a-f]{64}$').hasMatch(value) &&
    value.contains(RegExp('[1-9a-f]'));

final class SeedFunding {
  const SeedFunding(this.znn, this.qsr);
  final BigInt znn;
  final BigInt qsr;
}

/// Each wrapper's identity names the identical actual original operation.
abstract interface class SeedOriginal {
  Object get identity;
  bool get settled;
  bool get failed;
  bool get releaseFailed;
  String? get acceptedHash;
}

final class SeedConfirmed {
  const SeedConfirmed({
    required this.hash,
    required this.owner,
    required this.chain,
    required this.positiveConfirmation,
    required this.matchesRecipe,
  });
  final String hash;
  final String owner;
  final int chain;
  final bool positiveConfirmation;
  final bool matchesRecipe;
}

abstract interface class SeedSource {
  SeedEnvironment get environment;
  bool get isCurrent;
  Future<SeedFrontier> wsFrontier();
  Future<SeedFrontier> httpFrontier();
  Future<bool> sameMomentum(SeedFrontier http);
  Future<SeedFunding> funding();
  List<SeedOriginal> originals();
  Future<SeedConfirmed?> confirmed(String recipe, String hash);
  Future<bool> effect(String recipe, String hash);
  SeedFunding minimum(String recipe);
}

/// The production implementation creates exclusive, small profile records.
/// No operation clears an uncertain attempt or overwrites an earlier receipt.
abstract interface class SeedJournal {
  void requireAvailable(String recipe);
  void claim(String recipe);
  void accepted(String recipe, String hash);
  void confirmed(String recipe, String hash);
}

/// One captured source; returning to a revoked source cannot revive it.
final class SeedGuard {
  SeedGuard({
    required this.source,
    required this.journal,
    Future<void> Function(Duration)? delay,
    this.readTimeout = const Duration(seconds: 3),
  }) : _delay = delay ?? Future<void>.delayed,
       _labSend = false;

  /// Read admission for one original P09 request; never a generic seed publish.
  SeedGuard.forLabSend({
    required this.source,
    required this.journal,
    Future<void> Function(Duration)? delay,
    this.readTimeout = const Duration(seconds: 3),
  }) : _delay = delay ?? Future<void>.delayed,
       _labSend = true;
  final SeedSource source;
  final SeedJournal journal;
  final Future<void> Function(Duration) _delay;
  final Duration readTimeout;
  final bool _labSend;
  bool _revoked = false;
  bool _attempted = false;
  SeedOriginal? _original;
  String? _hash;
  String? get acceptedHash => _hash;

  void requireCurrent() {
    if (_revoked || !source.isCurrent) {
      _revoked = true;
      throw const SeedRefused('original-context-changed');
    }
    source.environment.requireLab();
  }

  void requirePreparation() {
    requireCurrent();
    if (_attempted) throw const SeedRefused('original-attempt-held');
  }

  Future<T> _read<T>(Future<T> Function() action) async {
    requireCurrent();
    final T value = await action().timeout(readTimeout);
    requireCurrent();
    return value;
  }

  Future<(SeedFrontier, SeedFrontier)> _frontiers() async {
    final List<SeedFrontier> values = await Future.wait<SeedFrontier>(
      <Future<SeedFrontier>>[
        _read(source.wsFrontier),
        _read(source.httpFrontier),
      ],
    );
    if (values.any((SeedFrontier value) => !value.valid)) {
      throw const SeedRefused('invalid-lab-frontier');
    }
    if (!await _read(() => source.sameMomentum(values.last))) {
      throw const SeedRefused('lab-endpoints-disagree');
    }
    return (values.first, values.last);
  }

  /// Both original endpoints must positively advance during this admission.
  Future<void> admit(String recipe) async {
    if (!(_labSend
        ? recipe == labSendRecipeId
        : seedRecipeIds.contains(recipe))) {
      throw const SeedRefused('unknown-recipe');
    }
    requireCurrent();
    journal.requireAvailable(recipe);
    final (SeedFrontier firstWs, SeedFrontier firstHttp) = await _frontiers();
    SeedFrontier previousWs = firstWs;
    SeedFrontier previousHttp = firstHttp;
    bool advancing = false;
    for (int poll = 0; poll < 6; poll++) {
      await _delay(const Duration(seconds: 5));
      requireCurrent();
      final (SeedFrontier ws, SeedFrontier http) = await _frontiers();
      if (ws.height < previousWs.height ||
          http.height < previousHttp.height ||
          ws.height == previousWs.height &&
              (ws.hash != previousWs.hash ||
                  ws.timestamp != previousWs.timestamp) ||
          http.height == previousHttp.height &&
              (http.hash != previousHttp.hash ||
                  http.timestamp != previousHttp.timestamp)) {
        throw const SeedRefused('lab-frontier-regressed');
      }
      if (ws.advances(firstWs) && http.advances(firstHttp)) {
        advancing = true;
        break;
      }
      previousWs = ws;
      previousHttp = http;
    }
    if (!advancing) {
      throw SeedRefused('advancing-momentum-required',
        frontier: SeedAdvanceObservation(
          firstWs: firstWs, firstHttp: firstHttp,
          lastWs: previousWs, lastHttp: previousHttp,
        ),
      );
    }
    final SeedFunding funds = await _read(source.funding);
    final SeedFunding minimum = source.minimum(recipe);
    if (funds.znn <= BigInt.zero ||
        funds.qsr.isNegative ||
        funds.znn < minimum.znn ||
        funds.qsr < minimum.qsr) {
      throw const SeedRefused('funded-selected-index-required');
    }
    if (source.originals().any(
      (SeedOriginal value) =>
          !value.settled || value.failed || value.releaseFailed,
    )) {
      throw const SeedRefused('earlier-original-unresolved');
    }
  }

  /// [tapOnce] is the real pointer path. No API here signs or sends a block.
  Future<String> publish(String recipe, Future<void> Function() tapOnce) async {
    if (_labSend) {
      throw const SeedRefused('original-transfer-witness-required');
    }
    if (_attempted) throw const SeedRefused('original-attempt-held');
    await admit(recipe);
    final Set<Object> before = source
        .originals()
        .map((SeedOriginal value) => value.identity)
        .toSet();
    requireCurrent();
    journal.claim(recipe);
    _attempted = true;
    // Any exception after the claim leaves the attempt held. A timeout never
    // cancels, replaces, re-signs or retries the original wallet operation.
    await tapOnce();
    for (int poll = 0; poll < 60; poll++) {
      final List<SeedOriginal> added = source
          .originals()
          .where((SeedOriginal value) => !before.contains(value.identity))
          .toList();
      if (added.length > 1) {
        throw const SeedRefused('ambiguous-original-publication');
      }
      if (added.length == 1) {
        final SeedOriginal value = added.single;
        if (_original != null &&
            !identical(value.identity, _original!.identity)) {
          throw const SeedRefused('original-publication-replaced');
        }
        _original = value;
        final String? accepted = value.acceptedHash;
        if (accepted != null) {
          if (!seedHash(accepted) || _hash != null && _hash != accepted) {
            throw const SeedRefused('invalid-original-hash');
          }
          _hash = accepted;
          journal.accepted(recipe, accepted);
        }
        if (value.failed || value.releaseFailed) {
          throw const SeedRefused('original-outcome-unknown');
        }
        if (value.settled && _hash != null) break;
      }
      requireCurrent();
      await _delay(const Duration(milliseconds: 500));
    }
    if (_original == null || !_original!.settled || _hash == null) {
      throw const SeedRefused('original-outcome-unknown');
    }
    final String hash = _hash!;
    int absent = 0;
    int unconfirmed = 0;
    int effectPending = 0;
    SeedPendingResult last = SeedPendingResult.absent;
    for (int poll = 0; poll < 18; poll++) {
      final SeedConfirmed? block = await _read(
        () => source.confirmed(recipe, hash),
      );
      if (block != null &&
          (block.hash != hash ||
              block.owner != source.environment.owner ||
              block.chain != 321 ||
              !block.matchesRecipe)) {
        throw const SeedRefused('exact-original-receipt-mismatch');
      }
      if (block?.positiveConfirmation == true) {
        if (await _read(() => source.effect(recipe, hash))) {
          requireCurrent();
          journal.confirmed(recipe, hash);
          return hash;
        }
        effectPending++;
        last = SeedPendingResult.effectPending;
      } else if (block == null) {
        absent++;
        last = SeedPendingResult.absent;
      } else {
        unconfirmed++;
        last = SeedPendingResult.unconfirmed;
      }
      await _delay(const Duration(seconds: 2));
    }
    throw SeedRefused('exact-confirmation-or-effect-pending',
      confirmation: SeedConfirmationObservation._(
        absent: absent, unconfirmed: unconfirmed,
        effectPending: effectPending, last: last,
      ),
    );
  }
}
