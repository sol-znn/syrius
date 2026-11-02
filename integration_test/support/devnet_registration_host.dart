import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/multiple_balance/bloc/multiple_balance_bloc.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/send/bloc/send_transaction/send_transaction_bloc.dart';

/// Owns one isolated registration sender and borrows the scenario's balances.
class DevnetRegistrationHost extends StatelessWidget {
  /// The owning provider retains its sender through rebuilds and step changes.
  const DevnetRegistrationHost({
    required this.balances,
    required this.child,
    this.createSender,
    super.key,
  });

  /// The original scenario service remains owned by the devnet test context.
  final MultipleBalanceBloc balances;

  /// A registration page whose scope reads this host's original sender.
  final Widget child;

  /// Offline lifecycle tests can observe creation and the original close.
  @visibleForTesting
  final SendTransactionBloc Function()? createSender;

  @override
  Widget build(BuildContext context) => BlocProvider<MultipleBalanceBloc>.value(
    value: balances,
    child: BlocProvider<SendTransactionBloc>(
      create: (_) => createSender?.call() ?? SendTransactionBloc(),
      lazy: false,
      child: child,
    ),
  );
}
