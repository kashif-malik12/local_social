import 'package:flutter/material.dart';

import 'brand_wordmark.dart';

class BrandLockup extends StatelessWidget {
  const BrandLockup({
    super.key,
    this.height = 44,
  });

  final double height;

  @override
  Widget build(BuildContext context) {
    final iconSize = height;
    final fontSize = height * 0.78;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        BrandMark(size: iconSize),
        SizedBox(width: height * 0.28),
        BrandWordmark(
          fontSize: fontSize,
          color: Colors.white,
          accentColor: const Color(0xFFFFD27A),
          showIcon: false,
        ),
      ],
    );
  }
}
