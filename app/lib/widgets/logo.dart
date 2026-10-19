import 'package:flutter/material.dart';

import '../theme.dart';

/// Verlium mark: a rounded "page" with a spark, in our own colours (no Google branding).
class VerliumLogo extends StatelessWidget {
  final double size;
  final bool showText;
  const VerliumLogo({super.key, this.size = 32, this.showText = false});

  @override
  Widget build(BuildContext context) {
    final v = context.v;
    final mark = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF4259FF), Color(0xFF9B6BFF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(size * .3),
      ),
      child: Icon(Icons.auto_stories_rounded, color: Colors.white, size: size * .6),
    );
    if (!showText) return mark;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      mark,
      SizedBox(width: size * .3),
      Text('Verlium', style: vText(23, 29, weight: FontWeight.w500, color: v.textTitle)),
    ]);
  }
}
