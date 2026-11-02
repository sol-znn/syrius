import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/blocs/p2p_swap/htlc_swap/swap_action_origin.dart';
import 'package:zenon_syrius_wallet_flutter/blocs/p2p_swap/htlc_swap/swap_actions.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/p2p_swap_widgets/modals/start_native_swap_modal.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/p2p_swap_widgets/modals/swap_action_data.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/p2p_swap_widgets/modals/swap_action_surface.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/p2p_swap_widgets/modals/swap_modal_state.dart';

import 'fixtures/seed_deposit_presentation.dart';
import 'fixtures/seed_policy.dart';

/// Captures the actual Start State and route before its publication pointer.
SeedDepositPresentation captureSeedDepositPresentation(
  Element submit, {
  required String expectedOwner,
  required Future<void> Function(Element, VoidCallback) tapOriginal,
}) {
  StatefulElement? found;
  if (submit.mounted) {
    submit.visitAncestorElements((Element ancestor) {
      if (ancestor is StatefulElement &&
          ancestor.widget is StartNativeSwapModal) {
        found = ancestor;
        return false;
      }
      return true;
    });
  }
  final StatefulElement? owner = found;
  if (owner == null || !owner.mounted ||
      owner.state is! CapturedSwapModal<StartNativeSwapModal>) {
    throw const SeedRefused('original-deposit-presentation-required');
  }
  final CapturedSwapModal<StartNativeSwapModal> state =
      owner.state as CapturedSwapModal<StartNativeSwapModal>;
  final StartNativeSwapModal view = owner.widget as StartNativeSwapModal;
  final SwapActionOrigin? source = state.origin;
  final Object epoch = state.epoch;
  final ModalRoute<dynamic>? route = ModalRoute.of(owner);
  final Widget control = submit.widget;
  if (source == null || source.chainId != 321 ||
      source.ownerAddress != expectedOwner ||
      !identical(view.source, source) || !state.sourceCurrent ||
      state.busy || state.activeRun != null || state.shownResult != null ||
      control is! OutlinedButton || control.onPressed == null ||
      control.key != const Key('swap_create_deposit') ||
      route == null || !route.isActive || !route.isCurrent ||
      !TickerMode.valuesOf(owner).enabled) {
    throw const SeedRefused('original-deposit-presentation-required');
  }
  bool current() => owner.mounted && identical(owner.state, state) &&
      identical(owner.widget, view) && identical(state.origin, source) &&
      identical(state.epoch, epoch) && state.sourceCurrent &&
      route.isCurrent && identical(ModalRoute.of(owner), route) &&
      TickerMode.valuesOf(owner).enabled;
  SwapUiRun? acceptedRun;
  SwapActionResult? acceptedResult;
  bool submitted(String hash) {
    final SwapUiRun? run = state.activeRun;
    final SwapActionResult? result = state.shownResult;
    if (!current() || state.busy || run == null || result == null ||
        !identical(run.result, result) ||
        result.status != SwapActionStatus.submitted ||
        result.acceptedHash != hash || result.swap?.id != hash ||
        result.swap?.chainId != 321 ||
        result.swap?.selfAddress != expectedOwner) {
      return false;
    }
    acceptedRun ??= run;
    acceptedResult ??= result;
    return identical(acceptedRun, run) && identical(acceptedResult, result);
  }
  return SeedDepositPresentation(
    originalCurrent: current,
    submittedCurrent: submitted,
    originalRouteCompleted: route.completed,
    tapOriginalExit: (VoidCallback admission) async {
      admission();
      final List<Element> surfaces = <Element>[];
      void visit(Element element) {
        if (element.widget is SwapDialogSurface) surfaces.add(element);
        element.visitChildElements(visit);
      }
      owner.visitChildElements(visit);
      if (surfaces.length != 1 || !surfaces.single.mounted) {
        throw const SeedRefused('original-deposit-presentation-changed');
      }
      final Element surface = surfaces.single;
      final SwapDialogSurface original = surface.widget as SwapDialogSurface;
      final VoidCallback? leave = original.onClose;
      if (original.marker != const Key('swap_start_screen_marker') ||
          leave == null) {
        throw const SeedRefused('original-deposit-presentation-changed');
      }
      final List<Element> exits = <Element>[];
      void controls(Element element) {
        if (element.widget case final IconButton button) {
          if (button.key == const Key('swap_action_close') &&
              button.onPressed == leave) {
            exits.add(element);
          }
        }
        element.visitChildElements(controls);
      }
      surface.visitChildElements(controls);
      if (exits.length != 1 || !exits.single.mounted) {
        throw const SeedRefused('original-deposit-presentation-changed');
      }
      final Element exit = exits.single;
      void admit() {
        admission();
        final Widget button = exit.widget;
        if (!surface.mounted || !identical(surface.widget, original) ||
            !exit.mounted || button is! IconButton ||
            button.key != const Key('swap_action_close') ||
            button.onPressed != leave) {
          throw const SeedRefused('original-deposit-presentation-changed');
        }
      }
      admit();
      await tapOriginal(exit, admit);
    },
  );
}
