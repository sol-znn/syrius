import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/p2p_swap_widgets/modals/p2p_swap_warning_modal.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/p2p_swap_widgets/modals/start_native_swap_modal.dart';

import 'fixtures/seed_deposit_entry.dart';
import 'fixtures/seed_policy.dart';

/// Captures only real modal ancestors of the current visible UI snapshot.
SeedDepositEntry captureSeedDepositEntry(
  Iterable<Element> visible, {
  required String expectedOwner,
  required Future<void> Function(Element, VoidCallback) tapOriginal,
}) {
  final Set<Element> warnings = <Element>{};
  final Set<Element> starts = <Element>{};
  void collect(Element element) {
    if (element.widget is P2PSwapWarningModal) warnings.add(element);
    if (element.widget is StartNativeSwapModal) starts.add(element);
  }
  for (final Element element in visible) {
    if (!element.mounted) continue;
    collect(element);
    element.visitAncestorElements((Element ancestor) {
      collect(ancestor);
      return true;
    });
  }
  if (warnings.length == 1 && starts.isEmpty) {
    final Element owner = warnings.single;
    final P2PSwapWarningModal original = owner.widget as P2PSwapWarningModal;
    final ModalRoute<dynamic>? route = ModalRoute.of(owner);
    final List<Element> controls = <Element>[];
    void visit(Element element) {
      if (element.widget case final OutlinedButton button) {
        if (button.key == const Key('p2p_warning_continue') &&
            button.onPressed == original.onAccepted) {
          controls.add(element);
        }
      }
      element.visitChildElements(visit);
    }
    owner.visitChildElements(visit);
    if (route == null || !route.isCurrent || controls.length != 1 ||
        !TickerMode.valuesOf(owner).enabled) {
      throw const SeedRefused('original-deposit-entry-required');
    }
    final Element control = controls.single;
    bool current() {
      final Widget button = control.widget;
      return owner.mounted && control.mounted &&
          identical(owner.widget, original) &&
          identical(ModalRoute.of(owner), route) && route.isCurrent &&
          TickerMode.valuesOf(owner).enabled && button is OutlinedButton &&
          button.key == const Key('p2p_warning_continue') &&
          button.onPressed == original.onAccepted;
    }
    return SeedDepositEntry.warning(
      originalCurrent: current,
      tapOriginalContinue: (VoidCallback admission) =>
          tapOriginal(control, admission),
    );
  }
  if (starts.length == 1 && warnings.isEmpty) {
    final Element owner = starts.single;
    if (owner is! StatefulElement) {
      throw const SeedRefused('original-deposit-entry-required');
    }
    final Object originalState = owner.state;
    final StartNativeSwapModal original = owner.widget as StartNativeSwapModal;
    final ModalRoute<dynamic>? route = ModalRoute.of(owner);
    bool current() => owner.mounted && identical(owner.state, originalState) &&
        identical(owner.widget, original) && route != null && route.isCurrent &&
        identical(ModalRoute.of(owner), route) &&
        TickerMode.valuesOf(owner).enabled &&
        original.source?.chainId == 321 &&
        original.source?.ownerAddress == expectedOwner &&
        original.source?.isCurrent == true &&
        original.sourceIsCurrent?.call() == true;
    if (!current()) {
      throw const SeedRefused('original-deposit-entry-required');
    }
    return SeedDepositEntry.ready(originalCurrent: current);
  }
  throw const SeedRefused('original-deposit-entry-required');
}
