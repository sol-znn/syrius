import 'package:zenon_syrius_wallet_flutter/main.dart' as app;
import 'package:zenon_syrius_wallet_flutter/utils/global.dart';
import 'package:zenon_syrius_wallet_flutter/utils/wallet_context_revision.dart';
import 'package:znn_sdk_dart/znn_sdk_dart.dart';

/// A read's transport and wallet context. Returning to a node cannot revive it.
final class TokenReadContext {
  /// Captures the transport before any asynchronous token or account read.
  TokenReadContext({
    required Client client,
    required this._ownsClient,
    Zenon? sdk,
  }) : _client = client,
       _appClient = sdk ?? app.zenon,
       _revision = WalletContextRevision.value,
       _selection = kSelectedAddress,
       _node = kCurrentNode,
       _nodeChain = kNodeChainId,
       _chain = getChainIdentifier(),
       _url = client is WsClient ? client.url : null;

  final Client _client;
  final bool Function() _ownsClient;
  final Zenon? _appClient;
  final int _revision;
  final String? _selection;
  final String? _node;
  final int? _nodeChain;
  final int _chain;
  final String? _url;
  bool _revoked = false;

  /// A captured read is current only while every original context agrees.
  bool get isCurrent {
    if (_revoked) return false;
    return !(_revoked =
        _revision != WalletContextRevision.value ||
        !identical(_appClient, app.zenon) ||
        _selection != kSelectedAddress ||
        _node != kCurrentNode ||
        _nodeChain != kNodeChainId ||
        _chain != getChainIdentifier() ||
        (_client is WsClient && _client.url != _url) ||
        !_ownsClient());
  }

  /// Stops an incomplete or superseded read before its next RPC page.
  void requireCurrent() {
    if (!isCurrent) throw const TokenReadSuperseded();
  }
}

/// A superseded read has no result for the current page.
final class TokenReadSuperseded implements Exception {
  /// Creates the cancellation marker without wallet or transport data.
  const TokenReadSuperseded();
}
