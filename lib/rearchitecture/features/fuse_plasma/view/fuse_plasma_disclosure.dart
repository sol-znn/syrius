import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/widgets/disclosure.dart';
import 'package:zenon_syrius_wallet_flutter/utils/app_theme.dart';

/// A retained Fuse form whose old callbacks lose authority when it closes.
class FusePlasmaDisclosure extends StatefulWidget {
  /// Builds the production form with an authority bound to this opening.
  const FusePlasmaDisclosure({
    required this.controller,
    required this.isCurrent,
    required this.builder,
    super.key,
  });

  /// The same controller used by the page strip's Fuse and Close controls.
  final DisclosureController controller;

  /// Captured page and wallet authority, independent of disclosure state.
  final bool Function() isCurrent;

  /// Builds the retained form with authority for only this opening.
  final Widget Function(BuildContext context, bool Function() isCurrent)
  builder;

  @override
  State<FusePlasmaDisclosure> createState() => _FusePlasmaDisclosureState();
}

class _FusePlasmaDisclosureState extends State<FusePlasmaDisclosure> {
  int _closeEpoch = 0;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChanged);
  }

  @override
  void didUpdateWidget(FusePlasmaDisclosure oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onChanged);
      _closeEpoch++;
      widget.controller.addListener(_onChanged);
    }
  }

  void _onChanged() {
    // Advance synchronously: a close and reopen in one frame must still
    // revoke a callback captured before the close.
    if (!widget.controller.isOpen) _closeEpoch++;
    setState(() {});
  }

  @override
  void dispose() {
    _closeEpoch++;
    widget.controller.removeListener(_onChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final int closeEpoch = _closeEpoch;
    final bool wasOpen = widget.controller.isOpen;
    final bool Function() pageIsCurrent = widget.isCurrent;
    bool isCurrent() =>
        wasOpen &&
        mounted &&
        closeEpoch == _closeEpoch &&
        widget.controller.isOpen &&
        pageIsCurrent();
    return Disclosure.bare(
      controller: widget.controller,
      keepAlive: true,
      child: Padding(
        padding: EdgeInsetsDirectional.only(top: AppTokens.of(context).pageGap),
        child: widget.builder(context, isCurrent),
      ),
    );
  }
}
