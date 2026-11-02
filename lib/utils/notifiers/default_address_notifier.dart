import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/blocs/pow_generating_status_bloc.dart';
import 'package:zenon_syrius_wallet_flutter/main.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/dapp_bridge/dapp_bridge.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/latest_transactions/bloc/latest_transactions_bloc.dart';
import 'package:zenon_syrius_wallet_flutter/services/i_web3wallet_service.dart';
import 'package:zenon_syrius_wallet_flutter/utils/global.dart';
import 'package:zenon_syrius_wallet_flutter/utils/wallet_context_revision.dart';

/// Announces the selected address after invalidating old display ownership.
class SelectedAddressNotifier extends ChangeNotifier {
  /// A real address change revokes old PoW before announcing the new context.
  void changeSelectedAddress(String? newSelectedAddress) {
    if (newSelectedAddress != kSelectedAddress) {
      WalletContextRevision.invalidate();
    }
    if (newSelectedAddress != kSelectedAddress &&
        sl.isRegistered<LatestTransactionsBloc>()) {
      sl.get<LatestTransactionsBloc>().invalidateReadContext();
    }
    if (newSelectedAddress != kSelectedAddress &&
        sl.isRegistered<PowGeneratingStatusBloc>()) {
      sl.get<PowGeneratingStatusBloc>().invalidate();
    }
    kSelectedAddress = newSelectedAddress;
    unawaited(
      sl<IWeb3WalletService>().emitAddressChangeEvent(newSelectedAddress!),
    );
    DappBridge.instance.selectionChanged();
    notifyListeners();
  }
}

/// Owns only the shell's original selection subscription.
/// Closing it leaves the provider's notifier and original actions untouched.
final class SelectedAddressContextListener {
  /// Captures the current selection before attaching to the original source.
  SelectedAddressContextListener({
    required this._source,
    required this._onChanged,
  }) : _selected = kSelectedAddress {
    _source.addListener(_changed);
  }

  final SelectedAddressNotifier _source;
  final void Function({required bool contextAlreadyInvalidated}) _onChanged;
  String? _selected;
  bool _closed = false;

  void _changed() {
    if (_closed || _selected == kSelectedAddress) return;
    _selected = kSelectedAddress;
    // The original notifier already revoked before announcing this choice.
    _onChanged(contextAlreadyInvalidated: true);
  }

  /// Detaches this subscription once without disposing the original notifier.
  void close() {
    if (_closed) return;
    _closed = true;
    _source.removeListener(_changed);
  }
}
