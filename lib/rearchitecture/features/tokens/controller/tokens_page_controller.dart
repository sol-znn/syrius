import 'package:flutter/foundation.dart';

/// The token list's local filter.
enum TokensFilter {
  /// Non-native tokens with a positive, successfully read balance.
  held,

  /// Exact persisted ZTS favorites across the complete network catalog.
  favorites,

  /// Every non-native token in the complete catalog.
  all,
}

/// Shell-owned presentation state. It carries no balances or action authority.
final class TokensPageController extends ChangeNotifier {
  TokensFilter _filter = TokensFilter.held;
  String _query = '';
  double _scrollOffset = 0;

  /// The selected list. Ordinary page navigation leaves it intact.
  TokensFilter get filter => _filter;

  /// The original text, including an unfinished search.
  String get query => _query;

  /// The last list offset, restored by the next mounted page's own controller.
  double get scrollOffset => _scrollOffset;

  /// A new filter changes only the visible rows.
  void selectFilter(TokensFilter value) {
    if (_filter == value) return;
    _filter = value;
    _scrollOffset = 0;
    notifyListeners();
  }

  /// Search has no RPC and never changes the favorite membership.
  void setQuery(String value) {
    if (_query == value) return;
    _query = value;
    _scrollOffset = 0;
    notifyListeners();
  }

  /// Scroll updates do not rebuild rows or their inputs.
  void rememberScroll(double value) {
    if (value.isFinite && value >= 0) _scrollOffset = value;
  }
}
