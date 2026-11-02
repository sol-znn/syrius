import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/accelerator_widgets/accelerator_action_controller.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/accelerator_widgets/accelerator_action_stepper.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/accelerator_widgets/accelerator_parts.dart';

import 'fixtures/seed_policy.dart';
import 'fixtures/seed_project_presentation.dart';

/// Captures actual view identities before the original publication pointer.
/// The caller supplies its existing guarded pointer implementation.
SeedProjectPresentation captureSeedProjectPresentation(
  Element submit, {
  required Future<void> Function(Element, VoidCallback) tapOriginal,
}) {
  if (!submit.mounted) {
    throw const SeedRefused('original-project-presentation-required');
  }
  StatefulElement? foundOwner;
  Element? foundFrame;
  submit.visitAncestorElements((Element ancestor) {
    if (foundFrame == null && ancestor.widget is AccStepperFrame) {
      foundFrame = ancestor;
    }
    if (ancestor is StatefulElement &&
        ancestor.widget is AcceleratorActionStepper &&
        ancestor.state is AcceleratorActionPresentationSource) {
      foundOwner = ancestor;
      return false;
    }
    return true;
  });
  final StatefulElement? owner = foundOwner;
  final Element? frame = foundFrame;
  if (owner == null || frame == null || !owner.mounted || !frame.mounted) {
    throw const SeedRefused('original-project-presentation-required');
  }
  final AcceleratorActionPresentationSource source =
      owner.state as AcceleratorActionPresentationSource;
  final AcceleratorActionPresentation original = source.actionPresentation;
  final AccStepperFrame originalFrame = frame.widget as AccStepperFrame;
  final ModalRoute<dynamic>? route = ModalRoute.of(submit);
  if (original.kind != AcceleratorActionKind.createProject ||
      !original.prepared || originalFrame.isDone ||
      route == null || !route.isActive || !route.isCurrent) {
    throw const SeedRefused('original-project-presentation-required');
  }
  final VoidCallback leave = originalFrame.onDone;
  bool current() {
    if (!owner.mounted || !frame.mounted ||
        !identical(owner.state, source) || !route.isCurrent) {
      return false;
    }
    final Widget view = frame.widget;
    final AcceleratorActionPresentation observed = source.actionPresentation;
    return view is AccStepperFrame && view.onDone == leave &&
        observed.current && observed.sameOwner(original);
  }
  bool submitted(String hash) => current() &&
      (frame.widget as AccStepperFrame).isDone &&
      source.actionPresentation.submittedWith(hash);
  return SeedProjectPresentation(
    originalCurrent: current,
    submittedCurrent: submitted,
    originalRouteCompleted: route.completed,
    tapOriginalExit: (VoidCallback admission) async {
      admission();
      final List<Element> leaves = <Element>[];
      void visit(Element element) {
        if (element.widget.key == const Key('acc_stepper_leave')) {
          leaves.add(element);
        }
        element.visitChildElements(visit);
      }
      frame.visitChildElements(visit);
      if (leaves.length != 1 || !leaves.single.mounted) {
        throw const SeedRefused('original-project-presentation-changed');
      }
      final Widget control = leaves.single.widget;
      if (control is! OutlinedButton || control.onPressed != leave) {
        throw const SeedRefused('original-project-presentation-changed');
      }
      admission();
      await tapOriginal(leaves.single, admission);
    },
  );
}
