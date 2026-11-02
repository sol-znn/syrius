import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/create_token_stepper/model/token_create_supply.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/reusable_widgets/buttons/primary_pill.dart';

/// Fills the current form and returns its original, untapped Issue control.
Future<Finder> prepareDevnetTokenIssue(
  WidgetTester tester, {
  required String name,
  required String symbol,
  required String website,
  required bool mintable,
  required bool burnable,
  required int decimals,
  required String maxSupply,
  required String totalSupply,
  required bool utility,
  Duration timeout = const Duration(seconds: 90),
}) async {
  if (timeout <= Duration.zero || timeout > const Duration(seconds: 90)) {
    throw ArgumentError('Invalid token form deadline');
  }
  final BigInt? maximum = parseTokenCreateSupply(maxSupply, decimals);
  final BigInt? total = parseTokenCreateSupply(totalSupply, decimals);
  if (maximum == null || total == null || !mintable && maximum != total) {
    throw TestFailure('Token supplies cannot be preserved');
  }
  final DateTime deadline = tester.binding.clock.now().add(timeout);
  await _enter(tester, 'token_name_field', name, deadline);
  await _enter(tester, 'token_symbol_field', symbol, deadline);
  await _enter(tester, 'token_domain_field', website, deadline);
  await _continue(tester, 'details', deadline);

  final Finder slider = await _visible(
    tester,
    'token_decimals_slider',
    deadline,
  );
  final Slider decimalsControl = tester.widget<Slider>(slider);
  expect(decimalsControl.onChanged, isNotNull);
  decimalsControl.onChanged!(decimals.toDouble());
  await tester.pump();
  await _enter(tester, 'token_total_supply_field', totalSupply, deadline);
  await _continue(tester, 'supply', deadline);

  await _checkbox(tester, 'token_mintable_checkbox', mintable, deadline);
  await _checkbox(tester, 'token_burnable_checkbox', burnable, deadline);
  await _checkbox(tester, 'token_utility_checkbox', utility, deadline);
  await _continue(tester, 'options', deadline);

  if (mintable) {
    // The real Options action returns to Supply for the new maximum.
    await _enter(tester, 'token_max_supply_field', maxSupply, deadline);
    await _continue(tester, 'supply', deadline);
    await _continue(tester, 'options', deadline);
  }
  return _action(tester, 'issue', deadline);
}

Future<void> _wait(
  WidgetTester tester,
  bool Function() ready,
  DateTime deadline,
) async {
  while (!ready() && tester.binding.clock.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  if (!tester.binding.clock.now().isBefore(deadline) || !ready()) {
    throw TestFailure('Token step is not actionable');
  }
}

Future<Finder> _visible(
  WidgetTester tester,
  String key,
  DateTime deadline,
) async {
  final Finder finder = find.byKey(Key(key));
  await _wait(tester, () => finder.evaluate().length == 1, deadline);
  await tester.ensureVisible(finder);
  await _wait(
    tester,
    () => finder.hitTestable().evaluate().length == 1,
    deadline,
  );
  return finder;
}

Future<void> _enter(
  WidgetTester tester,
  String key,
  String value,
  DateTime deadline,
) async {
  final Finder finder = await _visible(tester, key, deadline);
  final TextField field = tester.widget<TextField>(finder);
  expect(field.enabled, isNot(false));
  expect(field.readOnly, isFalse);
  await tester.enterText(finder, value);
  await tester.pump();
}

Future<void> _checkbox(
  WidgetTester tester,
  String key,
  bool value,
  DateTime deadline,
) async {
  final Finder finder = await _visible(tester, key, deadline);
  final Checkbox checkbox = tester.widget<Checkbox>(finder);
  expect(checkbox.onChanged, isNotNull);
  if (checkbox.value != value) {
    await tester.tap(finder);
    await tester.pump();
  }
  expect(tester.widget<Checkbox>(finder).value, value);
}

Future<Finder> _action(
  WidgetTester tester,
  String step,
  DateTime deadline,
) async {
  final Finder finder = find.descendant(
    of: find.byKey(Key('token_create_$step')),
    matching: find.byKey(const Key('token_create_continue')),
  );
  await _wait(
    tester,
    () {
      if (finder.evaluate().length != 1) {
        return false;
      }
      final Widget control = tester.widget<Widget>(finder);
      return control is PrimaryPill &&
          control.onPressed != null &&
          finder.hitTestable().evaluate().length == 1;
    },
    deadline,
  );
  return finder;
}

Future<void> _continue(
  WidgetTester tester,
  String step,
  DateTime deadline,
) async {
  final Finder finder = await _action(tester, step, deadline);
  await tester.tap(finder);
  await tester.pump();
}
