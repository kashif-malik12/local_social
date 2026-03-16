import 'dart:math' as math;

import 'package:flutter/material.dart';

class GoogleMark extends StatelessWidget {
  const GoogleMark({super.key, this.size = 20});

  final double size;

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
  const _GoogleGPainter();

  static const _blue = Color(0xFF4285F4);
  static const _red = Color(0xFFEA4335);
  static const _yellow = Color(0xFFFBBC05);
  static const _green = Color(0xFF34A853);

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final outerR = math.min(size.width, size.height) / 2;
    final stroke = outerR * 0.28;
    final arcR = outerR - stroke / 2;
    final rect = Rect.fromCircle(center: c, radius: arcR);
    final k = math.pi / 180.0;

    // White background
    canvas.drawCircle(c, outerR, Paint()..color = Colors.white);

    Paint arc(Color color) => Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.butt;

    // Google G arc segments (0° = 3 o'clock, clockwise positive):
    // Blue  : -15° → 90°  (upper-right arc + bar junction)
    // Yellow:  90° → 180° (lower-right arc)
    // Green : 180° → 270° (lower-left arc)
    // Red   : 270° → 345° (upper-left arc)
    // Gap   : 345° → 345° (≈30° opening on the upper right)
    canvas.drawArc(rect, -15 * k, 105 * k, false, arc(_blue));
    canvas.drawArc(rect, 90 * k, 90 * k, false, arc(_yellow));
    canvas.drawArc(rect, 180 * k, 90 * k, false, arc(_green));
    canvas.drawArc(rect, 270 * k, 75 * k, false, arc(_red));

    // Horizontal cross-bar (blue) from center to right edge at mid-height
    canvas.drawLine(
      Offset(c.dx, c.dy),
      Offset(c.dx + arcR + stroke / 2, c.dy),
      Paint()
        ..color = _blue
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.butt,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}
