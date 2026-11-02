import 'dart:async';

import 'package:hive_ce/hive_ce.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/token_favorite/exceptions/favorite_tokens_exception.dart';
import 'package:zenon_syrius_wallet_flutter/utils/constants.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

/// Stores the token standards marked as favorites by the wallet.
abstract interface class FavoriteTokensRepository {
  /// Whether [tokenStandard] is currently a favorite.
  bool contains(TokenStandard tokenStandard);

  /// Adds [tokenStandard] to favorites if it is not already present.
  Future<void> add(TokenStandard tokenStandard);

  /// Removes [tokenStandard] from favorites if it is present.
  Future<void> remove(TokenStandard tokenStandard);
}

/// A page reads committed membership even while Hive has an optimistic write.
final class PersistedFavoriteTokensRepository
    implements FavoriteTokensRepository {
  /// Shares this wrapper between the page and its rows.
  factory PersistedFavoriteTokensRepository(
    FavoriteTokensRepository repository,
  ) {
    if (repository is PersistedFavoriteTokensRepository) return repository;
    if (repository is HiveFavoriteTokensRepository) {
      final Box<dynamic> box = repository._favoriteTokensBox;
      return _byBox[box] ??= PersistedFavoriteTokensRepository._(repository);
    }
    return PersistedFavoriteTokensRepository._(repository);
  }

  PersistedFavoriteTokensRepository._(this._repository);

  static final Expando<PersistedFavoriteTokensRepository> _byBox =
      Expando<PersistedFavoriteTokensRepository>();

  final FavoriteTokensRepository _repository;
  final Map<String, bool> _committed = <String, bool>{};
  final Map<String, Future<void>> _pending = <String, Future<void>>{};
  final Map<String, Object> _pendingOwners = <String, Object>{};
  final StreamController<void> _changes = StreamController<void>.broadcast();

  /// A remounted page learns of a completed write from the previous page.
  Stream<void> get changes => _changes.stream;

  @override
  bool contains(TokenStandard tokenStandard) => _committed.putIfAbsent(
    tokenStandard.toString(),
    () => _repository.contains(tokenStandard),
  );

  @override
  Future<void> add(TokenStandard tokenStandard) =>
      _change(tokenStandard, favorite: true);

  @override
  Future<void> remove(TokenStandard tokenStandard) =>
      _change(tokenStandard, favorite: false);

  Future<void> _change(TokenStandard standard, {required bool favorite}) {
    final String key = standard.toString();
    final Future<void>? previous = _pending[key];
    contains(standard);
    final Object owner = Object();
    _pendingOwners[key] = owner;
    final Future<void> result = _persist(
      standard,
      favorite: favorite,
      previous: previous,
      owner: owner,
    );
    _pending[key] = result;
    return result;
  }

  Future<void> _persist(
    TokenStandard standard, {
    required bool favorite,
    required Future<void>? previous,
    required Object owner,
  }) async {
    await Future<void>.value();
    if (previous != null) {
      try {
        await previous;
      } on Object {
        // A failed earlier write does not replace this explicit later request.
      }
    }
    try {
      if (favorite) {
        await _repository.add(standard);
      } else {
        await _repository.remove(standard);
      }
      _committed[standard.toString()] = favorite;
      _changes.add(null);
    } finally {
      final String key = standard.toString();
      if (identical(_pendingOwners[key], owner)) {
        _pendingOwners.remove(key);
        unawaited(_pending.remove(key));
      }
    }
  }
}

/// A Hive-backed [FavoriteTokensRepository].
final class HiveFavoriteTokensRepository implements FavoriteTokensRepository {
  /// Creates a repository using the wallet's favorite-token box.
  HiveFavoriteTokensRepository({Box<dynamic>? favoriteTokensBox})
    : _favoriteTokensBox =
          favoriteTokensBox ?? Hive.box<dynamic>(kFavoriteTokensBox);

  final Box<dynamic> _favoriteTokensBox;

  @override
  bool contains(TokenStandard tokenStandard) =>
      _favoriteTokensBox.values.contains(tokenStandard.toString());

  @override
  Future<void> add(TokenStandard tokenStandard) async {
    try {
      if (contains(tokenStandard)) {
        return;
      }

      await _favoriteTokensBox.add(tokenStandard.toString());
    } on AddingToFavoriteTokensException {
      rethrow;
    } on Object catch (error, stackTrace) {
      Error.throwWithStackTrace(
        AddingToFavoriteTokensException(cause: error),
        stackTrace,
      );
    }
  }

  @override
  Future<void> remove(TokenStandard tokenStandard) async {
    try {
      final int index = _favoriteTokensBox.values.toList().indexOf(
        tokenStandard.toString(),
      );
      if (index == -1) {
        return;
      }

      await _favoriteTokensBox.deleteAt(index);
    } on RemovingFromFavoriteTokensException {
      rethrow;
    } on Object catch (error, stackTrace) {
      Error.throwWithStackTrace(
        RemovingFromFavoriteTokensException(cause: error),
        stackTrace,
      );
    }
  }
}
