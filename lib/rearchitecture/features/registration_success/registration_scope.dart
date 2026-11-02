import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/registration_success/registration_confirmation.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/registration_success/registration_publisher.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/send/bloc/send_transaction/send_transaction_bloc.dart';
import 'package:zenon_syrius_wallet_flutter/utils/account_block_utils.dart';

/// One captured registration owner survives parent rebuilds and step changes.
class RegistrationScope extends StatefulWidget {
  /// An existing owner publisher keeps its original fresh-read policy.
  const RegistrationScope({
    required this.builder,
    this.accountBlockUtils,
    this.sender,
    super.key,
  });

  /// Builds the existing blocs and retained form under one stable owner.
  final Widget Function(
    RegistrationConfirmation confirmation,
    AccountBlockUtils publisher,
  )
  builder;

  /// The caller's original owner-specific publisher, when present.
  final AccountBlockUtils? accountBlockUtils;

  /// Captured from the shell before a route crosses its provider boundary.
  final SendTransactionBloc? sender;

  @override
  State<RegistrationScope> createState() => _RegistrationScopeState();
}

class _RegistrationScopeState extends State<RegistrationScope> {
  late final RegistrationConfirmation _confirmation;
  late final AccountBlockUtils _publisher;

  @override
  void initState() {
    super.initState();
    _confirmation = RegistrationConfirmation.capture();
    _publisher =
        widget.accountBlockUtils ??
        RegistrationPublisher(
          sender: widget.sender ?? context.read<SendTransactionBloc>(),
          confirmation: _confirmation,
        );
  }

  @override
  Widget build(BuildContext context) =>
      widget.builder(_confirmation, _publisher);

  @override
  void dispose() {
    _confirmation.dispose();
    super.dispose();
  }
}
