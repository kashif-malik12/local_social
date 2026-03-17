import 'package:flutter/material.dart';

class BrandMark extends StatelessWidget {
  const BrandMark({
    super.key,
    this.size = 28,
  });

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.32),
        gradient: const LinearGradient(
          colors: [Color(0xFF08675E), Color(0xFF199081)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF08675E).withValues(alpha: 0.18),
            blurRadius: size * 0.3,
            offset: Offset(0, size * 0.12),
          ),
        ],
      ),
      alignment: Alignment.center,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          Container(
            width: size * 0.46,
            height: size * 0.46,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.5),
                width: size * 0.04,
              ),
            ),
          ),
          Text(
            'A',
            style: TextStyle(
              fontSize: size * 0.58,
              fontWeight: FontWeight.w900,
              color: const Color(0xFFF5EFE5),
              height: 1,
            ),
          ),
          Positioned(
            right: size * 0.12,
            bottom: size * 0.09,
            child: Container(
              width: size * 0.24,
              height: size * 0.24,
              decoration: BoxDecoration(
                color: const Color(0xFFE8A74A),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFE8A74A).withValues(alpha: 0.28),
                    blurRadius: size * 0.08,
                  ),
                ],
              ),
              child: Center(
                child: Container(
                  width: size * 0.09,
                  height: size * 0.09,
                  decoration: const BoxDecoration(
                    color: Color(0xFF08675E),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class BrandWordmark extends StatelessWidget {
  final double fontSize;
  final Color color;
  final Color accentColor;
  final FontWeight fontWeight;
  final double letterSpacing;
  final bool italic;
  final bool showIcon;

  const BrandWordmark({
    super.key,
    this.fontSize = 24,
    this.color = const Color(0xFF12211D),
    this.accentColor = const Color(0xFFCC7A00),
    this.fontWeight = FontWeight.w800,
    this.letterSpacing = -1.1,
    this.italic = false,
    this.showIcon = true,
  });

  @override
  Widget build(BuildContext context) {
    final baseStyle = TextStyle(
      fontSize: fontSize,
      height: 0.96,
      fontWeight: fontWeight,
      letterSpacing: letterSpacing,
      color: color,
      shadows: [
        BoxShadow(
          color: color.withValues(alpha: 0.08),
          blurRadius: fontSize * 0.08,
          offset: Offset(0, fontSize * 0.04),
        ),
      ],
    );
    final accentStyle = baseStyle.copyWith(
      color: accentColor,
      fontWeight: FontWeight.w900,
    );

    final wordmark = Text.rich(
      TextSpan(
        children: [
          TextSpan(text: 'Allon', style: baseStyle),
          TextSpan(text: 'ssy', style: accentStyle),
          TextSpan(text: '!', style: accentStyle.copyWith(letterSpacing: -0.2)),
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      softWrap: false,
      style: baseStyle,
    );

    if (!showIcon) return wordmark;

    final iconSize = fontSize * 1.25;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        BrandMark(size: iconSize),
        SizedBox(width: fontSize * 0.34),
        wordmark,
      ],
    );
  }
}
