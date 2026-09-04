import 'dart:math';
import 'package:flutter/material.dart';
import 'package:smartsafe/theme/colors.dart';

import '../../../constants.dart';

class Chart extends StatelessWidget {
  const Chart({
    Key? key,
    required this.critical,
    required this.silent,
    required this.crash,
    required this.medical,
  }) : super(key: key);

  final int critical;
  final int silent;
  final int crash;
  final int medical;

  @override
  Widget build(BuildContext context) {
    final total = critical + silent + crash + medical;
    return SizedBox(
      height: 200,
      child: Stack(
        children: [
          Center(
            child: SizedBox(
              width: 150,
              height: 150,
              child: CustomPaint(
                painter: PieChartPainter(
                  critical: critical,
                  silent: silent,
                  crash: crash,
                  medical: medical,
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(height: defaultPadding),
                Text(
                  "$total",
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  "Total SOS Alerts",
                  style: TextStyle(
                    color: C.textMuted,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                )
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class PieChartPainter extends CustomPainter {
  final int critical;
  final int silent;
  final int crash;
  final int medical;

  PieChartPainter({
    required this.critical,
    required this.silent,
    required this.crash,
    required this.medical,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 14
      ..strokeCap = StrokeCap.round;

    final rect = Rect.fromCircle(
      center: Offset(size.width / 2, size.height / 2),
      radius: size.width / 2 - 7,
    );

    int total = critical + silent + crash + medical;
    if (total == 0) {
      // Draw uniform/muted circle
      paint.color = Colors.white10;
      canvas.drawArc(rect, -pi / 2, 2 * pi, false, paint);
      return;
    }

    double startAngle = -pi / 2;

    // Draw Critical (Red)
    if (critical > 0) {
      paint.color = const Color(0xFFFF3B4F);
      double sweepAngle = 2 * pi * (critical / total);
      canvas.drawArc(rect, startAngle, sweepAngle - 0.05, false, paint);
      startAngle += sweepAngle;
    }

    // Draw Silent (Amber)
    if (silent > 0) {
      paint.color = const Color(0xFFFFB347);
      double sweepAngle = 2 * pi * (silent / total);
      canvas.drawArc(rect, startAngle, sweepAngle - 0.05, false, paint);
      startAngle += sweepAngle;
    }

    // Draw Crash (Teal)
    if (crash > 0) {
      paint.color = const Color(0xFF00E5C8);
      double sweepAngle = 2 * pi * (crash / total);
      canvas.drawArc(rect, startAngle, sweepAngle - 0.05, false, paint);
      startAngle += sweepAngle;
    }

    // Draw Medical (Green)
    if (medical > 0) {
      paint.color = const Color(0xFF3DDC84);
      double sweepAngle = 2 * pi * (medical / total);
      canvas.drawArc(rect, startAngle, sweepAngle - 0.05, false, paint);
    }
  }

  @override
  bool shouldRepaint(covariant PieChartPainter oldDelegate) {
    return oldDelegate.critical != critical ||
        oldDelegate.silent != silent ||
        oldDelegate.crash != crash ||
        oldDelegate.medical != medical;
  }
}
