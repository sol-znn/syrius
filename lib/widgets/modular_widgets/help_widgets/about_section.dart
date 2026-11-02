import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/modular_widgets/help_widgets/about_card.dart';

/// The single-column About section of Settings.
class AboutSection extends StatelessWidget {
  /// The optional trailing content belongs after the final genuine licence.
  const AboutSection({
    this.licencesTrailingBuilder,
    this.afterLicences,
    super.key,
  });

  /// The Settings owner controls the lifetime of content below the licences.
  final WidgetBuilder? licencesTrailingBuilder;

  /// Optional content on its own surface after the Licences group.
  final Widget? afterLicences;

  @override
  Widget build(BuildContext context) => AboutCard(
    licencesTrailingBuilder: licencesTrailingBuilder,
    afterLicences: afterLicences,
  );
}
