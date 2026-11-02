import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/create_token_stepper/view/create_token_stepper_view.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/create_token_stepper/widgets/token_create_frame.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/create_token_stepper/widgets/token_created_success.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/features/registration_success/registration_confirmation.dart';

import 'fixtures/seed_policy.dart';
import 'fixtures/seed_token_presentation.dart';

/// Retains the original Token view and attempt before its publication pointer.
/// It can later request only that confirmed receipt's actual Done control.
SeedTokenPresentation captureSeedTokenPresentation(
  Element submit, {
  required String expectedOwner,
  required Future<void> Function(Element, VoidCallback) tapOriginal,
}) {
  if (!submit.mounted) {
    throw const SeedRefused('original-token-presentation-required');
  }
  StatefulElement? foundOwner;
  Element? foundFrame;
  submit.visitAncestorElements((Element ancestor) {
    if (foundFrame == null && ancestor.widget is TokenCreateFrame) {
      foundFrame = ancestor;
    }
    if (ancestor is StatefulElement &&
        ancestor.widget is CreateTokenStepperView) {
      foundOwner = ancestor;
      return false;
    }
    return true;
  });
  final StatefulElement? owner = foundOwner;
  final Element? frame = foundFrame;
  if (owner == null || frame == null || !owner.mounted || !frame.mounted) {
    throw const SeedRefused('original-token-presentation-required');
  }
  final Object originalState = owner.state;
  final CreateTokenStepperView view = owner.widget as CreateTokenStepperView;
  final RegistrationConfirmation? confirmation = view.confirmation;
  final TokenCreateFrame issue = frame.widget as TokenCreateFrame;
  final ModalRoute<dynamic>? route = ModalRoute.of(submit);
  if (confirmation == null || !confirmation.isCurrent ||
      confirmation.publication != null || confirmation.chainId != 321 ||
      confirmation.context?.ownerAddress != expectedOwner ||
      view.preflight.session.owner != expectedOwner ||
      view.preflight.session.chainId != 321 || !view.preflight.isCurrent ||
      !view.preflight.sufficient || view.receipt != null ||
      view.onIssue != null ||
      frame.widget.key != const Key('token_create_issue') ||
      !issue.active || issue.busy || issue.onSubmit == null ||
      route == null || !route.isActive || !route.isCurrent ||
      !TickerMode.valuesOf(owner).enabled) {
    throw const SeedRefused('original-token-presentation-required');
  }
  final Object attempt = confirmation.originalAttempt;
  bool current() {
    if (!owner.mounted || !frame.mounted ||
        !identical(owner.state, originalState) || !route.isCurrent ||
        !identical(ModalRoute.of(owner), route) ||
        !TickerMode.valuesOf(owner).enabled ||
        frame.widget is! TokenCreateFrame) {
      return false;
    }
    final Widget observed = owner.widget;
    return observed is CreateTokenStepperView && observed.receipt == null &&
        observed.onIssue == null &&
        identical(observed.preflight, view.preflight) &&
        identical(observed.confirmation, confirmation) &&
        view.preflight.isCurrent && confirmation.isCurrent &&
        identical(confirmation.originalAttempt, attempt);
  }
  bool submitted(String hash) {
    final RegistrationPublication? publication = confirmation.publication;
    return current() && confirmation.isConfirmed && publication != null &&
        publication.hashText == hash && publication.chainId == 321 &&
        publication.ownerAddress == expectedOwner;
  }
  return SeedTokenPresentation(
    originalCurrent: current,
    submittedCurrent: submitted,
    originalRouteCompleted: route.completed,
    tapOriginalExit: (VoidCallback admission) async {
      admission();
      final List<Element> receipts = <Element>[];
      void visit(Element element) {
        if (element.widget case final TokenCreatedSuccess receipt) {
          if (identical(receipt.confirmation, confirmation)) {
            receipts.add(element);
          }
        }
        element.visitChildElements(visit);
      }
      owner.visitChildElements(visit);
      if (receipts.length != 1 || !receipts.single.mounted) {
        throw const SeedRefused('original-token-presentation-changed');
      }
      final Element receipt = receipts.single;
      final TokenCreatedSuccess original =
          receipt.widget as TokenCreatedSuccess;
      final VoidCallback leave = original.onViewTokensPressed;
      final List<Element> leaves = <Element>[];
      void controls(Element element) {
        if (element.widget case final OutlinedButton control) {
          if (control.onPressed == leave) leaves.add(element);
        }
        element.visitChildElements(controls);
      }
      receipt.visitChildElements(controls);
      if (leaves.length != 1 || !leaves.single.mounted) {
        throw const SeedRefused('original-token-presentation-changed');
      }
      final Element leaf = leaves.single;
      void admit() {
        admission();
        final Widget control = leaf.widget;
        if (!receipt.mounted || !identical(receipt.widget, original) ||
            !leaf.mounted || control is! OutlinedButton ||
            control.onPressed != leave) {
          throw const SeedRefused('original-token-presentation-changed');
        }
      }
      admit();
      await tapOriginal(leaf, admit);
    },
  );
}
