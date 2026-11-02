import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/multiple_balance/bloc/multiple_balance_bloc.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/segment.dart';
import 'package:zenon_syrius_wallet_flutter/utils/notifiers/default_address_notifier.dart';

/// Borrows scenario balances and owns only the stake fixture's selection view.
class DevnetStakeHost extends StatelessWidget {
  /// The original stake card continues to own its transaction bloc.
  const DevnetStakeHost({
    required this.balances,
    required this.child,
    this.createSelection,
    super.key,
  });

  /// The scenario retains ownership of its original balance service.
  final MultipleBalanceBloc balances;

  /// The genuine form is mounted without replacing its sender or controls.
  final Widget child;

  /// Offline tests can observe the original notifier's creation and disposal.
  @visibleForTesting
  final SelectedAddressNotifier Function()? createSelection;

  @override
  Widget build(BuildContext context) => BlocProvider<MultipleBalanceBloc>.value(
    value: balances,
    child: ChangeNotifierProvider<SelectedAddressNotifier>(
      create: (_) => createSelection?.call() ?? SelectedAddressNotifier(),
      child: child,
    ),
  );
}

/// Selects an offered month through the original form's actual segment button.
Future<void> selectDevnetStakeDuration(
  WidgetTester tester,
  String durationMonths,
) async {
  final int? months = int.tryParse(durationMonths);
  if (months == null || months <= 0) {
    throw ArgumentError('The stake duration must be a positive whole month');
  }
  final Finder segment = find.byType(Segment<int>);
  for (int turn = 0; turn < 900 && segment.evaluate().isEmpty; turn++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  expect(segment, findsOneWidget);
  if (!tester
      .widget<Segment<int>>(segment)
      .items
      .any(
        (SegmentItem<int> item) => item.value == months,
      )) {
    throw StateError('The stake form does not offer the requested month');
  }
  final Finder control = find.byKey(
    Segment.keyOf('create_stake_months', months),
  );
  expect(control, findsOneWidget);
  await tester.ensureVisible(control);
  await tester.tap(control);
  await tester.pumpAndSettle();
  expect(tester.widget<Segment<int>>(segment).selected, months);
}
