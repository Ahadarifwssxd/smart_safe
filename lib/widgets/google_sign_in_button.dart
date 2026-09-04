import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/colors.dart';

/// A polished, reusable "Continue with Google" button.
///
/// Improvements over the old inline version:
///  • The Google "G" is painted locally ([GoogleGLogo]) — it never flickers and
///    doesn't need internet on the login screen.
///  • Press feedback: the button scales down slightly while held.
///  • Built-in [loading] state shows a spinner and disables taps, so it can't be
///    double-tapped while a sign-in is already in flight.
///  • Light haptic tick on tap for a native, responsive feel.
class GoogleSignInButton extends StatefulWidget {
  final VoidCallback onPressed;
  final bool loading;
  final String label;

  const GoogleSignInButton({
    super.key,
    required this.onPressed,
    this.loading = false,
    this.label = 'Continue with Google',
  });

  @override
  State<GoogleSignInButton> createState() => _GoogleSignInButtonState();
}

class _GoogleSignInButtonState extends State<GoogleSignInButton> {
  bool _pressed = false;

  void _setPressed(bool v) {
    if (widget.loading) return;
    if (_pressed != v) setState(() => _pressed = v);
  }

  void _handleTap() {
    if (widget.loading) return;
    HapticFeedback.selectionClick();
    widget.onPressed();
  }

  @override
  Widget build(BuildContext context) {
    final disabled = widget.loading;
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
            duration: const Duration(milliseconds: 150),
            height: 52,
            decoration: BoxDecoration(
              color: _pressed ? C.bg3 : C.bg2,
              borderRadius: BorderRadius.circular(AppTheme.radiusMd),
              border: Border.all(
                color: _pressed ? C.accent.withValues(alpha: 0.5) : C.border,
              ),
            ),
            child: Center(
              child: widget.loading
                  ? SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: C.textPrimary,
                      ),
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const GoogleGLogo(size: 20),
                        const SizedBox(width: 12),
                        Text(
                          widget.label,
                          style: TextStyle(
                            color: C.textPrimary,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The official four-colour Google "G", painted with a [CustomPainter] so it is
/// crisp at any size and works completely offline (no network image).
class GoogleGLogo extends StatelessWidget {
  final double size;
  const GoogleGLogo({super.key, this.size = 20});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _GoogleGPainter()),
    );
  }
}

class _GoogleGPainter extends CustomPainter {
  static const _blue = Color(0xFF4285F4);
  static const _red = Color(0xFFEA4335);
  static const _yellow = Color(0xFFFBBC05);
  static const _green = Color(0xFF34A853);

  double _rad(double deg) => deg * math.pi / 180.0;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final center = Offset(size.width / 2, size.height / 2);
    final stroke = s * 0.22;
    final radius = (s - stroke) / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.butt;

    // Four coloured arcs form the ring (clockwise, 0° = east / 3 o'clock).
    // The ring is left open on the right where the cross-bar of the "G" sits.
    void arc(Color c, double startDeg, double sweepDeg) {
      paint.color = c;
      canvas.drawArc(rect, _rad(startDeg), _rad(sweepDeg), false, paint);
    }

    arc(_green, 22, 68); // lower-right → bottom
    arc(_yellow, 90, 78); // bottom → lower-left
    arc(_red, 168, 100); // left → top
    arc(_blue, 268, 70); // top → upper-right

    // The blue horizontal cross-bar: from the centre out to the right edge of
    // the ring, at the vertical middle. This is what turns the ring into a "G".
    final barHeight = stroke;
    final barLeft = center.dx + s * 0.02;
    final barRight = center.dx + radius + stroke / 2;
    final barRect = RRect.fromRectAndCorners(
      Rect.fromLTRB(
        barLeft,
        center.dy - barHeight / 2,
        barRight,
        center.dy + barHeight / 2,
      ),
      topLeft: Radius.circular(barHeight * 0.35),
      bottomLeft: Radius.circular(barHeight * 0.35),
    );
    canvas.drawRRect(barRect, Paint()..color = _blue);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
