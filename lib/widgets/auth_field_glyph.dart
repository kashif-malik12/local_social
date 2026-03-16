import 'package:flutter/material.dart';

enum AuthFieldGlyphKind { email, password }

class AuthFieldGlyph extends StatelessWidget {
  const AuthFieldGlyph({
    super.key,
    required this.kind,
    this.color = const Color(0xFF666E6B),
    this.size = 20,
  });

  final AuthFieldGlyphKind kind;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _AuthFieldGlyphPainter(kind: kind, color: color),
      ),
    );
  }
}

class _AuthFieldGlyphPainter extends CustomPainter {
  const _AuthFieldGlyphPainter({
    required this.kind,
    required this.color,
  });

  final AuthFieldGlyphKind kind;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.1
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    switch (kind) {
      case AuthFieldGlyphKind.email:
        final rect = RRect.fromRectAndRadius(
          Rect.fromLTWH(
            size.width * 0.08,
            size.height * 0.2,
            size.width * 0.84,
            size.height * 0.6,
          ),
          Radius.circular(size.width * 0.08),
        );
        canvas.drawRRect(rect, stroke);
        final flap = Path()
          ..moveTo(size.width * 0.14, size.height * 0.28)
          ..lineTo(size.width * 0.5, size.height * 0.56)
          ..lineTo(size.width * 0.86, size.height * 0.28);
        canvas.drawPath(flap, stroke);
        final base = Path()
          ..moveTo(size.width * 0.16, size.height * 0.72)
          ..lineTo(size.width * 0.38, size.height * 0.48);
        canvas.drawPath(base, stroke);
        final base2 = Path()
          ..moveTo(size.width * 0.84, size.height * 0.72)
          ..lineTo(size.width * 0.62, size.height * 0.48);
        canvas.drawPath(base2, stroke);
      case AuthFieldGlyphKind.password:
        final body = RRect.fromRectAndRadius(
          Rect.fromLTWH(
            size.width * 0.18,
            size.height * 0.42,
            size.width * 0.64,
            size.height * 0.42,
          ),
          Radius.circular(size.width * 0.08),
        );
        canvas.drawRRect(body, stroke);
        final shackle = Path()
          ..moveTo(size.width * 0.32, size.height * 0.42)
          ..lineTo(size.width * 0.32, size.height * 0.3)
          ..quadraticBezierTo(
            size.width * 0.32,
            size.height * 0.12,
            size.width * 0.5,
            size.height * 0.12,
          )
          ..quadraticBezierTo(
            size.width * 0.68,
            size.height * 0.12,
            size.width * 0.68,
            size.height * 0.3,
          )
          ..lineTo(size.width * 0.68, size.height * 0.42);
        canvas.drawPath(shackle, stroke);
        final fill = Paint()
          ..color = color
          ..style = PaintingStyle.fill;
        canvas.drawCircle(
          Offset(size.width * 0.5, size.height * 0.58),
          size.width * 0.06,
          fill,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(
              size.width * 0.47,
              size.height * 0.58,
              size.width * 0.06,
              size.height * 0.12,
            ),
            Radius.circular(size.width * 0.02),
          ),
          fill,
        );
    }
  }

  @override
  bool shouldRepaint(covariant _AuthFieldGlyphPainter oldDelegate) {
    return oldDelegate.kind != kind || oldDelegate.color != color;
  }
}
