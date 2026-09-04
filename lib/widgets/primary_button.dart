import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/colors.dart';

/// The app's standard primary call-to-action button.
///
/// Replaces the near-identical hand-rolled `GestureDetector + AnimatedContainer`
/// buttons that were copy-pasted across the auth screens. Gives every primary
/// CTA the same behaviour:
///  • press-scale feedback (so the button feels "alive" on tap),
///  • a built-in [loading] spinner + disabled state (double-tap safe),
///  • a light haptic tick on tap,
///  • one consistent height / radius / weight.
class PrimaryButton extends StatefulWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool loading;

  /// When false the button is dimmed and non-interactive (independent of
  /// [loading]). Defaults to true.
  final bool enabled;

  const PrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.loading = false,
    this.enabled = true,
  });

  @override
  State<PrimaryButton> createState() => _PrimaryButtonState();
}

class _PrimaryButtonState extends State<PrimaryButton> {
  bool _pressed = false;

  bool get _interactive =>
      widget.enabled && !widget.loading && widget.onPressed != null;

  void _setPressed(bool v) {
    if (!_interactive) return;
    if (_pressed != v) setState(() => _pressed = v);
  }

  void _handleTap() {
    if (!_interactive) return;
    HapticFeedback.selectionClick();
    widget.onPressed!();
  }

  @override
  Widget build(BuildContext context) {
    final disabled = !_interactive;
    return Semantics(
      button: true,
      enabled: !disabled,
      label: widget.label,
      child: GestureDetector(
        onTapDown: (_) => _setPressed(true),
        onTapUp: (_) => _setPressed(false),
        onTapCancel: () => _setPressed(false),
        onTap: _handleTap,
        child: AnimatedScale(
          scale: _pressed ? 0.97 : 1.0,
          duration: const Duration(milliseconds: 110),
          curve: Curves.easeOut,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: double.infinity,
            height: 52,
            decoration: BoxDecoration(
              color: disabled ? C.textDim : C.accent,
              borderRadius: BorderRadius.circular(AppTheme.radiusMd),
              boxShadow: disabled
                  ? null
                  : [
                      BoxShadow(
                        color: C.accent.withValues(alpha: _pressed ? 0.15 : 0.3),
                        blurRadius: _pressed ? 8 : 16,
                        offset: const Offset(0, 6),
                      ),
                    ],
            ),
            child: Center(
              child: widget.loading
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Colors.white,
                      ),
                    )
                  : Text(
                      widget.label,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
