import 'package:material_ui/material_ui.dart';
import 'package:zenon_syrius_wallet_flutter/rearchitecture/utils/extensions/buildcontext_extension.dart';
import 'package:zenon_syrius_wallet_flutter/utils/app_theme.dart';
import 'package:zenon_syrius_wallet_flutter/widgets/reusable_widgets/input_fields/input_field.dart';

/// A password field whose retained eye callback has the same route authority.
class SettingsSecretField extends StatefulWidget {
  /// Receives only presentation inputs and a captured route predicate.
  const SettingsSecretField({
    required this.controller,
    required this.label,
    required this.isCurrent,
    required this.onChanged,
    this.onSubmitted,
    this.validator,
    this.error,
    this.enabled = true,
    super.key,
  });

  /// The original screen's controller.
  final TextEditingController controller;

  /// The localized field name.
  final String label;

  /// Refuses hidden, disposed and replaced child screens.
  final bool Function() isCurrent;

  /// The parent also fences a retained direct callback.
  final ValueChanged<String> onChanged;

  /// Enter uses the same admission path as the visible action.
  final ValueChanged<String>? onSubmitted;

  /// Existing password-strength or matching validation.
  final FormFieldValidator<String>? validator;

  /// A localized result, never raw crypto or file text.
  final String? error;

  /// False while the original action is admitted.
  final bool enabled;

  @override
  State<SettingsSecretField> createState() => _SettingsSecretFieldState();
}

class _SettingsSecretFieldState extends State<SettingsSecretField> {
  bool _obscure = true;

  @override
  Widget build(BuildContext context) {
    final bool Function() current = widget.isCurrent;
    final bool enabled = widget.enabled;
    return InputField(
      controller: widget.controller,
      hintText: widget.label,
      enabled: enabled,
      obscureText: _obscure,
      inputtedTextStyle: AppTokens.of(context).bodyText,
      onChanged: widget.onChanged,
      onSubmitted: widget.onSubmitted,
      validator: widget.validator,
      errorText: widget.error,
      suffixIcon: IconButton(
        tooltip: _obscure
            ? context.l10n.lockShowPassword
            : context.l10n.lockHidePassword,
        onPressed: enabled
            ? () {
                if (mounted && current()) {
                  setState(() => _obscure = !_obscure);
                }
              }
            : null,
        icon: Icon(
          _obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined,
        ),
      ),
    );
  }
}
